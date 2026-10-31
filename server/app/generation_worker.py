"""DB 대기열을 처리하는 서버 내부 워커. 임대 잠금과 최대 두 개의 비동기 AI 호출.

그림 생성이 끝나면 작업을 먼저 성공으로 기록하고, 얼굴 분석은 그 뒤에 이어서 한다.
아이는 얼굴 분석을 기다리지 않고 친구 설정 화면으로 넘어간다. 얼굴 분석만 남은 작업은
생성 동시 처리 수(최대 2)에 세지 않으므로 다음 생성 작업이 바로 시작된다.
"""

import asyncio
import contextlib
import logging
from datetime import UTC, datetime
from uuid import uuid4

from app.errors import ApiError
from app.face_analysis import (
    DisabledFaceAnalyzer,
    analyze_face_best_effort,
    build_face_analyzer,
    face_to_json,
)
from app.image_provider import GenerationError, OpenRouterImages
from app.images import InvalidImage, character_image, input_reference
from app.repositories.creation import CreationRepository
from app.storage import StorageError

logger = logging.getLogger(__name__)

# 동시에 진행하는 얼굴 분석 수. 분리 전과 같은 최대 2개로 비용·스레드 사용량을 유지한다.
FACE_CONCURRENCY = 2


class GenerationWorker:
    def __init__(self, db, storage, settings, provider=None, analyzer=None):
        self.repo = CreationRepository(db)
        self.storage = storage
        self.settings = settings
        self.provider = provider or OpenRouterImages(settings)
        self.analyzer = analyzer if analyzer is not None else build_face_analyzer(settings)
        self.owner = uuid4()
        self.tasks: dict[asyncio.Task, dict] = {}
        # 그림을 성공으로 기록한 뒤 얼굴 분석만 남은 작업. 생성 슬롯을 차지하지 않는다.
        self.describing: set[asyncio.Task] = set()
        # run()이 자기 이벤트 루프에서 만든다. process()를 직접 부르면 제한 없이 실행한다.
        self.face_slots: asyncio.Semaphore | None = None

    @property
    def describes_faces(self) -> bool:
        return not isinstance(self.analyzer, DisabledFaceAnalyzer)

    def persist_images(self, job, image, face_status="pending"):
        assets = []
        try:
            for kind, data, width, height in (
                ("art", image.art, image.width, image.height),
                ("thumbnail", image.thumbnail, 256, 256),
            ):
                asset = self.repo.add_asset(job["user_id"], kind, data, "image/png", width, height)
                assets.append(asset)
                self.storage.upload(asset.storage_path, data, "image/png")
                # 실제 읽은 바이트와 동일한지까지 검사한 뒤 성공을 기록한다.
                if self.storage.download(asset.storage_path) != data:
                    raise StorageError("storage readback mismatch")
            accepted = self.repo.finish(
                job["user_id"],
                job["id"],
                self.owner,
                assets[0],
                assets[1],
                image.accent_argb,
                self.settings.generation_timeout_seconds,
                face_status=face_status,
            )
            if not accepted:
                elapsed = (datetime.now(UTC) - job["started_at"]).total_seconds()
                if elapsed >= self.settings.generation_timeout_seconds:
                    raise GenerationError(
                        "generation_timeout", "생성 시간이 길어져 중단됐어요.", True
                    )
                raise GenerationError(
                    "generation_interrupted", "작업이 중단됐어요. 다시 시도해 주세요.", True
                )
        except Exception:
            if assets:
                self.repo.discard_assets(job["user_id"], [a.id for a in assets])
            raise

    async def analyze_face(self, job, image):
        # 작업은 이미 성공했으므로 그림 생성의 4분 한도와 별도로 최대 120초를 기다린다.
        budget = min(120, self.settings.face_analysis_timeout_seconds)
        if budget <= 0:
            return None
        try:
            face = await asyncio.wait_for(
                asyncio.to_thread(
                    analyze_face_best_effort,
                    self.analyzer,
                    image.art,
                    width=image.width,
                    height=image.height,
                    content_type="image/png",
                ),
                timeout=budget,
            )
            return face_to_json(face)
        except TimeoutError:
            # 늦게 끝난 스레드의 결과는 사용하지 않는다. 작업은 이미 성공으로 기록돼 있다.
            logger.info("face analysis timed out jobId=%s", job["id"])
            return None

    async def describe_face(self, job, image):
        """성공한 작업의 얼굴 좌표를 분석해 작업과 저장된 친구에 채운다.

        분석이 실패해도 작업의 성공은 그대로 둔다.
        """
        task = asyncio.current_task()
        self.describing.add(task)
        try:
            async with self.face_slots or contextlib.nullcontext():
                face = await self.analyze_face(job, image)
            recorded = await asyncio.to_thread(
                self.repo.finish_face, job["user_id"], job["id"], self.owner, face
            )
            logger.info(
                "face analysis finished jobId=%s found=%s recorded=%s",
                job["id"],
                face is not None,
                recorded,
            )
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            # 기록하지 못한 pending 상태는 다음 복구(recover)에서 unavailable로 정리된다.
            logger.warning(
                "face analysis not recorded jobId=%s errorType=%s", job["id"], type(exc).__name__
            )
        finally:
            self.describing.discard(task)

    async def pipeline(self, job):
        source = await asyncio.to_thread(self.repo.source, job["user_id"], job["source_asset_id"])
        data = await asyncio.to_thread(self.storage.download, source.storage_path)
        try:
            reference = await asyncio.to_thread(input_reference, data)
        except InvalidImage:
            raise GenerationError(
                "invalid_source_image", "원본 그림을 읽을 수 없어요.", False
            ) from None
        data = await self.provider.generate(reference)
        try:
            image = await asyncio.to_thread(character_image, data)
        except InvalidImage:
            raise GenerationError(
                "generation_invalid_result", "투명 배경 캐릭터를 만들지 못했어요.", True
            ) from None
        face_status = "pending" if self.describes_faces else "unavailable"
        await asyncio.to_thread(self.persist_images, job, image, face_status)
        return image

    async def process(self, job):
        logger.info("generation processing jobId=%s", job["id"])
        image = None
        try:
            image = await asyncio.wait_for(
                self.pipeline(job), self.settings.generation_timeout_seconds
            )
        except (TimeoutError, GenerationError) as exc:
            if isinstance(exc, TimeoutError):
                exc = GenerationError("generation_timeout", "생성 시간이 길어져 중단됐어요.", True)
            await asyncio.to_thread(
                self.repo.fail,
                job["user_id"],
                job["id"],
                exc.code,
                exc.message,
                exc.retryable,
                self.owner,
            )
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            logger.warning("generation failed jobId=%s errorType=%s", job["id"], type(exc).__name__)
            await asyncio.to_thread(
                self.repo.fail,
                job["user_id"],
                job["id"],
                "generation_unavailable",
                "생성을 완료하지 못했어요. 다시 시도해 주세요.",
                True,
                self.owner,
            )
        logger.info("generation finished jobId=%s", job["id"])
        if image is not None:
            # 생성 성공은 이미 게시됐다. 배경 대기열 등록 실패가 성공을 취소하지 않는다.
            await asyncio.to_thread(self.prefetch_window, job)
        if image is not None and self.describes_faces:
            await self.describe_face(job, image)

    def prefetch_window(self, job):
        """얼굴 분석과 독립적으로 배경을 예약한다. AI 응답은 여기서 기다리지 않는다."""
        if (
            not self.settings.window_prefetch_after_generation
            or not self.settings.openrouter_api_key
        ):
            return
        from app.repositories.window_views import WindowViewRepository

        try:
            WindowViewRepository(self.repo.db).prefetch(job["user_id"], job["id"])
        except Exception as exc:
            logger.warning(
                "window prefetch skipped jobId=%s errorType=%s", job["id"], type(exc).__name__
            )

    async def run(self):
        acquired = False
        self.face_slots = asyncio.Semaphore(FACE_CONCURRENCY)
        try:
            while True:
                try:
                    lease = await asyncio.to_thread(self.repo.acquire_lease, self.owner)
                    if not lease:
                        for task in self.tasks:
                            task.cancel()
                        await asyncio.gather(*self.tasks, return_exceptions=True)
                        self.tasks.clear()
                        acquired = False
                        await asyncio.sleep(2)
                        continue
                    if not acquired:
                        await asyncio.to_thread(self.repo.recover)
                        acquired = True
                    for task, job in list(self.tasks.items()):
                        if task.done():
                            # 예외를 회수해 런타임이 민감한 객체를 출력하지 않게 한다.
                            if not task.cancelled():
                                exc = task.exception()
                                if exc is not None:
                                    await asyncio.to_thread(
                                        self.repo.fail,
                                        job["user_id"],
                                        job["id"],
                                        "generation_unavailable",
                                        "생성을 완료하지 못했어요.",
                                        True,
                                        self.owner,
                                    )
                            self.tasks.pop(task)
                            continue
                        try:
                            current = await asyncio.to_thread(
                                self.repo.job, job["user_id"], job["id"]
                            )
                            if current["status"] in ("cancelled", "failed"):
                                task.cancel()
                        except ApiError as exc:
                            if exc.status_code == 404:
                                # 삭제된 친구의 원본 작업은 다시 게시하지 않는다.
                                task.cancel()
                    # 얼굴 분석만 남은 작업은 이미 성공했으므로 생성 슬롯에서 뺀다.
                    generating = sum(1 for task in self.tasks if task not in self.describing)
                    for _ in range(
                        max(0, min(2, self.settings.generation_concurrency) - generating)
                    ):
                        job = await asyncio.to_thread(self.repo.claim, self.owner)
                        if not job:
                            break
                        self.tasks[asyncio.create_task(self.process(job))] = job
                except Exception as exc:
                    logger.warning("generation worker unavailable errorType=%s", type(exc).__name__)
                await asyncio.sleep(1)
        finally:
            for task in self.tasks:
                task.cancel()
            await asyncio.gather(*self.tasks, return_exceptions=True)
            with contextlib.suppress(Exception):
                await asyncio.to_thread(self.repo.release_lease, self.owner)


@contextlib.asynccontextmanager
async def background_generations(db, storage, settings):
    if db is None or storage is None:
        yield
        return
    worker = GenerationWorker(db, storage, settings)
    task = asyncio.create_task(worker.run())
    try:
        yield
    finally:
        task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await task
