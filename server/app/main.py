from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.config import get_settings
from app.db import create_database
from app.errors import register_exception_handlers
from app.request_context import RequestContextMiddleware, configure_logging
from app.routers import api_routers

API_PREFIX = "/v1"


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    database = create_database(get_settings())
    app.state.database = database
    try:
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
