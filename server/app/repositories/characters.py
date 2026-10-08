"""친구(`public.friends`) 조회.

모든 함수는 `user_id`를 받아 **쿼리에서 소유자로 거른다.** 남의 친구는 없는 것과 똑같이
빈 결과(`None`/`[]`)가 나오고, 라우터는 이를 404로 바꾼다 (FR-01.4).
"""

from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Annotated, Any
from uuid import UUID

import psycopg
from fastapi import Depends
from psycopg.types.json import Jsonb

from app.assets import AssetRow
from app.db import Database, DatabaseDep
from app.errors import ApiError
from app.idempotency import insert_or_replay


@dataclass(frozen=True)
class CharacterRecord:
    id: UUID
    name: str
    personality_type: str
    favorite_things: list[str]
    speech_style: str
    introduction: str
    accent_argb: int
    created_at: datetime
    source: AssetRow | None
    art: AssetRow
    thumbnail: AssetRow
    # 아이가 직접 적은 성격 (없으면 빈 문자열: 성격 유형의 문구를 쓴다)
    personality: str = ""
    # 자는 시각·깨는 시각 (자정부터 분, 한국 시간)
    bedtime_minute: int = 22 * 60
    wake_minute: int = 6 * 60
    face: dict | None = None


# 에셋 조인에도 소유자 조건을 건다. friends의 외래 키가 이미 같은 소유자를 보장하지만
# 쿼리 자체도 안전하게 읽히도록 남겨 둔다.
_SELECT = """
    select
        f.id, f.name, f.personality_type, f.favorite_things, f.speech_style,
        f.introduction, f.accent_argb, f.created_at,
        f.personality, f.bedtime_minute, f.wake_minute, f.face,
        s.id as source_id, s.storage_path as source_path, s.content_type as source_content_type,
        s.width as source_width, s.height as source_height,
        a.id as art_id, a.storage_path as art_path, a.content_type as art_content_type,
        a.width as art_width, a.height as art_height,
        t.id as thumbnail_id, t.storage_path as thumbnail_path,
        t.content_type as thumbnail_content_type,
        t.width as thumbnail_width, t.height as thumbnail_height
    from public.friends f
    left join public.assets s on s.id = f.source_asset_id and s.user_id = f.user_id
    join public.assets a on a.id = f.art_asset_id and a.user_id = f.user_id
    join public.assets t on t.id = f.thumbnail_asset_id and t.user_id = f.user_id
    where f.user_id = %(user_id)s
"""

# 보관함 정렬: 최신순. 같은 시각이면 id로 순서를 고정한다 (OI-07).
_ORDER = " order by f.created_at desc, f.id desc"


def _asset(row: dict[str, Any], prefix: str) -> AssetRow | None:
    asset_id = row[f"{prefix}_id"]
    if asset_id is None:
        return None
    return AssetRow(
        id=asset_id,
        storage_path=row[f"{prefix}_path"],
        content_type=row[f"{prefix}_content_type"],
        width=row[f"{prefix}_width"],
        height=row[f"{prefix}_height"],
    )


def _record(row: dict[str, Any]) -> CharacterRecord:
    art = _asset(row, "art")
    thumbnail = _asset(row, "thumbnail")
    assert art is not None and thumbnail is not None  # inner join이라 항상 있다.
    return CharacterRecord(
        id=row["id"],
        name=row["name"],
        personality_type=row["personality_type"],
        favorite_things=list(row["favorite_things"]),
        speech_style=row["speech_style"],
        introduction=row["introduction"],
        accent_argb=row["accent_argb"],
        # DB 세션 시간대와 무관하게 항상 UTC로 돌려준다 (API 계약: 시각은 UTC).
        created_at=row["created_at"].astimezone(UTC),
        source=_asset(row, "source"),
        art=art,
        thumbnail=thumbnail,
        personality=row["personality"],
        bedtime_minute=row["bedtime_minute"],
        wake_minute=row["wake_minute"],
        face=row["face"],
    )


@dataclass(frozen=True)
class NewCharacter:
    """`POST /v1/characters`가 정한 값. 이미지·대표색·얼굴은 생성 작업에서 가져온다."""

    generation_job_id: UUID
    name: str
    personality_type: str
    personality: str
    favorite_things: list[str]
    speech_style: str
    bedtime_minute: int
    wake_minute: int
    idempotency_key: str
    request_fingerprint: str


