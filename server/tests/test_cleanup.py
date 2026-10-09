"""미사용 에셋 정리(app/cleanup.py). 실제 PostgreSQL과 가짜 Storage로 확인한다."""

import asyncio
import time
from datetime import timedelta

import pytest
from fastapi.testclient import TestClient
from psycopg_pool import PoolTimeout

from app import cleanup
from app.cleanup import CleanupResult, background_cleanup, cleanup_assets, run_periodically
from app.config import Settings
from app.db import Database, get_database
from app.main import create_app
from app.storage import SupabaseStorage, get_storage
from tests.db_support import FakeStorage, make_asset, make_character, make_user
from tests.tokens import bearer, hs256_token

RETENTION = timedelta(hours=24)


@pytest.fixture
def storage() -> FakeStorage:
    return FakeStorage()


@pytest.fixture(autouse=True)
def empty_assets(request) -> None:
    """정리 작업은 전체 에셋이 대상이라 다른 테스트가 남긴 에셋과 섞이지 않게 비우고 시작한다.

    DB가 필요 없는 테스트(`database_url`을 쓰지 않는 것)는 건너뛴다.
    """
    if "database_url" not in request.fixturenames and "database" not in request.fixturenames:
        return
    conn = request.getfixturevalue("seed_conn")
    conn.execute("delete from public.friends")
    conn.execute("delete from public.assets")


def age(conn, asset_id, hours: float) -> None:
    conn.execute(
        "update public.assets set created_at = now() - make_interval(secs => %s) where id = %s",
        (hours * 3600, asset_id),
    )


def asset_exists(conn, asset_id) -> bool:
    return (
        conn.execute("select 1 from public.assets where id = %s", (asset_id,)).fetchone()
        is not None
    )


def removed_paths(storage: FakeStorage) -> list[str]:
    return [path for batch in storage.removed for path in batch]


def test_old_unused_asset_is_deleted_with_its_file(database, seed_conn, storage) -> None:
    user = make_user(seed_conn)
    asset_id, path = make_asset(seed_conn, user, "source")
    age(seed_conn, asset_id, 25)

    result = cleanup_assets(database, storage, RETENTION)

    assert result == CleanupResult(deleted=1, incomplete=False)
    assert removed_paths(storage) == [path]
    assert not asset_exists(seed_conn, asset_id)


def test_recent_unused_asset_is_kept(database, seed_conn, storage) -> None:
    user = make_user(seed_conn)
    asset_id, _ = make_asset(seed_conn, user, "source")
    age(seed_conn, asset_id, 23)

    result = cleanup_assets(database, storage, RETENTION)

    assert result.deleted == 0
    assert storage.removed == []
    assert asset_exists(seed_conn, asset_id)


def test_assets_used_by_a_character_are_never_deleted(database, seed_conn, storage) -> None:
    user = make_user(seed_conn)
    make_character(seed_conn, user, "쓰는 중")
    seed_conn.execute(
        "update public.assets set created_at = now() - interval '30 days',"
        " delete_requested_at = now() where user_id = %s",
        (user,),
    )

    result = cleanup_assets(database, storage, RETENTION)

    assert result.deleted == 0
    assert storage.removed == []
    assert (
        seed_conn.execute(
            "select count(*) as n from public.assets where user_id = %s", (user,)
        ).fetchone()["n"]
        == 3
    )


def test_delete_requested_assets_go_regardless_of_age(database, seed_conn, storage) -> None:
    user = make_user(seed_conn)
    asset_id, path = make_asset(seed_conn, user, "art")  # 방금 만든 에셋
    seed_conn.execute(
        "update public.assets set delete_requested_at = now() where id = %s", (asset_id,)
    )

    result = cleanup_assets(database, storage, RETENTION)

    assert result.deleted == 1
    assert removed_paths(storage) == [path]
    assert not asset_exists(seed_conn, asset_id)


