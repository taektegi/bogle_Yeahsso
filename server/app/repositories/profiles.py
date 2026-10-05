"""프로필(`public.profiles`) 조회·수정 (FR-02).

프로필은 가입할 때 DB 트리거가 만든다. 트리거가 없던 때 만든 계정을 위해 읽을 때 없으면 만든다.
모든 함수는 `user_id`로 소유자를 지정한다 (사용자 ID는 토큰에서만 온다).
"""

from dataclasses import dataclass
from typing import Annotated, Any
from uuid import UUID

import psycopg
from fastapi import Depends
from psycopg import errors

from app.db import Database, DatabaseDep
from app.errors import ApiError


@dataclass(frozen=True)
class ProfileRecord:
    nickname: str
    avatar_character_id: UUID | None
    friend_notifications: bool
    order_notifications: bool
    character_count: int


# 수정할 수 있는 필드 → 컬럼. SQL에는 이 목록의 컬럼 이름만 들어간다.
_UPDATABLE_COLUMNS = {
    "nickname": "nickname",
    "avatar_character_id": "avatar_friend_id",
    "friend_notifications": "friend_notifications",
    "order_notifications": "order_notifications",
}

_SELECT = """
    select p.nickname, p.avatar_friend_id, p.friend_notifications, p.order_notifications,
           (select count(*) from public.friends f where f.user_id = p.id) as character_count
    from public.profiles p
    where p.id = %(user_id)s
"""

_AVATAR_CONSTRAINT = "profiles_avatar_friend_fkey"


def _unknown_user() -> ApiError:
    # 토큰은 유효하지만 계정이 사라진 경우 (운영자가 정리한 계정 등)
    return ApiError(
        401,
        "unauthenticated",
        "로그인이 만료됐거나 올바르지 않아요. 다시 로그인해 주세요.",
        headers={"WWW-Authenticate": "Bearer"},
    )


def _record(row: dict[str, Any]) -> ProfileRecord:
    return ProfileRecord(
        nickname=row["nickname"],
        avatar_character_id=row["avatar_friend_id"],
        friend_notifications=row["friend_notifications"],
        order_notifications=row["order_notifications"],
        character_count=row["character_count"],
    )


class ProfileRepository:
    def __init__(self, db: Database) -> None:
        self._db = db

    def get(self, user_id: UUID) -> ProfileRecord:
        with self._db.connection() as conn:
            self._ensure_exists(conn, user_id)
            return _record(conn.execute(_SELECT, {"user_id": user_id}).fetchone())

    def update(self, user_id: UUID, changes: dict[str, Any]) -> ProfileRecord:
        """`changes`의 키는 `_UPDATABLE_COLUMNS`에 있는 필드뿐이다. 빈 dict면 수정 없이 읽기만 한다.

        아바타는 DB의 복합 외래 키가 "내 친구"만 허용한다. 남의 친구·없는 친구면 422이다.
        """
        unknown = changes.keys() - _UPDATABLE_COLUMNS.keys()
        if unknown:
            raise ValueError(f"cannot update {sorted(unknown)}")

        with self._db.connection() as conn:
            self._ensure_exists(conn, user_id)
            if changes:
                assignments = ", ".join(f"{_UPDATABLE_COLUMNS[k]} = %({k})s" for k in changes)
                try:
                    conn.execute(
                        f"update public.profiles set {assignments} where id = %(user_id)s",
                        {**changes, "user_id": user_id},
                    )
                except errors.ForeignKeyViolation as exc:
                    if exc.diag.constraint_name != _AVATAR_CONSTRAINT:
                        raise
                    raise ApiError(
                        422,
                        "validation_error",
                        "입력값을 확인해 주세요.",
                        field_errors={"avatarCharacterId": "character_not_found"},
                    ) from None
            return _record(conn.execute(_SELECT, {"user_id": user_id}).fetchone())

    @staticmethod
    def _ensure_exists(conn: psycopg.Connection, user_id: UUID) -> None:
        try:
            conn.execute(
                "insert into public.profiles (id) values (%s) on conflict (id) do nothing",
                (user_id,),
            )
        except errors.ForeignKeyViolation:
            raise _unknown_user() from None


def get_profile_repository(db: DatabaseDep) -> ProfileRepository:
    return ProfileRepository(db)


ProfileRepositoryDep = Annotated[ProfileRepository, Depends(get_profile_repository)]
