"""친구(캐릭터) 조회: 보관함 목록과 상세 (FR-06.1).

API 계약은 docs/frontend-api-reply.md 4절.
"""

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter

from app.assets import ImageRef, image_refs
from app.auth import CurrentUserDep
from app.clock import NowDep
from app.errors import ERROR_RESPONSES, ApiError
from app.personality import personality_label
from app.repositories.characters import CharacterRecord, CharacterRepositoryDep
from app.schemas import CamelModel
from app.sleep import sleep_status
from app.storage import StorageDep

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


def _to_out(record: CharacterRecord, refs: dict[UUID, ImageRef]) -> CharacterOut:
    return CharacterOut(
        id=record.id,
        name=record.name,
        personality_type=record.personality_type,
        personality_label=personality_label(record.personality_type),
        introduction=record.introduction,
        favorite_things=record.favorite_things,
        speech_style=record.speech_style,
        source=refs[record.source.id] if record.source else None,
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
    """내 친구를 최신순으로 돌려준다. 친구가 없으면 빈 목록이다."""
    records = repo.list_for_user(user.id)
    refs = image_refs(storage, _assets_of(records))
    return CharacterListOut(items=[_to_out(record, refs) for record in records])


@router.get("/{character_id}", response_model=CharacterOut, summary="친구 상세")
def get_character(
    character_id: UUID, user: CurrentUserDep, repo: CharacterRepositoryDep, storage: StorageDep
) -> CharacterOut:
    """없는 친구와 남의 친구는 똑같이 404다."""
    record = repo.get_for_user(user.id, character_id)
    if record is None:
        raise ApiError(404, "not_found", "친구를 찾을 수 없어요.")
    return _to_out(record, image_refs(storage, _assets_of([record])))


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
