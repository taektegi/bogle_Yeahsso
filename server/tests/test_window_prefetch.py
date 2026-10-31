"""캐릭터 생성 직후 배경을 미리 시작하고, 친구 저장 시 그 친구에 연결한다."""

import asyncio
from datetime import timedelta
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.auth import CurrentUser, get_current_user
from app.cleanup import cleanup_assets
from app.config import get_settings
from app.db import get_database
from app.images import input_reference
from app.rate_limit import window_limiter
from app.repositories.window_views import WindowViewRepository
from app.storage import get_storage
from app.window_images import day_prompt
from app.window_worker import WindowWorker
from tests.test_creation_db import FakeProvider, complete, creation, payload, uploaded  # noqa: F401
from tests.test_creation_images import png
from tests.test_window_views import Provider


@pytest.fixture(autouse=True)
def own_queue(seed_conn, creation):  # noqa: F811
    # 다른 파일이 직접 넣고 남긴 대기 작업을 이 파일의 워커가 먼저 집지 않게 한다.
    seed_conn.execute(
        "delete from public.generation_jobs where status='queued' and user_id<>%s", (creation[0],)
    )
    seed_conn.execute(
        "delete from public.window_view_jobs where status='queued' and user_id<>%s", (creation[0],)
    )


def window_jobs(seed_conn, user):
    return seed_conn.execute(
        "select * from public.window_view_jobs where user_id=%s order by created_at", (user,)
    ).fetchall()


def run_window(database, creation, provider=None):  # noqa: F811
    _, _, storage, settings = creation
    worker = WindowWorker(database, storage, settings, provider or Provider())
    repo = worker.repo
    assert repo.acquire_lease(worker.owner)
    job = repo.claim(worker.owner)
    asyncio.run(worker.process(job))
    repo.release_lease(worker.owner)
    return repo.job(job["user_id"], job["id"])


def test_generation_success_queues_background_before_friend_is_saved(
    app,
    database,
    seed_conn,
    creation,  # noqa: F811
):
    user, repo, storage, settings = creation
    job = complete(creation, database)
    assert job["status"] == "succeeded"
    [window] = window_jobs(seed_conn, user)
    assert window["status"] == "queued"
    assert window["character_id"] is None
    assert window["generation_job_id"] == job["id"]
    assert window["source_asset_id"] == job["art_asset_id"]

    provider = Provider()
    done = run_window(database, creation, provider)
    assert done["status"] == "succeeded"
    # 설정 전이므로 캐릭터 그림만 참고하고 친구 설정은 보내지 않는다.
    assert "Metadata" not in provider.calls[0][1]
    assert "personality" not in provider.calls[0][1]
    assert "favorites" not in provider.calls[0][1]

    friend_id, _ = repo.save_friend(user, payload(job), str(uuid4()))
    app.dependency_overrides[get_database] = lambda: database
    app.dependency_overrides[get_storage] = lambda: storage
    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_current_user] = lambda: CurrentUser(user)
    body = TestClient(app).get(f"/v1/characters/{friend_id}/window-view").json()
    assert body["status"] == "succeeded"
    assert body["readyJobId"] == str(done["id"])
    assert body["day"] and body["night"] is None


def test_friend_saved_while_queued_uses_only_art_and_reuses_the_job(
    database,
    seed_conn,
    creation,  # noqa: F811
):
    user, repo, _, _ = creation
    job = complete(creation, database)
    friend_id, _ = repo.save_friend(user, payload(job), str(uuid4()))
    [window] = window_jobs(seed_conn, user)
    assert window["character_id"] == friend_id and window["status"] == "queued"

    # 집에 들어간 앱의 요청은 새 유료 작업이 아니라 미리 시작한 작업을 따라간다.
    joined, new = WindowViewRepository(database).enqueue(user, friend_id, str(uuid4()))
    assert not new and joined["id"] == window["id"]

    provider = Provider()
    assert run_window(database, creation, provider)["status"] == "succeeded"
    # 날씨 지시에 '구름'이 있어도 친구 설정을 추가한 것은 아니다.
    # 저장된 친구 설정과 무관하게 공통 프롬프트만 전달됐는지 확인한다.
    assert provider.calls[0][1] == day_prompt()
    assert len(window_jobs(seed_conn, user)) == 1