def test_storage_failure_keeps_the_row_and_the_next_run_retries(database, seed_conn) -> None:
    user = make_user(seed_conn)
    asset_id, path = make_asset(seed_conn, user, "source")
    age(seed_conn, asset_id, 48)

    failing = FakeStorage(fail_remove=True)
    first = cleanup_assets(database, failing, RETENTION)
    assert first == CleanupResult(deleted=0, incomplete=True)
    assert asset_exists(seed_conn, asset_id)

    working = FakeStorage()
    second = cleanup_assets(database, working, RETENTION)
    assert second.deleted == 1
    assert removed_paths(working) == [path]
    assert not asset_exists(seed_conn, asset_id)


def test_a_run_interrupted_after_removing_the_files_is_completed_by_the_next_one(
    database, seed_conn, storage
) -> None:
    """서버가 정리 도중에 종료돼 파일만 지워지고 행이 남은 경우. 파일을 먼저 지우는 순서 덕에
    다음 주기가 이미 없는 파일을 다시 지우려 하고(오류 아님) 행을 마저 지운다."""
    user = make_user(seed_conn)
    asset_id, path = make_asset(seed_conn, user, "source")
    age(seed_conn, asset_id, 30)
    storage.remove([path])  # 첫 실행: 파일은 지웠지만 행을 지우기 전에 끝났다
    assert asset_exists(seed_conn, asset_id)

    result = cleanup_assets(database, storage, RETENTION)

    assert result == CleanupResult(deleted=1, incomplete=False)
    assert not asset_exists(seed_conn, asset_id)
    assert removed_paths(storage) == [path, path]  # 이미 없는 파일을 한 번 더 지우려 했다


def test_files_of_a_deleted_character_are_cleaned_even_if_the_api_could_not_remove_them(
    app, client: TestClient, database, seed_conn
) -> None:
    user = make_user(seed_conn)
    character_id = make_character(seed_conn, user, "파일 삭제 실패")
    app.dependency_overrides[get_database] = lambda: database
    app.dependency_overrides[get_storage] = lambda: FakeStorage(fail_remove=True)
    headers = bearer(hs256_token(sub=str(user)))

    assert client.delete(f"/v1/characters/{character_id}", headers=headers).status_code == 204

    left = seed_conn.execute(
        "select delete_requested_at is not null as marked from public.assets where user_id = %s",
        (user,),
    ).fetchall()
    assert len(left) == 3 and all(row["marked"] for row in left)

    working = FakeStorage()
    result = cleanup_assets(database, working, RETENTION)  # 에셋은 방금 만든 것이지만 바로 지운다

    assert result.deleted == 3
    assert len(removed_paths(working)) == 3
    assert (
        seed_conn.execute(
            "select count(*) as n from public.assets where user_id = %s", (user,)
        ).fetchone()["n"]
        == 0
    )


def test_a_successful_delete_leaves_nothing_for_the_cleanup(
    app, client: TestClient, database, seed_conn
) -> None:
    user = make_user(seed_conn)
    character_id = make_character(seed_conn, user, "정상 삭제")
    app.dependency_overrides[get_database] = lambda: database
    app.dependency_overrides[get_storage] = lambda: FakeStorage()
    client.delete(f"/v1/characters/{character_id}", headers=bearer(hs256_token(sub=str(user))))

    storage = FakeStorage()

    assert cleanup_assets(database, storage, RETENTION).deleted == 0
    assert storage.removed == []


def test_other_users_old_assets_are_cleaned_too(database, seed_conn, storage) -> None:
    a, b = make_user(seed_conn), make_user(seed_conn)
    old = [make_asset(seed_conn, u, "source")[0] for u in (a, b)]
    for asset_id in old:
        age(seed_conn, asset_id, 30)
    keep = make_character(seed_conn, b, "남의 친구")

    cleanup_assets(database, storage, RETENTION)

    assert not any(asset_exists(seed_conn, asset_id) for asset_id in old)
    assert seed_conn.execute("select 1 from public.friends where id = %s", (keep,)).fetchone()


