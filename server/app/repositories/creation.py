"""업로드·생성 작업·친구 저장. 소유권, 상태 전이와 멱등 처리를 DB에서 보장한다."""

import secrets
from datetime import timedelta
from uuid import UUID, uuid4

import psycopg
from psycopg.types.json import Jsonb

from app.assets import AssetRow
from app.db import Database
from app.errors import ApiError
from app.friend_settings import INTRODUCTIONS, SaveFriendIn
from app.idempotency import fingerprint, idempotency_conflict, insert_or_replay
from app.rate_limit import generation_limiter

MODEL = "openai/gpt-image-2.5-flare"
PROMPT_VERSION = "bogle-flat-v1-20261009"


def not_found() -> ApiError:
    return ApiError(404, "not_found", "요청한 이미지 또는 작업을 찾을 수 없어요.")


def asset_row(row: dict) -> AssetRow:
    return AssetRow(
        **{k: row[k] for k in ("id", "storage_path", "content_type", "width", "height")}
    )


def _replay(conn, table: str, user_id: UUID, key: str, digest: str):
    # 테이블 이름은 이 모듈에 있는 상수만 전달한다.
    row = conn.execute(
        f"select * from public.{table} where user_id=%s and idempotency_key=%s",
        (user_id, key),
    ).fetchone()
    if row and row["request_fingerprint"] != digest:
        raise idempotency_conflict()
    return row


