"""친구의 선택 창문 배경. 기존 배경은 새 낮 배경이 완성될 때까지 유지한다."""

from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Response

from app.assets import ImageRef, image_refs
from app.auth import CurrentUserDep
from app.config import Settings, get_settings
from app.db import DatabaseDep
from app.errors import ERROR_RESPONSES, ApiError
from app.idempotency import IdempotencyKeyHeader
from app.repositories.window_views import WindowViewRepository
from app.schemas import CamelModel
from app.storage import StorageDep

router = APIRouter(prefix="/characters", tags=["window views"], responses=ERROR_RESPONSES)


class WindowRequest(CamelModel):
    regenerate: bool = False


class WindowError(CamelModel):
    code: str
    message: str
    retryable: bool


class WindowOut(CamelModel):
    status: Literal["missing", "queued", "processing", "succeeded", "failed", "cancelled"]
    job_id: UUID | None = None
    ready_job_id: UUID | None = None
    day: ImageRef | None = None
    night: ImageRef | None = None
    error: WindowError | None = None
    poll_after_ms: int = 2000


def output(repo, user_id, character_id, storage, job=None):
    latest, ready = repo.current(user_id, character_id)
    job = job or latest
    day = night = None
    if ready:
        # 새 작업은 낮 한 장. 이전에 만든 낮·밤 쌍도 계속 읽을 수 있다.
        assets = [repo.asset(user_id, ready["day_asset_id"])]
        if ready["night_asset_id"]:
            assets.append(repo.asset(user_id, ready["night_asset_id"]))
        refs = image_refs(storage, assets)
        day = refs.get(assets[0].id)
        night = refs.get(assets[1].id) if len(assets) > 1 else None
    return WindowOut(
        status=job["status"] if job else "missing",
        job_id=job["id"] if job else None,
        ready_job_id=ready["id"] if ready and day else None,
        day=day,
        night=night,
        error=WindowError(
            code=job["error_code"], message=job["error_message"], retryable=job["error_retryable"]
        )
        if job and job["status"] == "failed"
        else None,
    )


@router.get("/{character_id}/window-view", response_model=WindowOut, summary="창문 배경 상태")
def get_window(
    character_id: UUID, user: CurrentUserDep, db: DatabaseDep, storage: StorageDep
) -> WindowOut:
    return output(WindowViewRepository(db), user.id, character_id, storage)


@router.post(
    "/{character_id}/window-view",
    response_model=WindowOut,
    status_code=202,
    responses={200: {"model": WindowOut, "description": "기존 작업 또는 완성된 배경"}},
    summary="창문 배경 만들기",
)
def create_window(
    character_id: UUID,
    payload: WindowRequest,
    user: CurrentUserDep,
    db: DatabaseDep,
    storage: StorageDep,
    idempotency_key: IdempotencyKeyHeader,
    response: Response,
    settings: Annotated[Settings, Depends(get_settings)],
) -> WindowOut:
    repo = WindowViewRepository(db)
    # 미설정 여부보다 소유권 검사를 먼저 하여 남의 친구 존재를 드러내지 않는다.
    repo.current(user.id, character_id)
    if not settings.openrouter_api_key:
        raise ApiError(
            503, "background_unavailable", "배경 만들기를 잠시 사용할 수 없어요.", retryable=True
        )
    job, new = repo.enqueue(user.id, character_id, idempotency_key, regenerate=payload.regenerate)
    response.status_code = 202 if new else 200
    return output(repo, user.id, character_id, storage, job)
