"""테스트 전용 라우터. 인증·오류 형식·검증을 실제 앱 경로로 확인하기 위해 테스트에서만 붙인다."""

from fastapi import APIRouter
from pydantic import Field

from app.auth import CurrentUserDep
from app.errors import ApiError
from app.schemas import CamelModel

router = APIRouter(prefix="/_probe")


class EchoIn(CamelModel):
    friend_name: str = Field(min_length=2)
    favorite_things: list[str] = Field(min_length=1)


@router.get("/me")
def me(user: CurrentUserDep) -> dict[str, str]:
    return {"userId": str(user.id)}


@router.post("/echo")
def echo(body: EchoIn) -> EchoIn:
    return body


@router.get("/api-error")
def api_error() -> None:
    raise ApiError(404, "friend_not_found", "친구를 찾을 수 없어요.")


@router.get("/retryable")
def retryable() -> None:
    raise ApiError(503, "temporarily_unavailable", "잠시 후 다시 시도해 주세요.", retryable=True)


@router.get("/boom")
def boom() -> None:
    raise RuntimeError("secret internal detail: sk-should-never-leak")
