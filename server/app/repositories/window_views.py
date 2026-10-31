"""선택 배경 대기열. 소유자·멱등 키·동시 생성·완성 이미지 게시를 DB에서 보호한다."""

from datetime import timedelta

from app.errors import ApiError
from app.idempotency import fingerprint, idempotency_conflict, insert_or_replay
from app.rate_limit import window_limiter
from app.repositories.creation import MODEL, CreationRepository, asset_row, not_found
from app.window_images import PROMPT_VERSION


class WindowViewRepository(CreationRepository):
    def asset(self, user_id, asset_id):
        """소유자에게 속하고 삭제되지 않은 입력·배경 에셋만 읽는다."""
        with self.db.connection() as conn:
            row = conn.execute(
                "select * from public.assets where user_id=%s and id=%s "
                "and delete_requested_at is null",
                (user_id, asset_id),
            ).fetchone()
        if not row:
            raise not_found()
        return asset_row(row)

    def enqueue(self, user_id, character_id, key, *, regenerate=False):
        digest = fingerprint({"characterId": character_id, "regenerate": regenerate})
        with self.db.connection() as conn:
            # 사용자 키와 친구 행 잠금을 함께 써서 다른 키의 중복 탭도 한 작업으로 합친다.
            conn.execute(
                "select pg_advisory_xact_lock(hashtextextended(%s,0))", (f"window:{user_id}:{key}",)
            )
            friend = conn.execute(
                "select art_asset_id from public.friends where user_id=%s and id=%s for update",
                (user_id, character_id),
            ).fetchone()
            if not friend:
                raise not_found()
            previous = conn.execute(
                "select j.*,r.request_fingerprint as request_digest "
                "from public.window_view_requests r "
                "join public.window_view_jobs j on j.user_id=r.user_id and j.id=r.job_id "
                "where r.user_id=%s and r.idempotency_key=%s",
                (user_id, key),
            ).fetchone()
            if previous:
                if previous["request_digest"] != digest:
                    raise idempotency_conflict()
                return previous, False
            current = conn.execute(
                "select * from public.window_view_jobs where user_id=%s and character_id=%s "
                "and (status in ('queued','processing') or (status='succeeded' and not %s)) "
                "order by created_at desc,id desc limit 1",
                (user_id, character_id, regenerate),
            ).fetchone()
            if current:
                self._remember(conn, user_id, key, digest, current["id"])
                return current, False
            # 친구 생성과 분리된 배경 전용 한도를 사용한다. 재전송·캐시 조회는 차감하지 않는다.
            window_limiter.check(user_id)
            job, new = insert_or_replay(
                conn,
                table="public.window_view_jobs",
                values={
                    "user_id": user_id,
                    "character_id": character_id,
                    "source_asset_id": friend["art_asset_id"],
                    "idempotency_key": key,
                    "model": MODEL,
                    "prompt_version": PROMPT_VERSION,
                },
                unique_columns=("user_id", "idempotency_key"),
                request_fingerprint=digest,
            )
            self._remember(conn, user_id, key, digest, job["id"])
            return job, new

    def prefetch(self, user_id, generation_job_id):
        """캐릭터 생성 직후 배경을 예약한다. 이미 있거나 한도를 넘으면 건너뛴다 (None)."""
        with self.db.connection() as conn:
            # 친구 저장과 같은 생성 작업 행을 잠가 저장 전·후 어느 쪽이든 친구에 한 번 연결한다.
            job = conn.execute(
                "select art_asset_id from public.generation_jobs where user_id=%s and id=%s "
                "and status='succeeded' for update",
                (user_id, generation_job_id),
            ).fetchone()
            if (
                not job
                or conn.execute(
                    "select 1 from public.window_view_jobs where generation_job_id=%s",
                    (generation_job_id,),
                ).fetchone()
            ):
                return None
            friend = conn.execute(
                "select id from public.friends where user_id=%s and generation_job_id=%s",
                (user_id, generation_job_id),
            ).fetchone()
            if (
                friend
                and conn.execute(
                    "select 1 from public.window_view_jobs where user_id=%s and character_id=%s",
                    (user_id, friend["id"]),
                ).fetchone()
            ):
                return None
            try:
                window_limiter.check(user_id)
            except ApiError:
                # 집에 들어갈 때 앱이 다시 요청하므로 미리 만들기만 생략한다.
                return None
            row, _ = insert_or_replay(
                conn,
                table="public.window_view_jobs",
                values={
                    "user_id": user_id,
                    "character_id": friend["id"] if friend else None,
                    "generation_job_id": generation_job_id,
                    "source_asset_id": job["art_asset_id"],
                    "idempotency_key": f"prefetch-{generation_job_id}",
                    "model": MODEL,
                    "prompt_version": PROMPT_VERSION,
                },
                unique_columns=("user_id", "idempotency_key"),
                request_fingerprint=fingerprint({"generationJobId": generation_job_id}),
            )
            return row

    @staticmethod
    def _remember(conn, user_id, key, digest, job_id):
        insert_or_replay(
            conn,
            table="public.window_view_requests",
            values={"user_id": user_id, "idempotency_key": key, "job_id": job_id},
            unique_columns=("user_id", "idempotency_key"),
            request_fingerprint=digest,
        )

    def current(self, user_id, character_id):
        with self.db.connection() as conn:
            if not conn.execute(
                "select 1 from public.friends where user_id=%s and id=%s", (user_id, character_id)
            ).fetchone():
                raise not_found()
            jobs = conn.execute(
                "select * from public.window_view_jobs where user_id=%s and character_id=%s "
                "order by created_at desc,id desc",
                (user_id, character_id),
            ).fetchall()
        return (jobs[0] if jobs else None), next(
            (job for job in jobs if job["status"] == "succeeded"), None
        )

    def job(self, user_id, job_id):
        with self.db.connection() as conn:
            job = conn.execute(
                "select * from public.window_view_jobs where user_id=%s and id=%s",
                (user_id, job_id),
            ).fetchone()
        if not job:
            raise not_found()
        return job

    def acquire_lease(self, owner):
        with self.db.connection() as conn:
            return (
                conn.execute(
                    "insert into public.window_worker_lease "
                    "values (1,%s,now()+interval '30 seconds') "
                    "on conflict(id) do update set owner=excluded.owner,"
                    "expires_at=excluded.expires_at "
                    "where window_worker_lease.owner=excluded.owner or "
                    "window_worker_lease.expires_at<now() returning id",
                    (owner,),
                ).fetchone()
                is not None
            )

    def release_lease(self, owner):
        with self.db.connection() as conn:
            conn.execute("delete from public.window_worker_lease where owner=%s", (owner,))

    def recover(self):
        with self.db.connection() as conn:
            conn.execute(
                "update public.window_view_jobs set status='failed',finished_at=now(),"
                "error_code='generation_interrupted',error_message='배경 만들기가 중단됐어요.',"
                "error_retryable=true where status='processing' or "
                "(status='queued' and created_at<now()-interval '24 hours')"
            )

    def claim(self, owner):
        with self.db.connection() as conn:
            return conn.execute(
                "update public.window_view_jobs set status='processing',started_at=now(),"
                "worker_owner=%s where id=(select id from public.window_view_jobs "
                "where status='queued' and exists(select 1 from public.window_worker_lease "
                "where owner=%s and expires_at>now()) "
                # 집에 곧 들어갈 저장된 친구를, 아직 저장하지 않은 후보보다 우선한다.
                "order by (character_id is null),created_at,id "
                "for update skip locked limit 1) returning *",
                (owner, owner),
            ).fetchone()

    def fail(self, user_id, job_id, code, message, retryable, owner=None):
        with self.db.connection() as conn:
            conn.execute(
                "update public.window_view_jobs set status='failed',error_code=%s,error_message=%s,"
                "error_retryable=%s,finished_at=now() where user_id=%s and id=%s "
                "and status='processing' and (worker_owner=%s or %s::uuid is null)",
                (code, message, retryable, user_id, job_id, owner, owner),
            )

    def finish(self, job, owner, day, timeout):
        with self.db.connection() as conn:
            return (
                conn.execute(
                    "update public.window_view_jobs set status='succeeded',day_asset_id=%s,"
                    "night_asset_id=null,finished_at=now() where user_id=%s and id=%s "
                    "and status='processing' and worker_owner=%s and started_at>now()-%s "
                    "and exists(select 1 from public.window_worker_lease where owner=%s "
                    "and expires_at>now()) and (exists(select 1 from public.friends f "
                    "where f.user_id=%s and f.id=window_view_jobs.character_id "
                    "and f.art_asset_id=window_view_jobs.source_asset_id) "
                    # 아직 저장하지 않은 친구는 원래 생성 결과가 남아 있을 때만 게시한다.
                    "or (window_view_jobs.character_id is null and exists("
                    "select 1 from public.generation_jobs g "
                    "where g.user_id=window_view_jobs.user_id "
                    "and g.id=window_view_jobs.generation_job_id "
                    "and g.art_asset_id=window_view_jobs.source_asset_id))) "
                    "returning id",
                    (
                        day.id,
                        job["user_id"],
                        job["id"],
                        owner,
                        timedelta(seconds=timeout),
                        owner,
                        job["user_id"],
                    ),
                ).fetchone()
                is not None
            )

    def cleanup_jobs(self, retention=timedelta(hours=24)):
        with self.db.connection() as conn:
            # 캐릭터마다 최신 작업과 마지막 성공 배경은 나이와 무관하게 유지한다.
            conn.execute(
                "delete from public.window_view_jobs j where created_at<now()-%s "
                "and status not in ('queued','processing') and exists("
                "select 1 from public.window_view_jobs n where n.user_id=j.user_id "
                "and n.character_id=j.character_id and (n.created_at,n.id)>(j.created_at,j.id)) "
                "and (status<>'succeeded' or exists(select 1 from public.window_view_jobs s "
                "where s.user_id=j.user_id and s.character_id=j.character_id and "
                "s.status='succeeded' and (s.created_at,s.id)>(j.created_at,j.id)))",
                (retention,),
            )
            # 미리 만들었지만 끝내 저장하지 않은 친구의 배경. 에셋은 이어서 정리된다.
            conn.execute(
                "delete from public.window_view_jobs where character_id is null "
                "and created_at<now()-%s and status not in ('queued','processing')",
                (retention,),
            )
