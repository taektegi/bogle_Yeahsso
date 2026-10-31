"""공통 이미지 워커의 임대·복구·취소 흐름을 재사용하는 독립 배경 큐."""

import asyncio
import contextlib
import logging
import time

from app.face_analysis import DisabledFaceAnalyzer
from app.generation_worker import GenerationWorker
from app.image_provider import GenerationError
from app.images import InvalidImage, input_reference
from app.repositories.window_views import WindowViewRepository
from app.storage import StorageError
from app.window_images import SIZE, day_prompt, window_png

logger = logging.getLogger(__name__)


class WindowWorker(GenerationWorker):
    def __init__(self, db, storage, settings, provider=None):
        # 상위 워커 수명주기를 공유하지만 배경 호출은 한 장씩만 처리한다.
        window_settings = settings.model_copy(
            update={
                "generation_timeout_seconds": settings.window_generation_timeout_seconds,
                "generation_concurrency": 1,
            }
        )
        super().__init__(
            db, storage, window_settings, provider=provider, analyzer=DisabledFaceAnalyzer()
        )
        self.repo = WindowViewRepository(db)

    def persist_day(self, job, day):
        assets = []
        try:
            asset = self.repo.add_asset(job["user_id"], "background", day, "image/png", *SIZE)
            assets.append(asset)
            self.storage.upload(asset.storage_path, day, "image/png")
            if self.storage.download(asset.storage_path) != day:
                raise StorageError("background readback mismatch")
            if not self.repo.finish(
                job, self.owner, assets[0], self.settings.generation_timeout_seconds
            ):
                raise GenerationError("generation_interrupted", "배경 만들기가 중단됐어요.", True)
        except Exception:
            if assets:
                self.repo.discard_assets(job["user_id"], [a.id for a in assets])
            raise

    async def pipeline(self, job):
        started = time.monotonic()
        # 저장·읽기 검증을 마친 캐릭터 PNG만 소유자 경로에서 읽는다.
        # 재시작 후에도 같은 아트를 쓰며 친구 설정 조회나 별도 분석 호출은 하지 않는다.
        art = await asyncio.to_thread(self.repo.asset, job["user_id"], job["source_asset_id"])
        data = await asyncio.to_thread(self.storage.download, art.storage_path)
        reference = await asyncio.to_thread(input_reference, data)
        try:
            day_source = await self.provider.generate_window(reference, day_prompt())
            logger.info(
                "window image received jobId=%s elapsedMs=%d",
                job["id"],
                int((time.monotonic() - started) * 1000),
            )
            day = await asyncio.to_thread(window_png, day_source)
        except InvalidImage:
            raise GenerationError(
                "generation_invalid_result",
                "창문에 맞는 배경을 만들지 못했어요. 다시 시도해 주세요.",
                True,
            ) from None
        await asyncio.to_thread(self.persist_day, job, day)
        logger.info(
            "window published jobId=%s elapsedMs=%d",
            job["id"],
            int((time.monotonic() - started) * 1000),
        )


@contextlib.asynccontextmanager
async def background_windows(db, storage, settings):
    if db is None or storage is None or not settings.openrouter_api_key:
        yield
        return
    task = asyncio.create_task(WindowWorker(db, storage, settings).run())
    try:
        yield
    finally:
        task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await task
