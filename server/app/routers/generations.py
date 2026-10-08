"""캐릭터 생성 작업: 시작·조회·취소 (FR-04, API 계약 3.3절).

작업은 서버 안의 처리기(app/workers.py)가 처리한다. 앱은 `pollAfterMs`(2초)마다 조회한다.
실패 코드는 응답 본문의 `error`로 내려간다 (HTTP 오류가 아니다).

| error.code | 뜻 | retryable |
|---|---|---|
| generation_rejected | AI가 캐릭터를 만들지 못함·안전 정책 거절 | false |
| invalid_source_image | 그림을 읽을 수 없음·빈 그림 | false |
| generation_timeout | 4분 안에 끝나지 않음 | true |
| generation_unavailable | 잠시 AI·저장소를 쓸 수 없음 | true |
"""

from datetime import datetime
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Response

from app.assets import ImageRef, image_refs
from app.auth import CurrentUserDep
from app.errors import ERROR_RESPONSES, ApiError
from app.idempotency import IdempotencyKeyHeader, fingerprint
from app.rate_limit import limit_generations
from app.repositories.generations import WAITING, GenerationRepositoryDep, JobRecord
from app.schemas import CamelModel
from app.storage import StorageClient, StorageDep

router = APIRouter(prefix="/generations", tags=["generations"], responses=ERROR_RESPONSES)

POLL_AFTER_MS = 2000

FAILURE_MESSAGES = {
    "generation_rejected": "이 그림으로는 친구를 만들지 못했어요. 다른 그림으로 해 볼까요?",
    "invalid_source_image": "그림을 알아보기 어려워요. 다시 그리거나 다른 사진을 골라 주세요.",
    "generation_timeout": "친구를 만드는 데 시간이 너무 걸렸어요. 다시 해 볼까요?",
    "generation_unavailable": "잠시 후 다시 시도해 주세요.",
}


class GenerationIn(CamelModel):
    source_asset_id: UUID
    source_type: Literal["drawing", "photo"]


class GenerationError(CamelModel):
    code: str
    message: str
    retryable: bool


class GenerationOut(CamelModel):
    job_id: UUID
    status: str
    source_asset_id: UUID
    created_at: datetime
    updated_at: datetime
    # queued·processing일 때
    poll_after_ms: int | None = None
    # succeeded일 때
    art: ImageRef | None = None
    thumbnail: ImageRef | None = None
    accent_argb: int | None = None
    # 얼굴 지도 (앱 face.json과 같은 형식). 앱이 얼굴을 움직이고 간식을 입에 댄다.
    face: dict | None = None
    # failed일 때
    error: GenerationError | None = None


class CancelOut(CamelModel):
    job_id: UUID
    status: str


def to_out(job: JobRecord, storage: StorageClient) -> GenerationOut:
    out = GenerationOut(
        job_id=job.id,
        status=job.status,
        source_asset_id=job.source_asset_id,
        created_at=job.created_at,
        updated_at=job.updated_at,
    )
    if job.status in WAITING:
        out.poll_after_ms = POLL_AFTER_MS
    elif job.status == "succeeded":
        assets = [a for a in (job.art, job.thumbnail) if a is not None]
        refs = image_refs(storage, assets)
        if job.art is None or job.thumbnail is None or job.art.id not in refs:
            # 결과 파일을 읽을 수 없으면 성공으로 내려 주지 않는다 (FR-04.3).
            out.status = "failed"
            out.error = GenerationError(
                code="generation_unavailable",
                message=FAILURE_MESSAGES["generation_unavailable"],
                retryable=True,
            )
            return out
        out.art = refs[job.art.id]
        out.thumbnail = refs.get(job.thumbnail.id)
        out.accent_argb = job.accent_argb
        out.face = job.face
    elif job.status == "failed":
        code = job.error_code or "generation_unavailable"
        out.error = GenerationError(
            code=code,
            message=FAILURE_MESSAGES.get(code, FAILURE_MESSAGES["generation_unavailable"]),
            retryable=bool(job.error_retryable),
        )
    return out


@router.post(
    "",
    status_code=202,
    response_model=GenerationOut,
    response_model_exclude_none=True,
    summary="캐릭터 생성 시작",
    dependencies=[Depends(limit_generations)],
)
def start(
    body: GenerationIn,
    idempotency_key: IdempotencyKeyHeader,
    user: CurrentUserDep,
    repo: GenerationRepositoryDep,
    storage: StorageDep,
    response: Response,
) -> GenerationOut:
    """같은 키로 다시 보내면 같은 작업을 200과 현재 상태로 돌려준다."""
    job, created = repo.create(
        user.id,
        source_asset_id=body.source_asset_id,
        source_type=body.source_type,
        idempotency_key=idempotency_key,
        request_fingerprint=fingerprint(body),
    )
    if not created:
        response.status_code = 200
    return to_out(job, storage)


@router.get(
    "/{job_id}",
    response_model=GenerationOut,
    response_model_exclude_none=True,
    summary="캐릭터 생성 상태",
)
def status(
    job_id: UUID, user: CurrentUserDep, repo: GenerationRepositoryDep, storage: StorageDep
) -> GenerationOut:
    job = repo.get_for_user(user.id, job_id)
    if job is None:
        raise ApiError(404, "not_found", "작업을 찾을 수 없어요.")
    return to_out(job, storage)


@router.post("/{job_id}/cancel", response_model=CancelOut, summary="캐릭터 생성 취소")
def cancel(job_id: UUID, user: CurrentUserDep, repo: GenerationRepositoryDep) -> CancelOut:
    """서버가 판단한 최종 상태를 돌려준다. 이미 끝난 작업이면 그 상태 그대로다."""
    result = repo.cancel_for_user(user.id, job_id)
    if result is None:
        raise ApiError(404, "not_found", "작업을 찾을 수 없어요.")
    job, _ = result
    return CancelOut(job_id=job.id, status=job.status)
