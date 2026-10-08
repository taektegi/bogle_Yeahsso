"""친구의 모션 클립 작업(`public.motion_jobs`). 친구마다 하나.

상태: queued → working → ready | unsupported | failed. 친구를 지우면 함께 지워진다.
"""

import json
from dataclasses import dataclass, field
from typing import Annotated, Any
from uuid import UUID

from fastapi import Depends
from psycopg.types.json import Jsonb

from app.assets import AssetRow
from app.db import Database, DatabaseDep
from app.repositories.assets import NewAsset, insert_asset

WAITING = ("queued", "working")


@dataclass(frozen=True)
class MotionRecord:
    id: UUID
    user_id: UUID
    character_id: UUID
    status: str
    reason: str | None
    remote_id: str | None
    attempts: int
    # {"jump": {"assetId": "...", "box": [l, t, r, b]}}
    clips: dict[str, Any] = field(default_factory=dict)
    assets: dict[UUID, AssetRow] = field(default_factory=dict)


@dataclass(frozen=True)
class MotionWork:
    """처리기가 모션 서버에 보낼 친구 그림."""

    job: MotionRecord
    art_path: str


def _record(row: dict[str, Any], assets: list[dict[str, Any]] | None = None) -> MotionRecord:
    clips = row["clips"]
    if isinstance(clips, str):
        clips = json.loads(clips)
    return MotionRecord(
        id=row["id"],
        user_id=row["user_id"],
        character_id=row["character_id"],
        status=row["status"],
        reason=row["reason"],
        remote_id=row["remote_id"],
        attempts=row["attempts"],
        clips=clips or {},
        assets={
            a["id"]: AssetRow(
                id=a["id"],
                storage_path=a["storage_path"],
                content_type=a["content_type"],
                width=a["width"],
                height=a["height"],
            )
            for a in assets or []
        },
    )


class MotionRepository:
    def __init__(self, db: Database) -> None:
        self._db = db

    def create(self, user_id: UUID, character_id: UUID, *, enabled: bool) -> None:
        """친구가 생기면 작업을 만든다. 모션 서버가 없으면 바로 unsupported(disabled)."""
        with self._db.connection() as conn:
            conn.execute(
                "insert into public.motion_jobs (user_id, character_id, status, reason)"
                " values (%(user_id)s, %(character_id)s, %(status)s, %(reason)s)"
                " on conflict (character_id) do nothing",
                {
                    "user_id": user_id,
                    "character_id": character_id,
                    "status": "queued" if enabled else "unsupported",
                    "reason": None if enabled else "disabled",
                },
            )

    def get_for_user(self, user_id: UUID, character_id: UUID) -> MotionRecord | None:
        with self._db.connection() as conn:
            row = conn.execute(
                "select * from public.motion_jobs"
                " where character_id = %(character_id)s and user_id = %(user_id)s",
                {"character_id": character_id, "user_id": user_id},
            ).fetchone()
            if row is None:
                return None
            assets = conn.execute(
                "select id, storage_path, content_type, width, height from public.assets"
                " where id = any(%(ids)s) and user_id = %(user_id)s",
                {"ids": row["asset_ids"], "user_id": user_id},
            ).fetchall()
        return _record(row, assets)

    # ---- 처리기 ----------------------------------------------------------

    def claim_next(self) -> MotionWork | None:
        with self._db.connection() as conn:
            row = conn.execute(
                "update public.motion_jobs m"
                " set status = 'working', started_at = now(), attempts = attempts + 1"
                " where m.id = ("
                "   select id from public.motion_jobs where status = 'queued'"
                "   order by created_at limit 1 for update skip locked)"
                " returning m.*",
            ).fetchone()
            if row is None:
                return None
            art = conn.execute(
                "select a.storage_path from public.friends f"
                " join public.assets a on a.id = f.art_asset_id and a.user_id = f.user_id"
                " where f.id = %(id)s",
                {"id": row["character_id"]},
            ).fetchone()
        if art is None:
            return None
        return MotionWork(job=_record(row), art_path=art["storage_path"])

    def set_remote(self, job_id: UUID, remote_id: str) -> None:
        with self._db.connection() as conn:
            conn.execute(
                "update public.motion_jobs set remote_id = %(remote)s where id = %(id)s",
                {"remote": remote_id, "id": job_id},
            )

    def is_working(self, job_id: UUID) -> bool:
        with self._db.connection() as conn:
            row = conn.execute(
                "select status from public.motion_jobs where id = %(id)s", {"id": job_id}
            ).fetchone()
        return row is not None and row["status"] == "working"

    def finish_ready(
        self,
        job: MotionRecord,
        clips: dict[str, dict[str, Any]],
        assets: list[NewAsset],
    ) -> bool:
        """클립 GIF 에셋을 저장하고 ready로 끝낸다. 그 사이 친구가 지워졌으면 False."""
        with self._db.connection() as conn:
            current = conn.execute(
                "select status from public.motion_jobs where id = %(id)s for update",
                {"id": job.id},
            ).fetchone()
            if current is None or current["status"] != "working":
                return False
            for asset in assets:
                insert_asset(conn, job.user_id, asset)
            conn.execute(
                "update public.motion_jobs set status = 'ready', reason = null,"
                " finished_at = now(), clips = %(clips)s, asset_ids = %(ids)s"
                " where id = %(id)s",
                {"id": job.id, "clips": Jsonb(clips), "ids": [a.id for a in assets]},
            )
        return True

    def finish(self, job_id: UUID, status: str, reason: str | None = None) -> None:
        with self._db.connection() as conn:
            conn.execute(
                "update public.motion_jobs set status = %(status)s, reason = %(reason)s,"
                " finished_at = now() where id = %(id)s and status = 'working'",
                {"id": job_id, "status": status, "reason": reason},
            )

    def requeue(self, job_id: UUID) -> None:
        """일시 오류: 다시 줄 세운다 (같은 원격 작업을 이어서 본다)."""
        with self._db.connection() as conn:
            conn.execute(
                "update public.motion_jobs set status = 'queued'"
                " where id = %(id)s and status = 'working'",
                {"id": job_id},
            )

    def requeue_interrupted(self) -> int:
        with self._db.connection() as conn:
            return conn.execute(
                "update public.motion_jobs set status = 'queued' where status = 'working'"
            ).rowcount

    def fail_stale(self, seconds: float) -> int:
        with self._db.connection() as conn:
            return conn.execute(
                "update public.motion_jobs set status = 'failed', finished_at = now()"
                " where status = 'working'"
                " and started_at < now() - make_interval(secs => %(seconds)s)",
                {"seconds": seconds},
            ).rowcount


def get_motion_repository(db: DatabaseDep) -> MotionRepository:
    return MotionRepository(db)


MotionRepositoryDep = Annotated[MotionRepository, Depends(get_motion_repository)]
