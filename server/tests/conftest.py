import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.config import Settings, get_settings
from app.main import API_PREFIX, create_app
from tests import probe

SUPABASE_URL = "https://proj.supabase.co"
JWT_SECRET = "test-jwt-secret-test-jwt-secret-0123456789"


@pytest.fixture
def settings() -> Settings:
    return Settings(_env_file=None, supabase_url=SUPABASE_URL, supabase_jwt_secret=JWT_SECRET)


@pytest.fixture
def app(settings: Settings) -> FastAPI:
    application = create_app()
    application.dependency_overrides[get_settings] = lambda: settings
    application.include_router(probe.router, prefix=API_PREFIX)
    return application


@pytest.fixture
def client(app: FastAPI) -> TestClient:
    # 처리되지 않은 예외도 실제 서버처럼 500 응답으로 받아 형식을 확인한다.
    return TestClient(app, raise_server_exceptions=False)
