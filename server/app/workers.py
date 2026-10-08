"""생성·모션 작업 처리기 (서버 안에서 도는 백그라운드 작업).

- 생성 처리기 `generation_workers`개: 기다리는 작업을 하나씩 가져가(`for update skip locked`)
  app/generation.py로 처리하고, 결과 그림·썸네일을 Storage에 올린 뒤 작업을 끝낸다.
- 모션 처리기 1개: app/motion.py.
- 감시: 너무 오래 처리 중인 작업을 시간 초과로 끝낸다 (처리기가 멈춘 경우).
- 서버가 시작할 때 이전에 처리 중이던 작업을 다시 줄 세운다 (재시작 복구, FR-10.6).

처리 자체는 동기 코드(OpenAI·Storage·DB)라서 스레드에서 돌린다. 데모 규모(서버 1개)를 전제로
하지만, 작업을 DB에서 잠그고 가져가므로 서버를 여러 개 띄워도 같은 작업을 두 번 처리하지 않는다.
"""

import asyncio
import contextlib
import functools
import logging
from uuid import uuid4

import anyio.to_thread

from app.ai import AiServices, build_ai
from app.config import Settings
from app.db import Database
from app.generation import GenerationFailure, make_character
from app.motion import HttpMotionClient, MotionClient, process_motion
from app.repositories.assets import NewAsset
from app.repositories.generations import GenerationRepository, JobSource
from app.repositories.motions import MotionRepository
from app.storage import StorageClient, StorageError

logger = logging.getLogger(__name__)

_SWEEP_SECONDS = 30
# 처리기가 끝내지 못한 작업을 시간 초과로 보는 여유 (작업 시간 + 이만큼)
_STALE_GRACE_SECONDS = 60


def process_generation(
    work: JobSource,
    *,
    repo: GenerationRepository,
    storage: StorageClient,
    ai: AiServices,
    timeout: float,
) -> str:
    """작업 하나를 끝까지 처리하고 최종 상태를 돌려준다 (succeeded / failed / cancelled)."""
    job = work.job
    try:
        source = storage.download(work.storage_path)
    except StorageError as exc:
        logger.warning("could not read the source of a generation job: %s", exc)
        repo.fail(job.id, code="generation_unavailable", retryable=True)
        return "failed"
    try:
        result = make_character(source, source_type=job.source_type, ai=ai, timeout=timeout)
    except GenerationFailure as failure:
        logger.info("generation job failed: %s", failure.code)
        repo.fail(job.id, code=failure.code, retryable=failure.retryable)
        return "failed"
    except Exception as exc:  # 예상하지 못한 오류도 작업을 실패로 끝내고 처리기는 계속 돈다
        logger.error("generation job crashed: %s", type(exc).__name__, exc_info=exc)
        repo.fail(job.id, code="generation_unavailable", retryable=True)
        return "failed"

    if not repo.is_waiting(job.id):
        return "cancelled"  # 처리하는 사이 취소됐다: 결과를 올리지 않는다

    folder = f"{job.user_id}/generated/{job.id}"
    art = NewAsset(
        id=uuid4(),
        kind="art",
        storage_path=f"{folder}/art.png",
        content_type="image/png",
        byte_size=len(result.art_png),
        width=result.width,
        height=result.height,
    )
    thumbnail = NewAsset(
        id=uuid4(),
        kind="thumbnail",
        storage_path=f"{folder}/thumbnail.png",
        content_type="image/png",
        byte_size=len(result.thumbnail_png),
        width=256,
        height=256,
    )
    try:
        storage.upload(art.storage_path, result.art_png, "image/png")
        storage.upload(thumbnail.storage_path, result.thumbnail_png, "image/png")
    except StorageError as exc:
        logger.warning("could not store a generated character: %s", exc)
        repo.fail(job.id, code="generation_unavailable", retryable=True)
        return "failed"

    if repo.succeed(
        job, art=art, thumbnail=thumbnail, accent_argb=result.accent_argb, face=result.face
    ):
        return "succeeded"
    # 그 사이 취소·시간 초과로 끝났다: 올린 파일을 지운다.
    with contextlib.suppress(StorageError):
        storage.remove([art.storage_path, thumbnail.storage_path])
    return "cancelled"


