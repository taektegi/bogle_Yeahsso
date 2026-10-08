"""그림·사진 업로드와 이미지 URL 갱신 (FR-03, API 계약 3.1–3.2절)."""

from typing import Annotated
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, File, UploadFile

from app.assets import ImageRef, image_refs
from app.auth import CurrentUserDep
from app.errors import ERROR_RESPONSES, ApiError, service_unavailable
from app.imaging import MAX_UPLOAD_BYTES, file_too_large, inspect_upload
from app.rate_limit import limit_uploads
from app.repositories.assets import AssetRepositoryDep, NewAsset
from app.storage import StorageDep, StorageError

router = APIRouter(prefix="/assets", tags=["assets"], responses=ERROR_RESPONSES)

_EXTENSIONS = {"image/png": "png", "image/jpeg": "jpg"}


@router.post(
    "",
    status_code=201,
    response_model=ImageRef,
    summary="그림·사진 올리기",
    dependencies=[Depends(limit_uploads)],
    responses={413: ERROR_RESPONSES[422]},
)
def upload(
    file: Annotated[UploadFile, File(description="그림판 PNG 또는 사진 JPEG")],
    user: CurrentUserDep,
    repo: AssetRepositoryDep,
    storage: StorageDep,
) -> ImageRef:
    """형식은 파일 내용으로 검사한다 (PNG·JPEG, 10 MiB, 각 변 64–4096px).

    올리기만 하고 생성을 시작하지 않으면 24시간 뒤 지워진다.
    """
    data = file.file.read(MAX_UPLOAD_BYTES + 1)
    if len(data) > MAX_UPLOAD_BYTES:
        raise file_too_large()
    info = inspect_upload(data)
    asset_id = uuid4()
    path = f"{user.id}/sources/{asset_id}.{_EXTENSIONS[info.content_type]}"
    try:
        storage.upload(path, data, info.content_type)
    except StorageError:
        raise service_unavailable() from None
    row = repo.create(
        user.id,
        NewAsset(
            id=asset_id,
            kind="source",
            storage_path=path,
            content_type=info.content_type,
            byte_size=len(data),
            width=info.width,
            height=info.height,
        ),
    )
    ref = image_refs(storage, [row]).get(asset_id)
    if ref is None:
        raise service_unavailable()
    return ref


@router.get("/{asset_id}", response_model=ImageRef, summary="이미지 URL 새로 받기")
def refresh(
    asset_id: UUID, user: CurrentUserDep, repo: AssetRepositoryDep, storage: StorageDep
) -> ImageRef:
    """만료됐거나 곧 만료될 서명 URL을 새로 받는다. 남의 에셋은 404."""
    owned = repo.get_for_user(user.id, asset_id)
    ref = image_refs(storage, [owned.row]).get(asset_id) if owned else None
    if ref is None:
        raise ApiError(404, "not_found", "이미지를 찾을 수 없어요.")
    return ref
