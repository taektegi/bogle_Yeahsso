"""프로필 조회·수정 (FR-02). API 계약은 docs/frontend-api-reply.md 5절."""

from typing import Any
from uuid import UUID

from fastapi import APIRouter
from pydantic import field_validator
from pydantic_core import PydanticCustomError

from app.auth import CurrentUserDep
from app.errors import ERROR_RESPONSES
from app.repositories.profiles import ProfileRecord, ProfileRepositoryDep
from app.schemas import CamelModel

router = APIRouter(prefix="/me", tags=["profile"], responses=ERROR_RESPONSES)

NICKNAME_MAX_LENGTH = 12


class ProfileOut(CamelModel):
    nickname: str
    # null이면 기본 아바타. 지정한 친구가 삭제되면 서버가 null로 되돌린다.
    avatar_character_id: UUID | None
    # 알림 설정값만 저장한다. 실제 푸시는 보내지 않는다.
    friend_notifications: bool
    order_notifications: bool
    character_count: int


class ProfilePatch(CamelModel):
    """보낸 필드만 수정한다. `avatarCharacterId`만 `null`(기본 아바타로 되돌리기)을 보낼 수 있다."""

    nickname: str | None = None
    avatar_character_id: UUID | None = None
    friend_notifications: bool | None = None
    order_notifications: bool | None = None

    @field_validator("nickname", "friend_notifications", "order_notifications", mode="before")
    @classmethod
    def _not_null(cls, value: Any) -> Any:
        # 값을 보냈다면 null일 수 없다. (보내지 않은 필드에는 이 검사가 실행되지 않는다.)
        if value is None:
            raise PydanticCustomError("not_null", "null일 수 없어요")
        return value

    @field_validator("nickname", mode="after")
    @classmethod
    def _nickname_length(cls, value: str) -> str:
        nickname = value.strip()
        if not nickname:
            raise PydanticCustomError("string_too_short", "닉네임은 1자 이상이어야 해요")
        if len(nickname) > NICKNAME_MAX_LENGTH:
            raise PydanticCustomError("string_too_long", "닉네임은 12자 이하여야 해요")
        return nickname


def _to_out(record: ProfileRecord) -> ProfileOut:
    return ProfileOut(
        nickname=record.nickname,
        avatar_character_id=record.avatar_character_id,
        friend_notifications=record.friend_notifications,
        order_notifications=record.order_notifications,
        character_count=record.character_count,
    )


@router.get("", response_model=ProfileOut, summary="내 프로필")
def get_me(user: CurrentUserDep, repo: ProfileRepositoryDep) -> ProfileOut:
    """처음 로그인한 계정도 기본 프로필(닉네임 `그린고블린`)을 받는다."""
    return _to_out(repo.get(user.id))


@router.patch("", response_model=ProfileOut, summary="내 프로필 수정")
def update_me(body: ProfilePatch, user: CurrentUserDep, repo: ProfileRepositoryDep) -> ProfileOut:
    """보낸 필드만 수정하고 수정된 프로필 전체를 돌려준다."""
    changes = {name: getattr(body, name) for name in body.model_fields_set}
    return _to_out(repo.update(user.id, changes))
