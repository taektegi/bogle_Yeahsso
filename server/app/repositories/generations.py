"""캐릭터 생성 작업(`public.generation_jobs`).

API(만들기·조회·취소)는 사용자 기준으로, 처리기(가져가기·끝내기)는 작업 ID 기준으로 쓴다.
상태는 queued → processing → succeeded | failed 로만 가고, 취소는 queued·processing에서만 된다.
처리기가 결과를 저장할 때도 "아직 processing인가"를 조건으로 걸어서, 그 사이 취소된 작업의 결과가
살아나지 않게 한다 (API 계약 3.3절: 취소한 시도의 늦은 결과로 넘어가지 않기).
"""

import json
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Annotated, Any
from uuid import UUID

from fastapi import Depends
from psycopg.types.json import Jsonb

from app.assets import AssetRow
from app.db import Database, DatabaseDep
from app.errors import ApiError
from app.idempotency import insert_or_replay
from app.repositories.assets import NewAsset, insert_asset

WAITING = ("queued", "processing")


@dataclass(frozen=True)
class JobRecord:
    id: UUID
    user_id: UUID
    source_asset_id: UUID
    source_type: str
    status: str
    art: AssetRow | None
    thumbnail: AssetRow | None
    accent_argb: int | None
    face: dict | None
    error_code: str | None
    error_retryable: bool | None
    attempts: int
    created_at: datetime
    updated_at: datetime


_SELECT = """
    select j.*,
        a.storage_path as art_path, a.content_type as art_content_type,
        a.width as art_width, a.height as art_height,
        t.storage_path as thumbnail_path, t.content_type as thumbnail_content_type,
        t.width as thumbnail_width, t.height as thumbnail_height
    from public.generation_jobs j
    left join public.assets a on a.id = j.art_asset_id and a.user_id = j.user_id
    left join public.assets t on t.id = j.thumbnail_asset_id and t.user_id = j.user_id
"""


def _asset(row: dict[str, Any], prefix: str) -> AssetRow | None:
    if row.get(f"{prefix}_asset_id") is None or row.get(f"{prefix}_path") is None:
        return None
    return AssetRow(
        id=row[f"{prefix}_asset_id"],
        storage_path=row[f"{prefix}_path"],
        content_type=row[f"{prefix}_content_type"],
        width=row[f"{prefix}_width"],
        height=row[f"{prefix}_height"],
    )


def _record(row: dict[str, Any]) -> JobRecord:
    face = row["face"]
    if isinstance(face, str):
        face = json.loads(face)
    return JobRecord(
        id=row["id"],
        user_id=row["user_id"],
        source_asset_id=row["source_asset_id"],
        source_type=row["source_type"],
        status=row["status"],
        art=_asset(row, "art"),
        thumbnail=_asset(row, "thumbnail"),
        accent_argb=row["accent_argb"],
        face=face,
        error_code=row["error_code"],
        error_retryable=row["error_retryable"],
        attempts=row["attempts"],
        created_at=row["created_at"].astimezone(UTC),
        updated_at=row["updated_at"].astimezone(UTC),
    )


@dataclass(frozen=True)
class JobSource:
    """처리기가 원본을 내려받는 데에 필요한 값."""

    job: JobRecord
    storage_path: str


