"""사용자별 요청 횟수 제한 (NFR-06). 한도는 API 계약 2절에서 정했다.

라우터에서는 아래 의존성을 `dependencies=[...]`나 인자로 붙인다. 한도를 넘으면 429 `rate_limited`와
`Retry-After`(초) 헤더를 돌려준다.

    @router.post("/generations", dependencies=[Depends(limit_generations)])

주의: 요청 기록을 **서버 프로세스 메모리**에 둔다. 데모 규모(서버 1개, 사용자 수십 명)를
전제로 하며, 서버를 재시작하면 기록이 사라지고 uvicorn 워커를 여러 개 띄우면 워커마다 따로 센다.
"""

import math
import threading
import time
from collections import defaultdict, deque
from collections.abc import Callable
from uuid import UUID

from app.auth import CurrentUserDep
from app.errors import ApiError


class RateLimiter:
    """슬라이딩 윈도우: 최근 `window_seconds`초 안에 `limit`번까지 허용한다."""

    def __init__(
        self,
        name: str,
        limit: int,
        window_seconds: float,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.name = name
        self.limit = limit
        self.window_seconds = window_seconds
        self._clock = clock
        self._hits: dict[UUID, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def check(self, user_id: UUID) -> None:
        """한도 안이면 이번 요청을 기록하고, 넘었으면 429(ApiError)를 낸다.

        거절된 요청은 기록하지 않으므로, 계속 두드려도 제한이 길어지지 않는다.
        """
        now = self._clock()
        with self._lock:
            hits = self._hits[user_id]
            while hits and hits[0] <= now - self.window_seconds:
                hits.popleft()
            if len(hits) >= self.limit:
                retry_after = max(1, math.ceil(hits[0] + self.window_seconds - now))
                raise ApiError(
                    429,
                    "rate_limited",
                    "요청이 너무 많아요. 잠시 후 다시 해 주세요.",
                    retryable=True,
                    headers={"Retry-After": str(retry_after)},
                )
            hits.append(now)


def dependency_for(limiter: RateLimiter) -> Callable[[CurrentUserDep], None]:
    def check(user: CurrentUserDep) -> None:
        limiter.check(user.id)

    return check


# API 계약 2절의 한도 (사용자당)
upload_limiter = RateLimiter("uploads", limit=30, window_seconds=3600)
generation_limiter = RateLimiter("generations", limit=10, window_seconds=3600)
message_limiter = RateLimiter("messages", limit=20, window_seconds=60)

limit_uploads = dependency_for(upload_limiter)
limit_generations = dependency_for(generation_limiter)
limit_messages = dependency_for(message_limiter)
