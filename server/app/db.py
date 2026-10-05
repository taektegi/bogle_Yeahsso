"""Postgres 연결 (psycopg 3, 동기 연결 풀).

쿼리는 `app/repositories/` 아래에서만 작성한다. 라우터는 repository만 부른다.

서버는 DB에 직접 연결하므로 RLS를 거치지 않는다 (RLS는 앱이 Supabase로 직접 읽을 때의 안전장치).
그래서 **모든 repository 함수는 `user_id`를 인자로 받고 쿼리에서 반드시 소유자로 거른다** (FR-01.4).
"""

import logging
from collections.abc import Iterator
from contextlib import contextmanager
from typing import Annotated

import psycopg
from fastapi import Depends, Request
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool, PoolTimeout

from app.config import Settings
from app.errors import service_unavailable

logger = logging.getLogger(__name__)

_CONNECT_TIMEOUT_SECONDS = 5


class Database:
    """연결 풀을 감싼다. 연결을 얻지 못하면 503(retryable)으로 바꿔 준다."""

    def __init__(self, pool: ConnectionPool) -> None:
        self._pool = pool

    @contextmanager
    def connection(self) -> Iterator[psycopg.Connection]:
        """블록이 끝나면 커밋하고, 예외가 나면 롤백한다. 행은 dict로 돌려준다."""
        try:
            with self._pool.connection(timeout=_CONNECT_TIMEOUT_SECONDS) as conn:
                yield conn
        except (PoolTimeout, psycopg.OperationalError) as exc:
            logger.error("database unavailable: %s", type(exc).__name__)
            raise service_unavailable() from None

    def close(self) -> None:
        self._pool.close()


def create_database(settings: Settings) -> Database | None:
    """DATABASE_URL이 없으면 None. 서버는 뜨지만 DB가 필요한 API는 503을 돌려준다."""
    if settings.database_url is None:
        logger.warning("DATABASE_URL is not set; database-backed APIs will return 503")
        return None
    pool = ConnectionPool(
        settings.database_url.get_secret_value(),
        min_size=1,
        max_size=10,
        # Supabase pooler(transaction mode)는 prepared statement를 지원하지 않는다.
        kwargs={"row_factory": dict_row, "prepare_threshold": None},
        open=False,
    )
    # 서버 시작 때 DB가 잠시 없어도 뜨도록 기다리지 않는다. 연결은 백그라운드에서 재시도한다.
    pool.open(wait=False)
    return Database(pool)


def get_database(request: Request) -> Database:
    database: Database | None = getattr(request.app.state, "database", None)
    if database is None:
        logger.error("database is not configured")
        raise service_unavailable()
    return database


DatabaseDep = Annotated[Database, Depends(get_database)]
