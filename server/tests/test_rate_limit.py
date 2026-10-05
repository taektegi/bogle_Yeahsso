from uuid import UUID, uuid4

import pytest
from fastapi import APIRouter, Depends
from fastapi.testclient import TestClient

from app.errors import ApiError
from app.main import API_PREFIX
from app.rate_limit import (
    RateLimiter,
    dependency_for,
    generation_limiter,
    message_limiter,
    upload_limiter,
)
from tests.tokens import bearer, hs256_token


class FakeClock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += seconds


@pytest.fixture
def clock() -> FakeClock:
    return FakeClock()


def hit(limiter: RateLimiter, user: UUID) -> ApiError | None:
    try:
        limiter.check(user)
    except ApiError as error:
        return error
    return None


def test_requests_within_the_limit_are_allowed(clock) -> None:
    limiter = RateLimiter("t", limit=3, window_seconds=60, clock=clock)
    user = uuid4()

    assert [hit(limiter, user) for _ in range(3)] == [None, None, None]


def test_the_request_over_the_limit_is_rejected_with_retry_after(clock) -> None:
    limiter = RateLimiter("t", limit=2, window_seconds=60, clock=clock)
    user = uuid4()
    hit(limiter, user)
    clock.advance(10)
    hit(limiter, user)
    clock.advance(5)

    error = hit(limiter, user)

    assert error is not None
    assert error.status_code == 429
    assert error.code == "rate_limited"
    assert error.retryable is True
    # 가장 오래된 기록(15초 전)이 60초 창에서 빠지려면 45초가 더 필요하다.
    assert error.headers == {"Retry-After": "45"}


def test_retry_after_is_rounded_up_and_at_least_one(clock) -> None:
    limiter = RateLimiter("t", limit=1, window_seconds=60, clock=clock)
    user = uuid4()
    hit(limiter, user)
    clock.advance(59.2)

    assert hit(limiter, user).headers == {"Retry-After": "1"}


def test_the_window_slides(clock) -> None:
    limiter = RateLimiter("t", limit=2, window_seconds=60, clock=clock)
    user = uuid4()
    hit(limiter, user)
    clock.advance(30)
    hit(limiter, user)
    assert hit(limiter, user) is not None

    clock.advance(30)  # 첫 요청이 창에서 빠진다 (정확히 60초 전)

    assert hit(limiter, user) is None
    assert hit(limiter, user) is not None  # 두 번째 요청은 아직 창 안에 있다


def test_users_are_counted_separately(clock) -> None:
    limiter = RateLimiter("t", limit=1, window_seconds=60, clock=clock)
    a, b = uuid4(), uuid4()

    assert hit(limiter, a) is None
    assert hit(limiter, a) is not None
    assert hit(limiter, b) is None


def test_rejected_requests_do_not_extend_the_lockout(clock) -> None:
    limiter = RateLimiter("t", limit=1, window_seconds=60, clock=clock)
    user = uuid4()
    hit(limiter, user)
    for _ in range(20):
        clock.advance(2)
        assert hit(limiter, user) is not None

    clock.advance(21)  # 첫 요청으로부터 61초

    assert hit(limiter, user) is None


def test_contract_limits() -> None:
    assert (upload_limiter.limit, upload_limiter.window_seconds) == (30, 3600)
    assert (generation_limiter.limit, generation_limiter.window_seconds) == (10, 3600)
    assert (message_limiter.limit, message_limiter.window_seconds) == (20, 60)


def test_limit_applies_through_the_api(app, client: TestClient, clock) -> None:
    limiter = RateLimiter("probe", limit=2, window_seconds=60, clock=clock)
    router = APIRouter()

    @router.get("/_limited", dependencies=[Depends(dependency_for(limiter))])
    def limited() -> dict[str, bool]:
        return {"ok": True}

    app.include_router(router, prefix=API_PREFIX)
    me = bearer(hs256_token())

    assert [client.get("/v1/_limited", headers=me).status_code for _ in range(2)] == [200, 200]
    response = client.get("/v1/_limited", headers=me)

    assert response.status_code == 429
    assert response.headers["retry-after"] == "60"
    error = response.json()["error"]
    assert error["code"] == "rate_limited"
    assert error["retryable"] is True
    # 다른 사용자는 영향이 없다.
    other = bearer(hs256_token(sub="99999999-9999-4999-8999-999999999999"))
    assert client.get("/v1/_limited", headers=other).status_code == 200


def test_login_is_checked_before_the_limit(app, client: TestClient, clock) -> None:
    limiter = RateLimiter("probe", limit=1, window_seconds=60, clock=clock)
    router = APIRouter()

    @router.get("/_limited2", dependencies=[Depends(dependency_for(limiter))])
    def limited() -> dict[str, bool]:
        return {"ok": True}

    app.include_router(router, prefix=API_PREFIX)

    assert client.get("/v1/_limited2").status_code == 401
    assert client.get("/v1/_limited2").status_code == 401  # 비로그인 요청은 한도를 쓰지 않는다
    assert client.get("/v1/_limited2", headers=bearer(hs256_token())).status_code == 200