def test_prefetch_can_be_turned_off(database, seed_conn, creation):  # noqa: F811
    user, repo, storage, settings = creation
    disabled = settings.model_copy(update={"window_prefetch_after_generation": False})
    off = (user, repo, storage, disabled)
    assert complete(off, database)["status"] == "succeeded"
    assert window_jobs(seed_conn, user) == []


def test_each_background_references_its_generated_art_not_the_original(database, creation):  # noqa: F811
    _, _, storage, _ = creation
    for source_color, art_color in (
        ((240, 70, 80, 255), (70, 120, 230, 255)),
        ((70, 210, 100, 255), (210, 120, 230, 255)),
    ):
        original = png(color=source_color)
        art = png(color=art_color)
        source = uploaded(creation, original)
        job = complete(creation, database, source, FakeProvider(result=art))
        provider = Provider()
        done = run_window(database, creation, provider)
        assert done["source_asset_id"] == job["art_asset_id"]
        saved = WindowViewRepository(database).asset(creation[0], job["art_asset_id"])
        assert provider.calls[0][0] == input_reference(storage.download(saved.storage_path))
        assert provider.calls[0][0] != input_reference(original)


def test_prefetch_failure_keeps_character_generation_success(database, creation, monkeypatch):  # noqa: F811
    def unavailable(*_):
        raise RuntimeError("queue unavailable")

    monkeypatch.setattr(WindowViewRepository, "prefetch", unavailable)
    assert complete(creation, database)["status"] == "succeeded"


def test_window_limit_skips_prefetch_but_generation_succeeds(
    database,
    seed_conn,
    creation,  # noqa: F811
):
    user = creation[0]
    for _ in range(window_limiter.limit):
        window_limiter.check(user)
    assert complete(creation, database)["status"] == "succeeded"
    assert window_jobs(seed_conn, user) == []


def test_unsaved_prefetched_background_is_cleaned_up(database, seed_conn, creation):  # noqa: F811
    user, _, storage, _ = creation
    complete(creation, database)
    done = run_window(database, creation)
    seed_conn.execute(
        "update public.window_view_jobs set created_at=now()-interval '2 days' where user_id=%s",
        (user,),
    )
    seed_conn.execute(
        "update public.generation_jobs set created_at=now()-interval '2 days' where user_id=%s",
        (user,),
    )
    seed_conn.execute(
        "update public.assets set created_at=now()-interval '2 days' where user_id=%s", (user,)
    )
    cleanup_assets(database, storage, timedelta(hours=24))
    assert window_jobs(seed_conn, user) == []
    assert not seed_conn.execute(
        "select 1 from public.assets where id = any(%s)",
        ([done["day_asset_id"]],),
    ).fetchone()


def test_deleting_the_saved_friend_removes_the_prefetched_background(
    database,
    seed_conn,
    creation,  # noqa: F811
):
    from app.repositories.characters import CharacterRepository

    user, repo, _, _ = creation
    job = complete(creation, database)
    done = run_window(database, creation)
    friend_id, _ = repo.save_friend(user, payload(job), str(uuid4()))
    assets = CharacterRepository(database).delete_for_user(user, friend_id)
    assert {done["day_asset_id"]} <= {a.id for a in assets}
    assert window_jobs(seed_conn, user) == []


def test_saved_friend_background_has_priority_over_unsaved_candidate(database, creation):  # noqa: F811
    user, repo, _, _ = creation
    first = complete(creation, database)
    second = complete(creation, database)
    friend_id, _ = repo.save_friend(user, payload(second), str(uuid4()))
    windows = WindowViewRepository(database)
    owner = uuid4()
    assert windows.acquire_lease(owner)
    try:
        claimed = windows.claim(owner)
        assert claimed["character_id"] == friend_id
        assert claimed["generation_job_id"] == second["id"]
        assert first["id"] != second["id"]
    finally:
        windows.release_lease(owner)