class GenerationRepository:
    def __init__(self, db: Database) -> None:
        self._db = db

    # ---- API -------------------------------------------------------------

    def create(
        self,
        user_id: UUID,
        *,
        source_asset_id: UUID,
        source_type: str,
        idempotency_key: str,
        request_fingerprint: str,
    ) -> tuple[JobRecord, bool]:
        """새 작업을 만들거나, 같은 키의 작업을 돌려준다. 원본이 내 업로드가 아니면 404."""
        with self._db.connection() as conn:
            source = conn.execute(
                "select kind from public.assets where id = %(id)s and user_id = %(user_id)s"
                " and delete_requested_at is null",
                {"id": source_asset_id, "user_id": user_id},
            ).fetchone()
            if source is None or source["kind"] != "source":
                raise ApiError(404, "not_found", "올린 그림을 찾을 수 없어요.")
            row, created = insert_or_replay(
                conn,
                table="public.generation_jobs",
                values={
                    "user_id": user_id,
                    "source_asset_id": source_asset_id,
                    "source_type": source_type,
                    "idempotency_key": idempotency_key,
                },
                unique_columns=("user_id", "idempotency_key"),
                request_fingerprint=request_fingerprint,
            )
            job = conn.execute(_SELECT + " where j.id = %(id)s", {"id": row["id"]}).fetchone()
        return _record(job), created

    def get_for_user(self, user_id: UUID, job_id: UUID) -> JobRecord | None:
        with self._db.connection() as conn:
            row = conn.execute(
                _SELECT + " where j.id = %(id)s and j.user_id = %(user_id)s",
                {"id": job_id, "user_id": user_id},
            ).fetchone()
        return _record(row) if row else None

    def cancel_for_user(
        self, user_id: UUID, job_id: UUID
    ) -> tuple[JobRecord, list[AssetRow]] | None:
        """기다리는 작업을 취소한다. 이미 끝났으면 그대로 둔다. 없으면 None.

        돌려주는 두 번째 값은 지워야 할 결과 에셋이다 (취소와 완료가 엇갈린 경우는 없다:
        처리기는 processing일 때만 결과를 저장하므로 취소된 작업에는 결과가 붙지 않는다).
        """
        with self._db.connection() as conn:
            conn.execute(
                "update public.generation_jobs set status = 'cancelled', finished_at = now()"
                " where id = %(id)s and user_id = %(user_id)s and status = any(%(waiting)s)",
                {"id": job_id, "user_id": user_id, "waiting": list(WAITING)},
            )
            row = conn.execute(
                _SELECT + " where j.id = %(id)s and j.user_id = %(user_id)s",
                {"id": job_id, "user_id": user_id},
            ).fetchone()
        return (_record(row), []) if row else None

    # ---- 처리기 ----------------------------------------------------------

    def claim_next(self) -> JobSource | None:
        """가장 오래 기다린 작업 하나를 processing으로 바꿔 가져간다 (여러 처리기가 겹치지 않게)."""
        with self._db.connection() as conn:
            row = conn.execute(
                "update public.generation_jobs j"
                " set status = 'processing', started_at = now(), attempts = attempts + 1"
                " where j.id = ("
                "   select id from public.generation_jobs where status = 'queued'"
                "   order by created_at limit 1 for update skip locked)"
                " returning j.id",
            ).fetchone()
            if row is None:
                return None
            job = conn.execute(_SELECT + " where j.id = %(id)s", {"id": row["id"]}).fetchone()
            source = conn.execute(
                "select storage_path from public.assets where id = %(id)s",
                {"id": job["source_asset_id"]},
            ).fetchone()
        if source is None:
            return None
        return JobSource(job=_record(job), storage_path=source["storage_path"])

    def is_waiting(self, job_id: UUID) -> bool:
        with self._db.connection() as conn:
            row = conn.execute(
                "select status from public.generation_jobs where id = %(id)s", {"id": job_id}
            ).fetchone()
        return row is not None and row["status"] in WAITING

    def succeed(
        self,
        job: JobRecord,
        *,
        art: NewAsset,
        thumbnail: NewAsset,
        accent_argb: int,
        face: dict | None,
    ) -> bool:
        """결과를 저장한다. 그 사이 취소·시간 초과로 끝난 작업이면 False.

        False이면 결과 파일은 호출한 쪽이 지운다.
        """
        with self._db.connection() as conn:
            current = conn.execute(
                "select status from public.generation_jobs where id = %(id)s for update",
                {"id": job.id},
            ).fetchone()
            if current is None or current["status"] != "processing":
                return False
            insert_asset(conn, job.user_id, art)
            insert_asset(conn, job.user_id, thumbnail)
            conn.execute(
                "update public.generation_jobs set status = 'succeeded', finished_at = now(),"
                " art_asset_id = %(art)s, thumbnail_asset_id = %(thumbnail)s,"
                " accent_argb = %(accent)s, face = %(face)s"
                " where id = %(id)s",
                {
                    "id": job.id,
                    "art": art.id,
                    "thumbnail": thumbnail.id,
                    "accent": accent_argb,
                    "face": Jsonb(face) if face is not None else None,
                },
            )
        return True

    def fail(self, job_id: UUID, *, code: str, retryable: bool) -> bool:
        with self._db.connection() as conn:
            updated = conn.execute(
                "update public.generation_jobs set status = 'failed', finished_at = now(),"
                " error_code = %(code)s, error_retryable = %(retryable)s"
                " where id = %(id)s and status = 'processing'",
                {"id": job_id, "code": code, "retryable": retryable},
            ).rowcount
        return updated > 0

    def requeue_interrupted(self) -> int:
        """서버가 재시작되기 전에 처리 중이던 작업을 다시 줄 세운다 (복구).

        이미 세 번 시도한 작업은 다시 돌리지 않고 실패로 끝낸다 (작업이 서버를 멈추게 하는 경우).
        """
        with self._db.connection() as conn:
            conn.execute(
                "update public.generation_jobs set status = 'failed', finished_at = now(),"
                " error_code = 'generation_unavailable', error_retryable = true"
                " where status = 'processing' and attempts >= 3"
            )
            return conn.execute(
                "update public.generation_jobs set status = 'queued' where status = 'processing'"
            ).rowcount

    def fail_stale(self, seconds: float) -> int:
        """너무 오래 처리 중인 작업(처리기가 멈춤)을 시간 초과로 끝낸다."""
        with self._db.connection() as conn:
            return conn.execute(
                "update public.generation_jobs set status = 'failed', finished_at = now(),"
                " error_code = 'generation_timeout', error_retryable = true"
                " where status = 'processing'"
                " and started_at < now() - make_interval(secs => %(seconds)s)",
                {"seconds": seconds},
            ).rowcount


def get_generation_repository(db: DatabaseDep) -> GenerationRepository:
    return GenerationRepository(db)


GenerationRepositoryDep = Annotated[GenerationRepository, Depends(get_generation_repository)]