def test_large_backlogs_are_cleaned_in_batches(database, seed_conn, storage, monkeypatch) -> None:
    monkeypatch.setattr(cleanup, "BATCH_SIZE", 3)
    user = make_user(seed_conn)
    for _ in range(7):
        age(seed_conn, make_asset(seed_conn, user, "source")[0], 30)

    result = cleanup_assets(database, storage, RETENTION)

    assert result == CleanupResult(deleted=7, incomplete=False)
    assert [len(batch) for batch in storage.removed] == [3, 3, 1]


def test_one_run_stops_after_the_batch_limit_and_the_next_run_continues(
    database, seed_conn, storage, monkeypatch
) -> None:
    monkeypatch.setattr(cleanup, "BATCH_SIZE", 3)
    monkeypatch.setattr(cleanup, "MAX_BATCHES_PER_RUN", 2)
    user = make_user(seed_conn)
    for _ in range(10):
        age(seed_conn, make_asset(seed_conn, user, "source")[0], 30)

    first = cleanup_assets(database, storage, RETENTION)
    second = cleanup_assets(database, storage, RETENTION)
    third = cleanup_assets(database, storage, RETENTION)

    assert first == CleanupResult(deleted=6, incomplete=True)
    assert second == CleanupResult(deleted=4, incomplete=False)
    assert third == CleanupResult(deleted=0, incomplete=False)


def test_other_tables_can_protect_assets_through_asset_references(
    database, seed_conn, storage, monkeypatch
) -> None:
    seed_conn.execute("create table public.test_jobs (source_asset_id uuid)")
    try:
        monkeypatch.setattr(
            cleanup,
            "ASSET_REFERENCES",
            [
                *cleanup.ASSET_REFERENCES,
                "exists (select 1 from public.test_jobs j where j.source_asset_id = a.id)",
            ],
        )
        user = make_user(seed_conn)
        protected, _ = make_asset(seed_conn, user, "source")
        unused, _ = make_asset(seed_conn, user, "source")
        for asset_id in (protected, unused):
            age(seed_conn, asset_id, 30)
        seed_conn.execute("insert into public.test_jobs values (%s)", (protected,))

        result = cleanup_assets(database, storage, RETENTION)

        assert result.deleted == 1
        assert asset_exists(seed_conn, protected)
        assert not asset_exists(seed_conn, unused)
    finally:
        seed_conn.execute("drop table public.test_jobs")


def test_an_asset_that_becomes_used_during_the_run_is_not_deleted(
    database, seed_conn, storage, monkeypatch
) -> None:
    user = make_user(seed_conn)
    target, _ = make_asset(seed_conn, user, "art")
    age(seed_conn, target, 30)

    def use_the_asset_now() -> None:
        thumbnail, _ = make_asset(seed_conn, user, "thumbnail")
        seed_conn.execute(
            "insert into public.friends (user_id, name, personality_type, favorite_things,"
            " speech_style, art_asset_id, thumbnail_asset_id, accent_argb)"
            " values (%s, '막 쓰기 시작', 'calm', '{사과}', '반말', %s, %s, 1)",
            (user, target, thumbnail),
        )

    original_select = cleanup._select_batch

    def select_then_use(db, retention):
        batch = original_select(db, retention)
        use_the_asset_now()
        return batch

    monkeypatch.setattr(cleanup, "_select_batch", select_then_use)

    result = cleanup_assets(database, storage, RETENTION)

    assert result.deleted == 0
    assert asset_exists(seed_conn, target)


# --- 주기 실행 -------------------------------------------------------------


class BrokenPool:
    def __init__(self) -> None:
        self.attempts = 0

    def connection(self, timeout: float):
        self.attempts += 1
        raise PoolTimeout("no connection")


