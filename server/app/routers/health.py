from typing import Literal

from fastapi import APIRouter

from app.schemas import CamelModel

router = APIRouter(tags=["health"])


class HealthResponse(CamelModel):
    status: Literal["ok"]


@router.get("/health", response_model=HealthResponse, summary="서버 상태 확인")
def health() -> HealthResponse:
    """로그인 없이 호출할 수 있다. 배포 확인과 앱의 서버 연결 확인에 쓴다."""
    return HealthResponse(status="ok")
