import os
from collections.abc import Iterator
from pathlib import Path
from uuid import uuid4

import psycopg
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from psycopg import conninfo
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from app.config import Settings, get_settings
from app.db import Database
from app.main import API_PREFIX, create_app
from tests import probe

SUPABASE_URL = "https://proj.supabase.co"
JWT_SECRET = "test-jwt-secret-test-jwt-secret-0123456789"

REPO_ROOT = Path(__file__).resolve().parents[2]
MIGRATIONS_DIR = REPO_ROOT / "supabase" / "migrations"
STUB_SQL = Path(__file__).parent / "sql" / "supabase_stub.sql"


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


# ---------------------------------------------------------------------------
# 실제 PostgreSQL을 쓰는 테스트용 fixture
#
# TEST_DATABASE_URL에 "데이터베이스를 만들 수 있는" 계정의 연결 문자열을 넣으면,
# 테스트 세션마다 임시 DB를 만들어 supabase_stub.sql과 supabase/migrations/*.sql을 적용하고
# 끝나면 지운다. 환경변수가 없으면 이 fixture를 쓰는 테스트는 건너뛴다.
#   예) supabase start 의 로컬 DB: postgresql://postgres:postgres@127.0.0.1:54322/postgres
# ---------------------------------------------------------------------------


@pytest.fixture(scope="session")
def database_url() -> Iterator[str]:
    admin_url = os.environ.get("TEST_DATABASE_URL")
    if not admin_url:
        if os.environ.get("CI"):
            # CI에서 DB 테스트가 조용히 건너뛰어지면 소유권 테스트를 안 돌린 채 통과해 버린다.
            pytest.fail("CI에서는 TEST_DATABASE_URL이 반드시 있어야 합니다", pytrace=False)
        pytest.skip("TEST_DATABASE_URL이 없어 DB 테스트를 건너뜁니다")

    name = f"bogle_test_{uuid4().hex[:10]}"
    test_url = conninfo.make_conninfo(admin_url, dbname=name)
    with psycopg.connect(admin_url, autocommit=True) as admin:
        admin.execute(f'create database "{name}"')
    try:
        with psycopg.connect(test_url, autocommit=True) as conn:
            conn.execute(STUB_SQL.read_text(encoding="utf-8"))
            for migration in sorted(MIGRATIONS_DIR.glob("*.sql")):
                conn.execute(migration.read_text(encoding="utf-8"))
        yield test_url
    finally:
        with psycopg.connect(admin_url, autocommit=True) as admin:
            admin.execute(f'drop database if exists "{name}" with (force)')


@pytest.fixture
def seed_conn(database_url: str) -> Iterator[psycopg.Connection]:
    """테스트 데이터를 넣는 연결 (RLS를 거치지 않는 관리자 연결, 자동 커밋)."""
    with psycopg.connect(database_url, autocommit=True, row_factory=dict_row) as conn:
        yield conn


def _use_seoul_timezone(conn: psycopg.Connection) -> None:
    # DB 세션 시간대가 UTC가 아니어도 서버가 UTC로 응답하는지 확인하기 위해 일부러 바꾼다.
    conn.execute("set timezone to 'Asia/Seoul'")
    conn.commit()


@pytest.fixture
def database(database_url: str) -> Iterator[Database]:
    """서버가 쓰는 것과 같은 방식의 연결 풀 (세션 시간대는 Asia/Seoul)."""
    pool = ConnectionPool(
        database_url,
        min_size=1,
        max_size=3,
        kwargs={"row_factory": dict_row, "prepare_threshold": None},
        configure=_use_seoul_timezone,
        open=True,
    )
    try:
        yield Database(pool)
    finally:
        pool.close()
