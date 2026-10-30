"""알려진 현상을 재현하는 관찰 테스트. 요구 동작이 충족됐다는 회귀 테스트가 아니다."""

import asyncio
import threading
import time
from contextlib import contextmanager
from datetime import timedelta
from uuid import uuid4

import pytest

from app.cleanup import cleanup_assets
from app.config import Settings
from app.errors import ApiError
from app.friend_settings import SaveFriendIn
from app.generation_worker import GenerationWorker
from app.repositories.characters import CharacterRepository
from app.repositories.creation import CreationRepository
from tests.db_support import FakeStorage, make_asset, make_user


def saved_fixture(database, conn):
    user = make_user(conn)
    source, _ = make_asset(conn, user, "source")
    art, _ = make_asset(conn, user, "art")
    thumb, _ = make_asset(conn, user, "thumbnail")
    repo = CreationRepository(database)
    job, _ = repo.enqueue(user, source, "drawing", str(uuid4()))
    conn.execute(
        "update generation_jobs set status='succeeded',art_asset_id=%s,"
        "thumbnail_asset_id=%s,accent_argb=4289974783 where id=%s",
        (art, thumb, job["id"]),
    )
    friend, _ = repo.save_friend(
        user,
        SaveFriendIn(
            generationJobId=job["id"],
            name="관찰친구",
            personalityType="gentle_smiling",
            favoriteThings=["그림"],
            speechStyle="해요체",
        ),
        str(uuid4()),
    )
    return user, job["id"], friend


def test_observe_delete_and_cleanup_deadlock(database, seed_conn, caplog):
    user, job, friend = saved_fixture(database, seed_conn)
    seed_conn.execute(
        "update generation_jobs set created_at=now()-interval '25 hours' where id=%s", (job,)
    )
    friend_locked = threading.Event()
    release_delete = threading.Event()
    outcomes = []

    class PausingConnection:
        def __init__(self, conn):
            self.conn = conn

        def execute(self, query, *args):
            result = self.conn.execute(query, *args)
            if "from public.friends" in query and "for update" in query:
                friend_locked.set()
                if not release_delete.wait(8):
                    raise TimeoutError("cleanup did not reach lock wait")
            return result

    class ObservedDB:
        def __init__(self, deleting):
            self.deleting = deleting

        @contextmanager
        def connection(self):
            with database.connection() as conn:
                conn.execute(
                    "set local application_name = 'bogle_diagnostic_"
                    + ("delete'" if self.deleting else "cleanup'")
                )
                yield PausingConnection(conn) if self.deleting else conn

    def deletion():
        try:
            CharacterRepository(ObservedDB(True)).delete_for_user(user, friend)
            outcomes.append("delete_completed")
        except ApiError:
            outcomes.append("delete_503")

    def cleanup():
        try:
            CreationRepository(ObservedDB(False)).cleanup_jobs()
            outcomes.append("cleanup_completed")
        except ApiError:
            outcomes.append("cleanup_503")

    first = threading.Thread(target=deletion)
    second = threading.Thread(target=cleanup)
    first.start()
    try:
        assert friend_locked.wait(5)
        second.start()
        deadline = time.monotonic() + 6
        waiting = False
        while time.monotonic() < deadline:
            waiting = seed_conn.execute(
                "select exists(select 1 from pg_stat_activity "
                "where application_name='bogle_diagnostic_cleanup' and wait_event_type='Lock') "
                "as waiting"
            ).fetchone()["waiting"]
            if waiting:
                break
            time.sleep(0.05)
        assert waiting, "실제 정리 쿼리가 친구 잠금을 기다리지 않음"
        release_delete.set()
        first.join(8)
        second.join(8)
        assert not first.is_alive() and not second.is_alive()
        assert any(x.endswith("503") for x in outcomes)
        assert "DeadlockDetected" in caplog.text
    finally:
        release_delete.set()
        first.join(8)
        if second.ident:
            second.join(8)
        seed_conn.execute("delete from auth.users where id=%s", (user,))


def test_observe_expired_processing_job_remains_protected(database, seed_conn):
    user = make_user(seed_conn)
    source, _ = make_asset(seed_conn, user, "source")
    repo = CreationRepository(database)
    job, _ = repo.enqueue(user, source, "drawing", str(uuid4()))
    storage = FakeStorage()

    class WaitingProvider:
        async def generate(self, reference):
            await asyncio.sleep(30)

    async def scenario():
        worker = GenerationWorker(database, storage, Settings(_env_file=None), WaitingProvider())

        async def blocked_pipeline(job):
            await asyncio.sleep(30)

        # 지연 구간만 주입하고 워커의 실제 claim·조회·취소 경로를 실행한다.
        worker.pipeline = blocked_pipeline
        task = asyncio.create_task(worker.run())
        try:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                status = seed_conn.execute(
                    "select status from generation_jobs where id=%s", (job["id"],)
                ).fetchone()["status"]
                if status == "processing":
                    break
                await asyncio.sleep(0.05)
            assert status == "processing"
            seed_conn.execute(
                "update generation_jobs set created_at=now()-interval '25 hours' where id=%s",
                (job["id"],),
            )
            seed_conn.execute(
                "update assets set created_at=now()-interval '25 hours' where id=%s", (source,)
            )
            await asyncio.sleep(2.2)
            assert not worker.tasks  # 404로 실제 실행은 취소됐다.
            with pytest.raises(ApiError) as exc:
                repo.job(user, job["id"])
            assert exc.value.status_code == 404
            cleanup_assets(database, storage, timedelta(hours=24))
            row = seed_conn.execute(
                "select status from generation_jobs where id=%s", (job["id"],)
            ).fetchone()
            assert row["status"] == "processing"
            assert seed_conn.execute("select 1 from assets where id=%s", (source,)).fetchone()
        finally:
            task.cancel()
            with pytest.raises(asyncio.CancelledError):
                await task

    try:
        asyncio.run(scenario())
    finally:
        seed_conn.execute("delete from auth.users where id=%s", (user,))
