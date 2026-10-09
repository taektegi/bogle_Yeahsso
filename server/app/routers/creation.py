"""FR-03~05: 원본 업로드, 비동기 생성·조회·취소, 초기 설정·친구 저장."""

from datetime import UTC, datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, File, Response, UploadFile

from app.assets import ImageRef, image_refs
from app.auth import CurrentUserDep
from app.config import Settings, get_settings
from app.db import DatabaseDep
from app.errors import ERROR_RESPONSES, ApiError, service_unavailable
from app.friend_settings import SaveFriendIn
from app.idempotency import IdempotencyKeyHeader
from app.images import MAX_UPLOAD_BYTES, InvalidImage, open_image
from app.personality import PERSONALITY_TYPES
from app.rate_limit import limit_uploads
from app.repositories.characters import CharacterRepositoryDep
from app.repositories.creation import CreationRepository
from app.routers.characters import CharacterOut, _assets_of, _to_out
from app.schemas import CamelModel
from app.storage import StorageDep, StorageError

router = APIRouter(tags=["creation"], responses=ERROR_RESPONSES)


class GenerationIn(CamelModel):
    source_asset_id: UUID
    source_type: Literal["drawing", "photo"]


class JobError(CamelModel):
    code: str
    message: str
    retryable: bool


class GenerationOut(CamelModel):
    job_id: UUID
    status: Literal["queued", "processing", "succeeded", "failed", "cancelled"]
    source_asset_id: UUID
    created_at: datetime
    updated_at: datetime
    poll_after_ms: int | None = None
    art: ImageRef | None = None
    thumbnail: ImageRef | None = None
    accent_argb: int | None = None
    error: JobError | None = None


def job_out(repo, storage, user_id, row):
    result = GenerationOut(
        job_id=row["id"],
        status=row["status"],
        source_asset_id=row["source_asset_id"],
        created_at=row["created_at"].astimezone(UTC),
        updated_at=row["updated_at"].astimezone(UTC),
    )
    if row["status"] in ("queued", "processing"):
        result.poll_after_ms = 2000
    elif row["status"] == "failed":
        result.error = JobError(
            code=row["error_code"], message=row["error_message"], retryable=row["error_retryable"]
        )
    elif row["status"] == "succeeded":
        refs = image_refs(storage, repo.result_assets(user_id, row))
        if len(refs) != 2:
            raise service_unavailable()
        result.art, result.thumbnail = refs[row["art_asset_id"]], refs[row["thumbnail_asset_id"]]
        result.accent_argb = row["accent_argb"]
    return result


@router.post(
    "/assets",
    status_code=201,
    response_model=ImageRef,
    dependencies=[Depends(limit_uploads)],
    summary="그림·사진 원본 업로드",
)
def upload_asset(
    user: CurrentUserDep, db: DatabaseDep, storage: StorageDep, file: Annotated[UploadFile, File()]
):
    data = file.file.read(MAX_UPLOAD_BYTES + 1)
    if len(data) > MAX_UPLOAD_BYTES:
        raise ApiError(413, "file_too_large", "10MiB 이하의 이미지를 올려 주세요.")
    try:
        image = open_image(data)
    except InvalidImage as exc:
        raise ApiError(422, "invalid_source_image", str(exc)) from None
    content_type = "image/png" if image.format == "PNG" else "image/jpeg"
    repo = CreationRepository(db)
    asset = repo.add_asset(user.id, "source", data, content_type, image.width, image.height)
    try:
        storage.upload(asset.storage_path, data, content_type)
        refs = image_refs(storage, [asset])
        if asset.id not in refs:
            raise StorageError("uploaded file unavailable")
        return refs[asset.id]
    except (StorageError, ApiError):
        repo.discard_assets(user.id, [asset.id])
        raise service_unavailable() from None


@router.post(
    "/generations",
    status_code=202,
    response_model=GenerationOut,
    response_model_exclude_none=True,
    summary="친구 생성 작업 요청",
)
def create_generation(
    payload: GenerationIn,
    user: CurrentUserDep,
    db: DatabaseDep,
    storage: StorageDep,
    key: IdempotencyKeyHeader,
    response: Response,
    settings: Annotated[Settings, Depends(get_settings)],
):
    repo = CreationRepository(db)
    # 키가 없으면 유료 작업을 대기열에 쌓지 않는다. 재조회·취소는 계속 가능하다.
    if settings.openrouter_api_key is None:
        raise service_unavailable()
    row, new = repo.enqueue(user.id, payload.source_asset_id, payload.source_type, key)
    response.status_code = 202 if new else 200
    return job_out(repo, storage, user.id, row)


@router.get(
    "/generations/{job_id}",
    response_model=GenerationOut,
    response_model_exclude_none=True,
    summary="친구 생성 상태 조회",
)
def get_generation(job_id: UUID, user: CurrentUserDep, db: DatabaseDep, storage: StorageDep):
    repo = CreationRepository(db)
    return job_out(repo, storage, user.id, repo.job(user.id, job_id))


@router.post(
    "/generations/{job_id}/cancel",
    response_model=GenerationOut,
    response_model_exclude_none=True,
    summary="친구 생성 취소",
)
def cancel_generation(job_id: UUID, user: CurrentUserDep, db: DatabaseDep, storage: StorageDep):
    repo = CreationRepository(db)
    return job_out(repo, storage, user.id, repo.cancel(user.id, job_id))


class PersonalityOut(CamelModel):
    code: str
    label: str


class PersonalityListOut(CamelModel):
    items: list[PersonalityOut]


@router.get("/personality-types", response_model=PersonalityListOut, summary="성격 선택지")
def list_personalities(user: CurrentUserDep):
    return PersonalityListOut(
        items=[PersonalityOut(code=p.code, label=p.label) for p in PERSONALITY_TYPES]
    )


@router.post(
    "/characters", status_code=201, response_model=CharacterOut, summary="친구 초기 설정 저장"
)
def save_character(
    payload: SaveFriendIn,
    user: CurrentUserDep,
    db: DatabaseDep,
    storage: StorageDep,
    repo: CharacterRepositoryDep,
    key: IdempotencyKeyHeader,
    response: Response,
):
    character_id, new = CreationRepository(db).save_friend(user.id, payload, key)
    record = repo.get_for_user(user.id, character_id)
    out = _to_out(record, image_refs(storage, _assets_of([record]))) if record else None
    if out is None:
        raise service_unavailable()
    response.status_code = 201 if new else 200
    return out
