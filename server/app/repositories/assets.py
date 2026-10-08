"""에셋(`public.assets`) 쓰기·조회. 모든 함수는 소유자(`user_id`)로 거른다 (FR-01.4)."""

from dataclasses import dataclass
from typing import Annotated
from uuid import UUID

import psycopg
from fastapi import Depends

from app.assets import AssetRow
from app.db import Database, DatabaseDep


@dataclass(frozen=True)
class NewAsset:
    id: UUID
    kind: str  # source | art | thumbnail | motion
    storage_path: str
    content_type: str
    byte_size: int
    width: int
    height: int


def insert_asset(conn: psycopg.Connection, user_id: UUID, asset: NewAsset) -> AssetRow:
    """같은 트랜잭션 안에서 쓸 수 있게 연결을 받는다."""
    conn.execute(
        "insert into public.assets"
        " (id, user_id, kind, storage_path, content_type, byte_size, width, height)"
        " values (%(id)s, %(user_id)s, %(kind)s, %(path)s, %(type)s, %(size)s, %(w)s, %(h)s)",
        {
            "id": asset.id,
            "user_id": user_id,
            "kind": asset.kind,
            "path": asset.storage_path,
            "type": asset.content_type,
            "size": asset.byte_size,
            "w": asset.width,
            "h": asset.height,
        },
    )
    return AssetRow(
        id=asset.id,
        storage_path=asset.storage_path,
        content_type=asset.content_type,
        width=asset.width,
        height=asset.height,
    )


@dataclass(frozen=True)
class OwnedAsset:
    row: AssetRow
    kind: str


class AssetRepository:
    def __init__(self, db: Database) -> None:
        self._db = db

    def create(self, user_id: UUID, asset: NewAsset) -> AssetRow:
        with self._db.connection() as conn:
            return insert_asset(conn, user_id, asset)

    def get_for_user(self, user_id: UUID, asset_id: UUID) -> OwnedAsset | None:
        """내 에셋. 삭제를 요청한 에셋은 없는 것으로 본다."""
        with self._db.connection() as conn:
            row = conn.execute(
                "select id, kind, storage_path, content_type, width, height from public.assets"
                " where id = %(id)s and user_id = %(user_id)s and delete_requested_at is null",
                {"id": asset_id, "user_id": user_id},
            ).fetchone()
        if row is None:
            return None
        return OwnedAsset(
            row=AssetRow(
                id=row["id"],
                storage_path=row["storage_path"],
                content_type=row["content_type"],
                width=row["width"],
                height=row["height"],
            ),
            kind=row["kind"],
        )


def get_asset_repository(db: DatabaseDep) -> AssetRepository:
    return AssetRepository(db)


AssetRepositoryDep = Annotated[AssetRepository, Depends(get_asset_repository)]