async def _generation_loop(
    db: Database, storage: StorageClient, settings: Settings, ai: AiServices
) -> None:
    repo = GenerationRepository(db)
    while True:
        try:
            work = await anyio.to_thread.run_sync(repo.claim_next)
            if work is None:
                await asyncio.sleep(settings.worker_poll_seconds)
                continue
            await anyio.to_thread.run_sync(
                functools.partial(
                    process_generation,
                    work,
                    repo=repo,
                    storage=storage,
                    ai=ai,
                    timeout=settings.generation_timeout_seconds,
                )
            )
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            logger.error("generation worker error: %s", type(exc).__name__)
            await asyncio.sleep(max(1.0, settings.worker_poll_seconds))


async def _motion_loop(
    db: Database, storage: StorageClient, settings: Settings, client: MotionClient
) -> None:
    repo = MotionRepository(db)
    while True:
        try:
            work = await anyio.to_thread.run_sync(repo.claim_next)
            if work is None:
                await asyncio.sleep(settings.worker_poll_seconds * 2)
                continue
            await anyio.to_thread.run_sync(
                functools.partial(
                    process_motion,
                    work,
                    repo=repo,
                    storage=storage,
                    client=client,
                    timeout=settings.motion_timeout_seconds,
                    retries=settings.motion_retries,
                )
            )
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            logger.error("motion worker error: %s", type(exc).__name__)
            await asyncio.sleep(max(1.0, settings.worker_poll_seconds))


async def _sweep_loop(db: Database, settings: Settings) -> None:
    generations, motions = GenerationRepository(db), MotionRepository(db)
    while True:
        try:
            await anyio.to_thread.run_sync(
                generations.fail_stale, settings.generation_timeout_seconds + _STALE_GRACE_SECONDS
            )
            await anyio.to_thread.run_sync(
                motions.fail_stale, settings.motion_timeout_seconds + _STALE_GRACE_SECONDS
            )
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            logger.error("job sweep failed: %s", type(exc).__name__)
        await asyncio.sleep(_SWEEP_SECONDS)


async def _recover(db: Database) -> None:
    """서버가 재시작되기 전에 처리 중이던 작업을 다시 줄 세운다."""
    try:
        await anyio.to_thread.run_sync(GenerationRepository(db).requeue_interrupted)
        await anyio.to_thread.run_sync(MotionRepository(db).requeue_interrupted)
    except Exception as exc:
        logger.error("could not recover interrupted jobs: %s", type(exc).__name__)


@contextlib.asynccontextmanager
async def background_workers(
    db: Database | None, storage: StorageClient | None, settings: Settings
):
    """`async with`로 감싸 두면 서버가 끝날 때 처리기도 멈춘다.

    DB·Storage가 없거나 `worker_poll_seconds`가 0이면 아무것도 하지 않는다 (테스트).
    """
    if db is None or storage is None or settings.worker_poll_seconds <= 0:
        logger.info("job workers are disabled")
        yield []
        return
    ai = build_ai(settings)
    # 서버가 뜨는 것을 기다리게 하지 않도록 복구도 백그라운드에서 한다.
    tasks = [asyncio.create_task(_recover(db))]
    tasks += [
        asyncio.create_task(_generation_loop(db, storage, settings, ai))
        for _ in range(max(1, settings.generation_workers))
    ]
    tasks.append(asyncio.create_task(_sweep_loop(db, settings)))
    if settings.motion_service_url:
        client = HttpMotionClient(settings.motion_service_url)
        tasks.append(asyncio.create_task(_motion_loop(db, storage, settings, client)))
    try:
        yield tasks
    finally:
        for task in tasks:
            task.cancel()
        for task in tasks:
            with contextlib.suppress(asyncio.CancelledError):
                await task
