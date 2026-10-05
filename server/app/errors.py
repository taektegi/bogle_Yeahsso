"""공통 오류 형식 (NFR-10).

모든 오류 응답은 아래 모양이다. 오류 형식은 앱과의 계약이므로 바꾸면 팀 채널에 알린다.

    {"error": {"code": "not_found", "message": "찾을 수 없어요.", "retryable": false,
               "fieldErrors": {"name": "string_too_short"}, "requestId": "..."}}

- `code`: 영어 snake_case 기계용 코드. 앱은 이것으로 분기한다.
- `message`: 사용자에게 보여 줄 수 있는 한국어 문구.
- `retryable`: 같은 요청을 다시 보내면 성공할 수 있는 일시 오류일 때만 true (FR-04.4).
- `fieldErrors`: 입력 검증 실패 시 {필드 경로: 오류 종류 코드}. 없으면 빈 객체.
- `requestId`: 응답 헤더 X-Request-Id와 같은 값.

OpenAI 오류나 스택 추적은 응답에 넣지 않는다 (NFR-09).
"""

import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import Field
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.request_context import REQUEST_ID_HEADER, get_request_id
from app.schemas import CamelModel

logger = logging.getLogger(__name__)


class ErrorBody(CamelModel):
    code: str
    message: str
    retryable: bool = False
    field_errors: dict[str, str] = Field(default_factory=dict)
    request_id: str


class ErrorResponse(CamelModel):
    error: ErrorBody


# 라우터에서 `responses=ERROR_RESPONSES`로 쓰면 OpenAPI 문서에 오류 형식이 나온다.
ERROR_RESPONSES: dict[int | str, dict] = {
    401: {"model": ErrorResponse, "description": "로그인이 필요하거나 토큰이 올바르지 않음"},
    404: {"model": ErrorResponse, "description": "없거나 내 것이 아닌 리소스"},
    422: {"model": ErrorResponse, "description": "입력값 검증 실패"},
}


class ApiError(Exception):
    """서버가 의도해서 돌려주는 오류. 라우터·서비스 어디서든 raise하면 공통 형식으로 응답한다."""

    def __init__(
        self,
        status_code: int,
        code: str,
        message: str,
        *,
        retryable: bool = False,
        field_errors: dict[str, str] | None = None,
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.retryable = retryable
        self.field_errors = field_errors or {}
        self.headers = headers


_HTTP_ERRORS: dict[int, tuple[str, str]] = {
    400: ("bad_request", "잘못된 요청이에요."),
    401: ("unauthenticated", "로그인이 필요해요."),
    403: ("forbidden", "권한이 없어요."),
    404: ("not_found", "찾을 수 없어요."),
    405: ("method_not_allowed", "허용되지 않는 요청 방식이에요."),
    409: ("conflict", "요청이 현재 상태와 맞지 않아요."),
    429: ("rate_limited", "요청이 너무 많아요. 잠시 후 다시 해 주세요."),
}


def _error_response(
    request: Request,
    status_code: int,
    code: str,
    message: str,
    *,
    retryable: bool = False,
    field_errors: dict[str, str] | None = None,
    headers: dict[str, str] | None = None,
) -> JSONResponse:
    request_id = get_request_id(request)
    body = ErrorResponse(
        error=ErrorBody(
            code=code,
            message=message,
            retryable=retryable,
            field_errors=field_errors or {},
            request_id=request_id,
        )
    )
    response_headers = {REQUEST_ID_HEADER: request_id, **(headers or {})}
    return JSONResponse(
        status_code=status_code,
        content=body.model_dump(by_alias=True),
        headers=response_headers,
    )


def _field_path(loc: tuple) -> str:
    # loc[0]은 오류가 난 위치("body", "query" 등)라서 뺀다.
    path = ".".join(str(part) for part in loc[1:])
    return "_" if not path or path.isdigit() else path


async def _handle_api_error(request: Request, exc: ApiError) -> JSONResponse:
    return _error_response(
        request,
        exc.status_code,
        exc.code,
        exc.message,
        retryable=exc.retryable,
        field_errors=exc.field_errors,
        headers=exc.headers,
    )


async def _handle_http_exception(request: Request, exc: StarletteHTTPException) -> JSONResponse:
    code, message = _HTTP_ERRORS.get(exc.status_code, ("http_error", "요청을 처리하지 못했어요."))
    return _error_response(request, exc.status_code, code, message, headers=exc.headers)


async def _handle_validation_error(request: Request, exc: RequestValidationError) -> JSONResponse:
    field_errors: dict[str, str] = {}
    for err in exc.errors():
        field_errors.setdefault(_field_path(err["loc"]), err["type"])
    return _error_response(
        request,
        422,
        "validation_error",
        "입력값을 확인해 주세요.",
        field_errors=field_errors,
    )


async def _handle_unexpected_error(request: Request, exc: Exception) -> JSONResponse:
    # 원인과 스택 추적은 로그에만 남기고, 사용자 응답에는 내보내지 않는다 (NFR-09).
    logger.error(
        "unhandled error: %s",
        type(exc).__name__,
        exc_info=exc,
        extra={"request_id": get_request_id(request)},
    )
    return _error_response(
        request, 500, "internal_error", "문제가 생겼어요. 잠시 후 다시 시도해 주세요."
    )


def register_exception_handlers(app: FastAPI) -> None:
    app.add_exception_handler(ApiError, _handle_api_error)
    app.add_exception_handler(StarletteHTTPException, _handle_http_exception)
    app.add_exception_handler(RequestValidationError, _handle_validation_error)
    app.add_exception_handler(Exception, _handle_unexpected_error)