def wait_until(condition, timeout: float = 3.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return True
        time.sleep(0.02)
    return False


def test_the_periodic_task_cleans_and_stops_when_cancelled(database, seed_conn) -> None:
    user = make_user(seed_conn)
    asset_id, _ = make_asset(seed_conn, user, "source")
    age(seed_conn, asset_id, 30)
    storage = FakeStorage()

    async def scenario() -> bool:
        task = asyncio.create_task(
            run_periodically(
                database, storage, interval_seconds=0.05, retention=RETENTION, first_delay_seconds=0
            )
        )
        # 파일을 지운 뒤에 행을 지우므로, 행이 사라질 때까지 기다렸다가 멈춘다.
        for _ in range(150):
            if not asset_exists(seed_conn, asset_id):
                break
            await asyncio.sleep(0.02)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
        return bool(storage.removed)

    assert asyncio.run(scenario()) is True
    assert not asset_exists(seed_conn, asset_id)


def test_a_failing_run_does_not_stop_the_task() -> None:
    pool = BrokenPool()

    async def scenario() -> int:
        task = asyncio.create_task(
            run_periodically(
                Database(pool),  # type: ignore[arg-type]
                FakeStorage(),
                interval_seconds=0.05,
                retention=RETENTION,
                first_delay_seconds=0,
            )
        )
        await asyncio.sleep(0.4)
        still_running = not task.done()
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
        assert still_running
        return pool.attempts

    assert asyncio.run(scenario()) >= 2  # 첫 실패 뒤에도 다음 주기에 다시 시도했다


@pytest.mark.parametrize(
    ("db", "storage", "interval"),
    [(None, FakeStorage(), 3600), (object(), None, 3600), (object(), FakeStorage(), 0)],
)
def test_cleanup_is_disabled_without_db_storage_or_interval(db, storage, interval) -> None:
    async def scenario():
        async with background_cleanup(
            db, storage, interval_seconds=interval, retention=RETENTION
        ) as task:
            return task

    assert asyncio.run(scenario()) is None


def test_leaving_the_context_cancels_the_task(database) -> None:
    async def scenario():
        async with background_cleanup(
            database,
            FakeStorage(),
            interval_seconds=3600,
            retention=RETENTION,
            first_delay_seconds=3600,
        ) as task:
            assert not task.done()
        return task

    task = asyncio.run(scenario())
    assert task.cancelled()


# --- 서버 시작에 연결 ---------------------------------------------------------


def test_server_startup_starts_the_cleanup_with_the_configured_values(monkeypatch) -> None:
    calls: list[dict] = []

    class RecordingCleanup:
        def __init__(self, db, storage, **kwargs) -> None:
            calls.append({"db": db, "storage": storage, **kwargs})

        async def __aenter__(self):
            return None

        async def __aexit__(self, *exc) -> None:
            calls.append({"stopped": True})

    settings = Settings(
        _env_file=None,
        supabase_url="https://proj.supabase.co",
        supabase_service_role_key="service-role-key",
        database_url="postgresql://u:p@127.0.0.1:5999/none",
        cleanup_interval_seconds=1800,
        asset_retention_hours=12,
    )
    monkeypatch.setattr("app.main.get_settings", lambda: settings)
    monkeypatch.setattr("app.main.background_cleanup", RecordingCleanup)

    with TestClient(create_app()):
        pass

    [started, stopped] = calls
    assert started["interval_seconds"] == 1800
    assert started["retention"] == timedelta(hours=12)
    assert isinstance(started["storage"], SupabaseStorage)
    assert started["db"] is not None
    assert stopped == {"stopped": True}


def test_server_starts_without_database_or_storage_configuration(monkeypatch) -> None:
    monkeypatch.setattr("app.main.get_settings", lambda: Settings(_env_file=None))

    with TestClient(create_app()) as client:
        assert client.get("/v1/health").status_code == 200
