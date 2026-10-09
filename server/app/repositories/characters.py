"""친구(`public.friends`) 조회.

모든 함수는 `user_id`를 받아 **쿼리에서 소유자로 거른다.** 남의 친구는 없는 것과 똑같이
빈 결과(`None`/`[]`)가 나오고, 라우터는 이를 404로 바꾼다 (FR-01.4).
"""

import logging
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Annotated, Any
from uuid import UUID

from fastapi import Depends

from app.assets import AssetRow
from app.db import Database, DatabaseDep
from app.face_analysis import FaceMap, validate_face_payload

logger = logging.getLogger(__name__)


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
    face: FaceMap | None
    source: AssetRow | None
    art: AssetRow
    thumbnail: AssetRow


# 에셋 조인에도 소유자 조건을 건다. friends의 외래 키가 이미 같은 소유자를 보장하지만
# 쿼리 자체도 안전하게 읽히도록 남겨 둔다.
_SELECT = """
    select
        f.id, f.name, f.personality_type, f.favorite_things, f.speech_style,
        f.introduction, f.accent_argb, f.created_at, f.face,
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
    face = None
    if row["face"] is not None:
        try:
            face = validate_face_payload(row["face"], width=art.width, height=art.height)
        except ValueError:
            # 과거 데이터나 수동 입력이 잘못돼도 친구 조회 자체는 살리고 얼굴 효과만 뺀다.
            logger.warning("character %s has an invalid face map; skipping it", row["id"])
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
        face=face,
        source=_asset(row, "source"),
        art=art,
        thumbnail=thumbnail,
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