# 앱의 수정 화면에서 바꿀 수 있는 값 (PATCH /v1/characters/{id})
EDITABLE = (
    "name",
    "personality_type",
    "personality",
    "introduction",
    "speech_style",
    "bedtime_minute",
    "wake_minute",
)


class CharacterRepository:
    def __init__(self, db: Database) -> None:
        self._db = db

    def list_for_user(self, user_id: UUID) -> list[CharacterRecord]:
        with self._db.connection() as conn:
            rows = conn.execute(_SELECT + _ORDER, {"user_id": user_id}).fetchall()
        return [_record(row) for row in rows]

    def get_for_user(self, user_id: UUID, character_id: UUID) -> CharacterRecord | None:
        with self._db.connection() as conn:
            row = conn.execute(
                _SELECT + " and f.id = %(character_id)s",
                {"user_id": user_id, "character_id": character_id},
            ).fetchone()
        return _record(row) if row else None

    def create_for_user(self, user_id: UUID, new: NewCharacter) -> tuple[CharacterRecord, bool]:
        """성공한 생성 작업으로 친구를 만든다. 같은 키의 재요청이면 이미 만든 친구를 돌려준다.

        - 작업이 없거나 남의 것: 404 `not_found`
        - 작업이 아직 성공하지 않음: 409 `generation_not_ready`
        - 다른 키로 이미 친구가 된 작업: 409 `generation_job_already_used`
        """
        with self._db.connection() as conn:
            job = conn.execute(
                "select status, source_asset_id, art_asset_id, thumbnail_asset_id, accent_argb,"
                " face from public.generation_jobs"
                " where id = %(id)s and user_id = %(user_id)s for update",
                {"id": new.generation_job_id, "user_id": user_id},
            ).fetchone()
            if job is None:
                raise ApiError(404, "not_found", "친구를 만든 작업을 찾을 수 없어요.")
            existing = conn.execute(
                "select id from public.friends"
                " where user_id = %(user_id)s and idempotency_key = %(key)s",
                {"user_id": user_id, "key": new.idempotency_key},
            ).fetchone()
            if existing is None and job["status"] != "succeeded":
                raise ApiError(409, "generation_not_ready", "친구 그림이 아직 완성되지 않았어요.")
            # 같은 원본으로 다시 만든 작업이면 원본은 먼저 만든 친구에게만 붙인다.
            source = job["source_asset_id"]
            if (
                source is not None
                and conn.execute(
                    "select 1 from public.friends where source_asset_id = %(source)s",
                    {"source": source},
                ).fetchone()
            ):
                source = None
            try:
                with conn.transaction():
                    row, created = insert_or_replay(
                        conn,
                        table="public.friends",
                        values={
                            "user_id": user_id,
                            "idempotency_key": new.idempotency_key,
                            "generation_job_id": new.generation_job_id,
                            "name": new.name,
                            "personality_type": new.personality_type,
                            "personality": new.personality,
                            "favorite_things": new.favorite_things,
                            "speech_style": new.speech_style,
                            "bedtime_minute": new.bedtime_minute,
                            "wake_minute": new.wake_minute,
                            "source_asset_id": source,
                            "art_asset_id": job["art_asset_id"],
                            "thumbnail_asset_id": job["thumbnail_asset_id"],
                            "accent_argb": job["accent_argb"],
                            "face": Jsonb(job["face"]) if job["face"] is not None else None,
                        },
                        unique_columns=("user_id", "idempotency_key"),
                        request_fingerprint=new.request_fingerprint,
                    )
            except psycopg.errors.UniqueViolation as exc:
                if exc.diag.constraint_name in (
                    "friends_generation_job_id_key",
                    "friends_art_asset_id_key",
                    "friends_thumbnail_asset_id_key",
                ):
                    raise ApiError(
                        409,
                        "generation_job_already_used",
                        "이 그림으로는 이미 친구를 만들었어요.",
                    ) from None
                raise
            record = conn.execute(
                _SELECT + " and f.id = %(character_id)s",
                {"user_id": user_id, "character_id": row["id"]},
            ).fetchone()
        return _record(record), created

    def update_for_user(
        self, user_id: UUID, character_id: UUID, changes: dict[str, Any]
    ) -> CharacterRecord | None:
        """보낸 값만 바꾼다. 없거나 남의 친구면 None."""
        columns = [c for c in changes if c in EDITABLE]
        with self._db.connection() as conn:
            if columns:
                updated = conn.execute(
                    "update public.friends set "
                    + ", ".join(f"{c} = %({c})s" for c in columns)
                    + " where id = %(character_id)s and user_id = %(user_id)s",
                    {
                        **{c: changes[c] for c in columns},
                        "character_id": character_id,
                        "user_id": user_id,
                    },
                ).rowcount
                if updated == 0:
                    return None
            row = conn.execute(
                _SELECT + " and f.id = %(character_id)s",
                {"user_id": user_id, "character_id": character_id},
            ).fetchone()
        return _record(row) if row else None

    def set_introduction(self, user_id: UUID, character_id: UUID, introduction: str) -> None:
        """AI가 쓴 소개 문구를 채운다. 그 사이 아이가 직접 적었으면 덮어쓰지 않는다."""
        with self._db.connection() as conn:
            conn.execute(
                "update public.friends set introduction = %(text)s"
                " where id = %(id)s and user_id = %(user_id)s and introduction = ''",
                {"text": introduction, "id": character_id, "user_id": user_id},
            )

    def exists_for_user(self, user_id: UUID, character_id: UUID) -> bool:
        """내 친구인지만 확인한다 (이미지 서명이 필요 없는 API용)."""
        with self._db.connection() as conn:
            row = conn.execute(
                "select 1 from public.friends"
                " where id = %(character_id)s and user_id = %(user_id)s",
                {"user_id": user_id, "character_id": character_id},
            ).fetchone()
        return row is not None

    def delete_for_user(self, user_id: UUID, character_id: UUID) -> list[AssetRow] | None:
        """내 친구를 삭제하고, 그 친구가 쓰던 에셋(원본·아트·썸네일)을 돌려준다. 없으면 None.

        **에셋 행과 Storage 파일은 지우지 않는다.** 호출하는 쪽이 파일을 먼저 지운 뒤
        `delete_assets()`로 행을 지운다. 파일 삭제가 실패해도 행이 남고, 이 에셋들에는
        삭제 요청 표시가 있어서 정리 작업(`app/cleanup.py`)이 곧바로 다시 지운다.
        친구에 딸린 대화·모션 기록은 각 테이블의 `on delete cascade`로 함께 지워지고, 프로필
        아바타는 DB가 기본값(null)으로 되돌린다.
        """
        params = {"user_id": user_id, "character_id": character_id}
        with self._db.connection() as conn:
            row = conn.execute(
                "select source_asset_id, art_asset_id, thumbnail_asset_id from public.friends"
                " where id = %(character_id)s and user_id = %(user_id)s for update",
                params,
            ).fetchone()
            if row is None:
                return None
            asset_ids = [
                row[column]
                for column in ("source_asset_id", "art_asset_id", "thumbnail_asset_id")
                if row[column] is not None
            ]
            # 모션 클립 GIF도 함께 지운다 (motion_jobs는 친구와 함께 연쇄 삭제된다).
            motion = conn.execute(
                "select asset_ids from public.motion_jobs where character_id = %(character_id)s"
                " and user_id = %(user_id)s",
                params,
            ).fetchone()
            if motion:
                asset_ids.extend(motion["asset_ids"])
            conn.execute(
                "delete from public.friends where id = %(character_id)s and user_id = %(user_id)s",
                params,
            )
            # 삭제를 요청했다고 표시한다. 파일 삭제가 실패해도 정리 작업이 나이와 상관없이
            # 바로 다시 지운다 (app/cleanup.py).
            asset_rows = conn.execute(
                "update public.assets set delete_requested_at = now()"
                " where id = any(%(asset_ids)s) and user_id = %(user_id)s"
                " returning id, storage_path, content_type, width, height",
                {"asset_ids": asset_ids, "user_id": user_id},
            ).fetchall()
        return [
            AssetRow(
                id=a["id"],
                storage_path=a["storage_path"],
                content_type=a["content_type"],
                width=a["width"],
                height=a["height"],
            )
            for a in asset_rows
        ]

    def delete_assets(self, user_id: UUID, asset_ids: list[UUID]) -> None:
        """Storage 파일을 지운 뒤 에셋 행을 지운다. 소유자 조건으로 남의 에셋은 건드리지 않는다."""
        with self._db.connection() as conn:
            conn.execute(
                "delete from public.assets where id = any(%(asset_ids)s) and user_id = %(user_id)s",
                {"asset_ids": asset_ids, "user_id": user_id},
            )


def get_character_repository(db: DatabaseDep) -> CharacterRepository:
    return CharacterRepository(db)


CharacterRepositoryDep = Annotated[CharacterRepository, Depends(get_character_repository)]
