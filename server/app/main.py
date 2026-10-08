from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import timedelta

from fastapi import FastAPI

from app.cleanup import background_cleanup
from app.config import get_settings
from app.db import create_database
from app.errors import ApiError, register_exception_handlers
from app.request_context import RequestContextMiddleware, configure_logging
from app.routers import api_routers
from app.storage import get_storage
from app.workers import background_workers

API_PREFIX = "/v1"


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    database = create_database(settings)
    app.state.database = database
    try:
        storage = get_storage(settings)
    except ApiError:  # SUPABASE_URL 또는 SUPABASE_SERVICE_ROLE_KEY가 없다
        storage = None
    try:
        # 미사용 에셋을 주기적으로 정리한다. 서버가 종료되면 함께 멈춘다.
        async with (
            background_cleanup(
                database,
                storage,
                interval_seconds=settings.cleanup_interval_seconds,
                retention=timedelta(hours=settings.asset_retention_hours),
            ),
            # 캐릭터 생성·모션 작업 처리기
            background_workers(database, storage, settings),
        ):
            yield
    finally:
        if database is not None:
            database.close()


def create_app() -> FastAPI:
    configure_logging(get_settings().log_level)

    app = FastAPI(
        title="Bogle API",
        version="0.1.0",
        description="보글 백엔드 API. 이 문서(`/docs`)가 앱과 서버 사이의 계약이다.",
        lifespan=lifespan,
    )
    app.add_middleware(RequestContextMiddleware)
    register_exception_handlers(app)
    for router in api_routers:
        app.include_router(router, prefix=API_PREFIX)
    return app


app = create_app()
