"""DB 대기열을 처리하는 서버 내부 워커. 임대 잠금과 최대 두 개의 비동기 AI 호출."""

import asyncio
import contextlib
import logging
from datetime import UTC, datetime
from uuid import uuid4

from app.errors import ApiError
from app.image_provider import GenerationError, OpenRouterImages
from app.images import InvalidImage, character_image, input_reference
from app.repositories.creation import CreationRepository
from app.storage import StorageError

logger = logging.getLogger(__name__)


class GenerationWorker:
    def __init__(self, db, storage, settings, provider=None):
        self.repo = CreationRepository(db)
        self.storage = storage
        self.settings = settings
        self.provider = provider or OpenRouterImages(settings)
        self.owner = uuid4()
        self.tasks: dict[asyncio.Task, dict] = {}

    def persist_images(self, job, image):
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
        await asyncio.to_thread(self.persist_images, job, image)

    async def process(self, job):
        logger.info("generation processing jobId=%s", job["id"])
        try:
            await asyncio.wait_for(self.pipeline(job), self.settings.generation_timeout_seconds)
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

    async def run(self):
        acquired = False
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
                    for _ in range(
                        max(0, min(2, self.settings.generation_concurrency) - len(self.tasks))
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
