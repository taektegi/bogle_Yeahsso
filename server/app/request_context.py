"""요청마다 requestId를 붙이고 접근 로그를 남긴다 (NFR-09).

로그에는 메서드·경로·상태 코드·처리 시간만 남기고, 요청 본문과 쿼리 문자열은 남기지 않는다 (NFR-05).
"""

import logging
import re
import time
from contextvars import ContextVar
from uuid import uuid4

from starlette.datastructures import Headers, MutableHeaders
from starlette.requests import Request
from starlette.types import ASGIApp, Message, Receive, Scope, Send

REQUEST_ID_HEADER = "X-Request-Id"
_VALID_REQUEST_ID = re.compile(r"[A-Za-z0-9_-]{8,64}")

request_id_var: ContextVar[str] = ContextVar("request_id", default="-")
logger = logging.getLogger("app.access")


def get_request_id(request: Request) -> str:
    return getattr(request.state, "request_id", None) or request_id_var.get()


class RequestIdFilter(logging.Filter):
    """모든 로그 줄에 현재 requestId를 붙인다. `extra={"request_id": ...}`가 있으면 그것을 쓴다."""

    def filter(self, record: logging.LogRecord) -> bool:
        if not getattr(record, "request_id", None):
            record.request_id = request_id_var.get()
        return True


def configure_logging(level: str = "INFO") -> None:
    handler = logging.StreamHandler()
    handler.addFilter(RequestIdFilter())
    handler.setFormatter(
        logging.Formatter("%(asctime)s %(levelname)s [%(request_id)s] %(name)s: %(message)s")
    )
    app_logger = logging.getLogger("app")
    app_logger.handlers = [handler]
    app_logger.setLevel(level.upper())


class RequestContextMiddleware:
    """클라이언트가 보낸 X-Request-Id를 받아들이거나 새로 만들고, 응답 헤더에 돌려준다."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        incoming = Headers(scope=scope).get(REQUEST_ID_HEADER.lower())
        request_id = incoming if incoming and _VALID_REQUEST_ID.fullmatch(incoming) else uuid4().hex
        scope.setdefault("state", {})["request_id"] = request_id
        token = request_id_var.set(request_id)

        status_code = 500
        started = time.perf_counter()

        async def send_with_request_id(message: Message) -> None:
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = message["status"]
                MutableHeaders(scope=message)[REQUEST_ID_HEADER] = request_id
            await send(message)

        try:
            await self.app(scope, receive, send_with_request_id)
        finally:
            logger.info(
                "%s %s -> %s (%.1fms)",
                scope["method"],
                scope["path"],
                status_code,
                (time.perf_counter() - started) * 1000,
            )
            request_id_var.reset(token)
