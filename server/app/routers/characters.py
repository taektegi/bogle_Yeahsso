"""친구(캐릭터) 조회: 보관함 목록과 상세 (FR-06.1).

API 계약은 docs/frontend-api-reply.md 4절.
"""

import logging
from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Response

from app.assets import AssetRow, ImageRef, image_refs
from app.auth import CurrentUserDep
from app.clock import NowDep
from app.errors import ERROR_RESPONSES, ApiError
from app.personality import personality_label
from app.repositories.characters import (
    CharacterRecord,
    CharacterRepository,
    CharacterRepositoryDep,
)
from app.schemas import CamelModel
from app.sleep import sleep_status
from app.storage import StorageClient, StorageDep, StorageError

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/characters", tags=["characters"], responses=ERROR_RESPONSES)


class CharacterOut(CamelModel):
    id: UUID
    name: str
    personality_type: str
    personality_label: str
    introduction: str
    favorite_things: list[str]
    speech_style: str
    # 서버에서 만든 친구는 항상 값이 있다. 원본이 없는 데이터만 null이다.
    source: ImageRef | None
    art: ImageRef
    thumbnail: ImageRef
    accent_argb: int
    created_at: datetime


class CharacterListOut(CamelModel):
    items: list[CharacterOut]
    # 데모 규모라 한 번에 모두 내려 준다. 나중에 페이지를 나눌 때를 위한 필드로 항상 null이다.
    next_cursor: str | None = None


def _to_out(record: CharacterRecord, refs: dict[UUID, ImageRef]) -> CharacterOut | None:
    """아트·썸네일 파일을 열 수 없는 친구는 None이다 (원본만 없으면 source가 null)."""
    if record.art.id not in refs or record.thumbnail.id not in refs:
        logger.error("character %s has an unreadable art or thumbnail file", record.id)
        return None
    return CharacterOut(
        id=record.id,
        name=record.name,
        personality_type=record.personality_type,
        personality_label=personality_label(record.personality_type),
        introduction=record.introduction,
        favorite_things=record.favorite_things,
        speech_style=record.speech_style,
        source=refs.get(record.source.id) if record.source else None,
        art=refs[record.art.id],
        thumbnail=refs[record.thumbnail.id],
        accent_argb=record.accent_argb,
        created_at=record.created_at,
    )


def _assets_of(records: list[CharacterRecord]):
    for record in records:
        if record.source:
            yield record.source
        yield record.art
        yield record.thumbnail


class SleepStatusOut(CamelModel):
    asleep: bool
    next_change_at: datetime
    # 앱이 기기 시계 오차를 보정할 수 있도록 서버 시각을 함께 준다.
    server_time: datetime


@router.get("", response_model=CharacterListOut, summary="내 친구 목록 (보관함)")
def list_characters(
    user: CurrentUserDep, repo: CharacterRepositoryDep, storage: StorageDep
) -> CharacterListOut:
    """내 친구를 최신순으로 돌려준다. 친구가 없으면 빈 목록이다.

    아트·썸네일 파일이 사라진 친구는 목록에서 빼고(오류 로그), 나머지는 정상으로 돌려준다.
    """
    records = repo.list_for_user(user.id)
    refs = image_refs(storage, _assets_of(records))
    outs = (_to_out(record, refs) for record in records)
    return CharacterListOut(items=[out for out in outs if out is not None])


@router.get("/{character_id}", response_model=CharacterOut, summary="친구 상세")
def get_character(
    character_id: UUID, user: CurrentUserDep, repo: CharacterRepositoryDep, storage: StorageDep
) -> CharacterOut:
    """없는 친구와 남의 친구는 똑같이 404다. 아트·썸네일 파일이 사라진 친구도 목록과 같게 404다."""
    record = repo.get_for_user(user.id, character_id)
    out = _to_out(record, image_refs(storage, _assets_of([record]))) if record else None
    if out is None:
        raise ApiError(404, "not_found", "친구를 찾을 수 없어요.")
    return out


@router.get(
    "/{character_id}/status",
    response_model=SleepStatusOut,
    summary="친구의 수면 상태",
)
def get_status(
    character_id: UUID, user: CurrentUserDep, repo: CharacterRepositoryDep, now: NowDep
) -> SleepStatusOut:
    """한국 시간 22:00–06:00에는 잔다. 판정은 서버 시각 기준이다 (FR-08)."""
    if not repo.exists_for_user(user.id, character_id):
        raise ApiError(404, "not_found", "친구를 찾을 수 없어요.")
    status = sleep_status(now)
    return SleepStatusOut(
        asleep=status.asleep, next_change_at=status.next_change_at, server_time=now
    )


def _remove_files(
    repo: CharacterRepository, storage: StorageClient, user_id: UUID, assets: list[AssetRow]
) -> None:
    """파일을 지우고 에셋 행을 지운다. 실패해도 친구는 이미 삭제됐으므로 예외를 내지 않는다.

    실패하면 에셋 행이 남는다. 행이 남아 있으면 경로를 알 수 있어서 나중에 다시 정리할 수 있다.
    """
    if not assets:
        return
    try:
        storage.remove([asset.storage_path for asset in assets])
        repo.delete_assets(user_id, [asset.id for asset in assets])
    except (StorageError, ApiError) as exc:
        logger.warning(
            "deleted a character but left %d asset row(s) for cleanup: %s", len(assets), exc
        )


@router.delete("/{character_id}", status_code=204, summary="친구 삭제 (영구)")
def delete_character(
    character_id: UUID, user: CurrentUserDep, repo: CharacterRepositoryDep, storage: StorageDep
) -> Response:
    """즉시 영구 삭제한다. 되돌릴 수 없다 (FR-06.3, D-21).

    친구, 대화·모션 기록, 원본·캐릭터 아트·썸네일 파일이 함께 지워지고, 아바타였다면 기본값으로
    돌아간다. 없는 친구와 남의 친구는 똑같이 404다. 이미 지운 친구를 다시 지워도 404다.
    """
    assets = repo.delete_for_user(user.id, character_id)
    if assets is None:
        raise ApiError(404, "not_found", "친구를 찾을 수 없어요.")
    _remove_files(repo, storage, user.id, assets)
    return Response(status_code=204)