class CreationRepository:
    def __init__(self, db: Database):
        self.db = db

    def add_asset(self, user_id, kind, data, content_type, width, height):
        asset_id = uuid4()
        extension = "jpg" if content_type == "image/jpeg" else "png"
        path = f"{user_id}/{kind}/{asset_id}.{extension}"
        with self.db.connection() as conn:
            row = conn.execute(
                "insert into public.assets "
                "(id,user_id,kind,storage_path,content_type,byte_size,width,height) "
                "values (%s,%s,%s,%s,%s,%s,%s,%s) returning *",
                (asset_id, user_id, kind, path, content_type, len(data), width, height),
            ).fetchone()
        return asset_row(row)

    def discard_assets(self, user_id, ids):
        # 파일 삭제 실패에 대비해 먼저 DB에 정리 표시를 남긴다.
        with self.db.connection() as conn:
            conn.execute(
                "update public.assets set delete_requested_at=now() "
                "where user_id=%s and id=any(%s)",
                (user_id, ids),
            )

    def source(self, user_id, asset_id):
        with self.db.connection() as conn:
            row = conn.execute(
                "select * from public.assets where user_id=%s and id=%s "
                "and kind='source' and delete_requested_at is null",
                (user_id, asset_id),
            ).fetchone()
        if not row:
            raise not_found()
        return asset_row(row)

    def enqueue(self, user_id, source_id, source_type, key):
        digest = fingerprint({"sourceAssetId": source_id, "sourceType": source_type})
        with self.db.connection() as conn:
            # 같은 사용자 키를 직렬화해 재전송은 횟수 제한에 포함하지 않는다.
            conn.execute(
                "select pg_advisory_xact_lock(hashtextextended(%s,0))",
                (f"generation:{user_id}:{key}",),
            )
            existing = _replay(conn, "generation_jobs", user_id, key, digest)
            if existing:
                return existing, False
            source = conn.execute(
                "select id from public.assets where user_id=%s and id=%s "
                "and kind='source' and delete_requested_at is null "
                "and created_at > now()-interval '24 hours' for update",
                (user_id, source_id),
            ).fetchone()
            if not source:
                raise not_found()
            if conn.execute(
                "select 1 from public.friends where user_id=%s and source_asset_id=%s",
                (user_id, source_id),
            ).fetchone():
                raise ApiError(409, "source_already_used", "이미 친구로 저장한 그림이에요.")
            generation_limiter.check(user_id)
            return insert_or_replay(
                conn,
                table="public.generation_jobs",
                values={
                    "user_id": user_id,
                    "source_asset_id": source_id,
                    "source_type": source_type,
                    "idempotency_key": key,
                    "model": MODEL,
                    "prompt_version": PROMPT_VERSION,
                },
                unique_columns=("user_id", "idempotency_key"),
                request_fingerprint=digest,
            )

    def job(self, user_id, job_id):
        with self.db.connection() as conn:
            row = conn.execute(
                "select * from public.generation_jobs where user_id=%s and id=%s "
                "and created_at > now()-interval '24 hours'",
                (user_id, job_id),
            ).fetchone()
        if not row:
            raise not_found()
        return row

    def cancel(self, user_id, job_id):
        with self.db.connection() as conn:
            conn.execute(
                "update public.generation_jobs set status='cancelled',finished_at=now() "
                "where user_id=%s and id=%s and status in ('queued','processing')",
                (user_id, job_id),
            )
        return self.job(user_id, job_id)

    def result_assets(self, user_id, job):
        with self.db.connection() as conn:
            rows = conn.execute(
                "select * from public.assets where user_id=%s and id=any(%s) "
                "and delete_requested_at is null",
                (user_id, [job["art_asset_id"], job["thumbnail_asset_id"]]),
            ).fetchall()
        if len(rows) != 2:
            raise not_found()
        return [asset_row(row) for row in rows]

    def save_friend(self, user_id: UUID, payload: SaveFriendIn, key: str):
        digest = fingerprint(payload)
        try:
            with self.db.connection() as conn:
                conn.execute(
                    "select pg_advisory_xact_lock(hashtextextended(%s,0))",
                    (f"friend:{user_id}:{key}",),
                )
                existing = _replay(conn, "friends", user_id, key, digest)
                if existing:
                    return existing["id"], False
                job = conn.execute(
                    "select * from public.generation_jobs where user_id=%s and id=%s "
                    "and created_at > now()-interval '24 hours' for update",
                    (user_id, payload.generation_job_id),
                ).fetchone()
                if not job:
                    raise not_found()
                if job["status"] != "succeeded":
                    raise ApiError(409, "generation_not_ready", "완성된 캐릭터만 저장할 수 있어요.")
                ids = [job[k] for k in ("source_asset_id", "art_asset_id", "thumbnail_asset_id")]
                assets = conn.execute(
                    "select id,kind from public.assets where user_id=%s and id=any(%s) "
                    "and delete_requested_at is null for update",
                    (user_id, ids),
                ).fetchall()
                kinds = {a["id"]: a["kind"] for a in assets}
                if [kinds.get(i) for i in ids] != ["source", "art", "thumbnail"]:
                    raise not_found()
                row, new = insert_or_replay(
                    conn,
                    table="public.friends",
                    unique_columns=("user_id", "idempotency_key"),
                    request_fingerprint=digest,
                    values={
                        "user_id": user_id,
                        "generation_job_id": job["id"],
                        "idempotency_key": key,
                        "name": payload.name,
                        "personality_type": payload.personality_type,
                        "favorite_things": payload.favorite_things,
                        "speech_style": payload.speech_style,
                        "bedtime": payload.bedtime,
                        "wake_time": payload.wake_time,
                        "introduction": secrets.choice(INTRODUCTIONS),
                        "source_asset_id": job["source_asset_id"],
                        "art_asset_id": job["art_asset_id"],
                        "thumbnail_asset_id": job["thumbnail_asset_id"],
                        "accent_argb": job["accent_argb"],
                        "face": Jsonb(job["face"]) if job["face"] is not None else None,
                    },
                )
                conn.execute(
                    "update public.window_view_jobs set character_id=%s where user_id=%s "
                    "and generation_job_id=%s and character_id is null",
                    (row["id"], user_id, job["id"]),
                )
                return row["id"], new
        except psycopg.errors.UniqueViolation:
            raise ApiError(
                409, "generation_job_already_used", "이 작업 또는 원본으로 이미 친구를 저장했어요."
            ) from None

    def acquire_lease(self, owner: UUID) -> bool:
        with self.db.connection() as conn:
            row = conn.execute(
                "insert into public.generation_worker_lease "
                "values (1,%s,now()+interval '30 seconds') "
                "on conflict(id) do update set owner=excluded.owner,expires_at=excluded.expires_at "
                "where generation_worker_lease.owner=excluded.owner "
                "or generation_worker_lease.expires_at < now() returning id",
                (owner,),
            ).fetchone()
        return row is not None

    def release_lease(self, owner):
        with self.db.connection() as conn:
            conn.execute("delete from public.generation_worker_lease where owner=%s", (owner,))

    def recover(self):
        with self.db.connection() as conn:
            conn.execute(
                "update public.generation_jobs set status='failed',"
                "error_code='generation_interrupted',"
                "error_message='서버가 재시작되어 작업이 중단됐어요. 다시 시도해 주세요.',"
                "error_retryable=true,finished_at=now() where status='processing'"
            )
            # 중단된 얼굴 분석은 유료 AI를 자동으로 다시 부르지 않고 좌표 없음으로 마친다.
            conn.execute(
                "update public.generation_jobs set face_status='unavailable' "
                "where face_status='pending'"
            )

    def claim(self, owner):
        with self.db.connection() as conn:
            return conn.execute(
                "update public.generation_jobs set status='processing',started_at=now(),"
                "worker_owner=%s where id=("
                "select id from public.generation_jobs where status='queued' "
                "and created_at > now()-interval '24 hours' "
                "and exists(select 1 from public.generation_worker_lease where owner=%s "
                "and expires_at>now()) order by created_at,id for update skip locked limit 1) "
                "returning *",
                (owner, owner),
            ).fetchone()

    def fail(self, user_id, job_id, code, message, retryable, owner=None):
        with self.db.connection() as conn:
            conn.execute(
                "update public.generation_jobs set status='failed',error_code=%s,error_message=%s,"
                "error_retryable=%s,finished_at=now() where user_id=%s and id=%s "
                "and status='processing' and (worker_owner=%s or %s::uuid is null)",
                (code, message, retryable, user_id, job_id, owner, owner),
            )

    def finish(
        self,
        user_id,
        job_id,
        owner,
        art,
        thumbnail,
        accent,
        timeout=240,
        *,
        face_status="pending",
    ):
        """그림 결과로 작업을 성공 처리한다. 얼굴 좌표는 ``finish_face``가 나중에 채운다."""
        with self.db.connection() as conn:
            return (
                conn.execute(
                    "update public.generation_jobs set status='succeeded',art_asset_id=%s,"
                    "thumbnail_asset_id=%s,accent_argb=%s,face=null,face_status=%s,"
                    "finished_at=now() "
                    "where user_id=%s and id=%s and status='processing' "
                    "and worker_owner=%s and started_at>now()-%s "
                    "and exists(select 1 from public.generation_worker_lease "
                    "where owner=%s and expires_at>now()) returning id",
                    (
                        art.id,
                        thumbnail.id,
                        accent,
                        face_status,
                        user_id,
                        job_id,
                        owner,
                        timedelta(seconds=timeout),
                        owner,
                    ),
                ).fetchone()
                is not None
            )

    def finish_face(self, user_id, job_id, owner, face) -> bool:
        """진행 중인 얼굴 분석 결과를 기록하고, 이 작업으로 이미 저장한 친구에도 채운다.

        작업 행을 먼저 잠그므로 같은 작업의 친구 저장(``save_friend``)과 순서가 섞여도
        친구는 분석 결과를 받는다. 분석이 끝나기 전에 저장했으면 여기서 채우고,
        분석이 먼저 끝났으면 저장할 때 작업의 face를 복사한다.
        """
        with self.db.connection() as conn:
            row = conn.execute(
                "update public.generation_jobs set face=%s,face_status=%s "
                "where user_id=%s and id=%s and status='succeeded' "
                "and face_status='pending' and worker_owner=%s "
                "and exists(select 1 from public.generation_worker_lease "
                "where owner=%s and expires_at>now()) returning id",
                (
                    Jsonb(face) if face is not None else None,
                    "ready" if face is not None else "unavailable",
                    user_id,
                    job_id,
                    owner,
                    owner,
                ),
            ).fetchone()
            if row is None:
                return False
            if face is not None:
                conn.execute(
                    "update public.friends set face=%s "
                    "where user_id=%s and generation_job_id=%s and face is null",
                    (Jsonb(face), user_id, job_id),
                )
            return True

    def cleanup_jobs(self, retention=timedelta(hours=24)):
        with self.db.connection() as conn:
            conn.execute(
                "delete from public.generation_jobs where created_at<now()-%s "
                "and status<>'processing'",
                (retention,),
            )
