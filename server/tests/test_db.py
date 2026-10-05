import psycopg
import pytest
from psycopg_pool import PoolTimeout

from app.db import Database
from app.errors import ApiError


class BrokenPool:
    def __init__(self, error: Exception) -> None:
        self.error = error

    def connection(self, timeout: float):
        raise self.error


def test_pool_timeout_becomes_a_retryable_503() -> None:
    database = Database(BrokenPool(PoolTimeout("no connection available")))
    with pytest.raises(ApiError) as excinfo, database.connection():
        pass
    assert excinfo.value.status_code == 503
    assert excinfo.value.code == "service_unavailable"
    assert excinfo.value.retryable is True


def test_connection_failure_becomes_a_retryable_503() -> None:
    database = Database(BrokenPool(psycopg.OperationalError("connection refused")))
    with pytest.raises(ApiError) as excinfo, database.connection():
        pass
    assert excinfo.value.status_code == 503
    assert excinfo.value.retryable is True


def test_503_does_not_leak_connection_details() -> None:
    error = psycopg.OperationalError("connection to server at 10.0.0.5 failed: password=hunter2")
    with pytest.raises(ApiError) as excinfo, Database(BrokenPool(error)).connection():
        pass
    assert "hunter2" not in excinfo.value.message
    assert "10.0.0.5" not in excinfo.value.message
