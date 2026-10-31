import asyncio
import base64
import io
from uuid import uuid4

import httpx2
import pytest
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw

from app.auth import CurrentUser, get_current_user
from app.cleanup import cleanup_assets
from app.config import Settings, get_settings
from app.db import get_database
from app.errors import ApiError
from app.image_provider import GenerationError, OpenRouterImages
from app.images import InvalidImage
from app.repositories.characters import CharacterRepository
from app.repositories.creation import MODEL
from app.repositories.window_views import WindowViewRepository
from app.storage import get_storage
from app.window_images import window_png
from app.window_worker import WindowWorker
from tests.db_support import FakeStorage, make_character, make_user
from tests.test_creation_images import png


def scenery(night=False, size=(2048, 876), mode="RGB"):
    image = Image.new(mode, size, "#454c7c" if night else "#c9ddf0")
    ImageDraw.Draw(image).ellipse(
        (50, 250, size[0] - 50, size[1] + 200), fill="#7c8ca0" if night else "#9bc0ad"
    )
    out = io.BytesIO()
    image.save(out, "PNG")
    return out.getvalue()


class Provider:
    def __init__(self, *, invalid=False):
        self.calls = []
        self.invalid = invalid

    async def generate_window(self, reference, prompt):
        self.calls.append((reference, prompt))
        return b"bad" if self.invalid else scenery()


@pytest.fixture
def scene(database, seed_conn):
    user = make_user(seed_conn)
    character = make_character(seed_conn, user, "민들레")
    repo = WindowViewRepository(database)
    storage = FakeStorage()
    friend = CharacterRepository(database).get_for_user(user, character)
    storage.upload(friend.art.storage_path, png(), "image/png")
    settings = Settings(
        _env_file=None, openrouter_api_key="fake", window_generation_timeout_seconds=5
    )
    yield user, character, repo, storage, settings
    seed_conn.execute("delete from auth.users where id=%s", (user,))
    seed_conn.execute("delete from public.window_worker_lease")


def complete(database, scene, provider=None, *, regenerate=False):
    user, character, repo, storage, settings = scene
    row, _ = repo.enqueue(user, character, str(uuid4()), regenerate=regenerate)
    worker = WindowWorker(database, storage, settings, provider or Provider())
    assert repo.acquire_lease(worker.owner)
    job = repo.claim(worker.owner)
    assert job["id"] == row["id"]
    asyncio.run(worker.process(job))
    repo.release_lease(worker.owner)
    return repo.job(user, row["id"])


def test_day_is_published_after_readback_with_one_ai_call(database, scene):
    provider = Provider()
    job = complete(database, scene, provider)
    assert job["status"] == "succeeded"
    _, _, repo, storage, _ = scene
    for key in ("day_asset_id",):
        asset = repo.asset(job["user_id"], job[key])
        assert asset.width == 2048 and asset.height == 576
        assert Image.open(io.BytesIO(storage.download(asset.storage_path))).size == (2048, 576)
    assert len(provider.calls) == 1
    assert job["night_asset_id"] is None


def test_failed_day_does_not_replace_previous_view_and_no_auto_retry(database, scene):
    success = complete(database, scene)
    provider = Provider(invalid=True)
    failed = complete(database, scene, provider, regenerate=True)
    latest, ready = scene[2].current(scene[0], scene[1])
    assert latest["id"] == failed["id"] and latest["status"] == "failed"
    assert ready["id"] == success["id"]
    assert failed["day_asset_id"] is None and len(provider.calls) == 1
    assert scene[2].claim(uuid4()) is None


def test_enqueue_replay_conflict_and_concurrent_keys(scene):
    user, character, repo, _, _ = scene
    key = str(uuid4())
    first, new = repo.enqueue(user, character, key)
    assert new
    again, new = repo.enqueue(user, character, key)
    assert not new and again["id"] == first["id"]
    alternate_key = str(uuid4())
    another, new = repo.enqueue(user, character, alternate_key)
    assert not new and another["id"] == first["id"]
    with pytest.raises(ApiError) as alternate:
        repo.enqueue(user, character, alternate_key, regenerate=True)
    assert alternate.value.status_code == 409
    with pytest.raises(ApiError) as error:
        repo.enqueue(user, character, key, regenerate=True)
    assert error.value.status_code == 409


def test_owner_api_and_failed_job_polling(app, database, seed_conn, scene):
    user, character, repo, storage, settings = scene
    app.dependency_overrides[get_database] = lambda: database
    app.dependency_overrides[get_storage] = lambda: storage
    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_current_user] = lambda: CurrentUser(user)
    client = TestClient(app)
    path = f"/v1/characters/{character}/window-view"
    assert client.get(path).json()["status"] == "missing"
    response = client.post(path, json={}, headers={"Idempotency-Key": str(uuid4())})
    assert response.status_code == 202
    assert response.json()["day"] is None
    outsider = make_user(seed_conn)
    app.dependency_overrides[get_current_user] = lambda: CurrentUser(outsider)
    assert client.get(path).status_code == 404
    assert client.post(path, json={}, headers={"Idempotency-Key": str(uuid4())}).status_code == 404
    assert repo.current(user, character)[0]["status"] == "queued"


def test_cleanup_retains_published_background_and_delete_marks_it(database, seed_conn, scene):
    job = complete(database, scene)
    user, character, repo, storage, _ = scene
    seed_conn.execute(
        "update public.window_view_jobs set created_at=now()-interval '2 days' where user_id=%s",
        (user,),
    )
    seed_conn.execute(
        "update public.assets set created_at=now()-interval '2 days' where user_id=%s", (user,)
    )
    from datetime import timedelta

    cleanup_assets(database, storage, timedelta(hours=24))
    assert repo.current(user, character)[1]["id"] == job["id"]
    assert repo.asset(user, job["day_asset_id"])
    assets = CharacterRepository(database).delete_for_user(user, character)
    assert job["day_asset_id"] in {asset.id for asset in assets}
    assert job["night_asset_id"] is None
    assert not seed_conn.execute(
        "select 1 from public.window_view_jobs where user_id=%s", (user,)
    ).fetchone()


def test_stale_worker_cannot_publish_after_delete(database, scene):
    user, character, repo, storage, settings = scene
    repo.enqueue(user, character, str(uuid4()))
    worker = WindowWorker(database, storage, settings, Provider())
    assert repo.acquire_lease(worker.owner)
    job = repo.claim(worker.owner)
    CharacterRepository(database).delete_for_user(user, character)
    with pytest.raises(GenerationError):
        worker.persist_day(job, window_png(scenery()))
    # 출력 파일 행은 남더라도 즉시 정리 대상으로 표시된다.
    with database.connection() as conn:
        rows = conn.execute(
            "select delete_requested_at from public.assets where user_id=%s and kind='background'",
            (user,),
        ).fetchall()
    assert len(rows) == 1 and all(row["delete_requested_at"] for row in rows)


@pytest.mark.parametrize("data", [b"wrong", scenery(size=(512, 512)), scenery(mode="RGBA")[:100]])
def test_reject_bad_results(data):
    with pytest.raises(InvalidImage):
        window_png(data)


def test_reject_transparency_and_blank():
    transparent = Image.new("RGBA", (2048, 876), (1, 2, 3, 0))
    out = io.BytesIO()
    transparent.save(out, "PNG")
    with pytest.raises(InvalidImage):
        window_png(out.getvalue())
    opaque = Image.new("RGB", (2048, 876), "white")
    out = io.BytesIO()
    opaque.save(out, "PNG")
    with pytest.raises(InvalidImage):
        window_png(out.getvalue())


def test_provider_uses_supported_panorama_parameters():
    calls = []

    def handle(request):
        import json

        calls.append(json.loads(request.content))
        return httpx2.Response(
            200, json={"data": [{"b64_json": base64.b64encode(scenery()).decode()}]}
        )

    provider = OpenRouterImages(
        Settings(_env_file=None, openrouter_api_key="fake"), httpx2.MockTransport(handle)
    )
    asyncio.run(provider.generate_window("data:image/png;base64,a", "landscape"))
    assert calls[0]["aspect_ratio"] == "21:9"
    assert calls[0]["background"] == "opaque"
    assert calls[0]["model"] == MODEL == "openai/gpt-image-2.5-flare"
    assert calls[0]["n"] == 1
    assert calls[0]["provider"]["allow_fallbacks"] is False


def test_lease_loss_and_restart_require_explicit_retry(database, scene):
    user, character, repo, _, _ = scene
    repo.enqueue(user, character, str(uuid4()))
    owner = uuid4()
    assert repo.acquire_lease(owner)
    assert not repo.acquire_lease(uuid4())
    job = repo.claim(owner)
    repo.release_lease(owner)
    repo.recover()
    assert repo.job(user, job["id"])["status"] == "failed"
    assert repo.claim(owner) is None


def test_rls_blocks_other_users(seed_conn, scene):
    import json

    user, character, repo, _, _ = scene
    repo.enqueue(user, character, str(uuid4()))
    with seed_conn.transaction():
        seed_conn.execute("set local role authenticated")
        seed_conn.execute("select set_config('request.jwt.claim.sub',%s,true)", (str(uuid4()),))
        seed_conn.execute(
            "select set_config('request.jwt.claims',%s,true)", (json.dumps({"sub": str(uuid4())}),)
        )
        assert not seed_conn.execute("select 1 from public.window_view_jobs").fetchone()
        assert not seed_conn.execute("select 1 from public.window_view_requests").fetchone()


def test_background_uses_its_own_quota(scene, monkeypatch):
    from app.rate_limit import generation_limiter, window_limiter

    user, character, repo, _, _ = scene
    hits = []
    monkeypatch.setattr(
        generation_limiter, "check", lambda _: pytest.fail("친구 생성 한도를 차감하면 안 됨")
    )
    monkeypatch.setattr(window_limiter, "check", lambda uid: hits.append(uid))
    first, new = repo.enqueue(user, character, str(uuid4()))
    assert new
    second, new = repo.enqueue(user, character, str(uuid4()))
    assert not new and first["id"] == second["id"]
    assert hits == [user]


def test_readback_failure_does_not_publish_or_replace_previous_day(database, scene):
    done = complete(database, scene)
    storage = scene[3]
    original = storage.download

    def broken(path):
        return b"corrupt" if "/background/" in path else original(path)

    # 새 출력의 읽기 검증만 실패시킨다.
    storage.download = broken
    failed = complete(database, scene, regenerate=True)
    latest, ready = scene[2].current(scene[0], scene[1])
    assert latest["id"] == failed["id"] and latest["status"] == "failed"
    assert ready["id"] == done["id"]


def test_legacy_night_remains_available(app, database, seed_conn, scene):
    done = complete(database, scene)
    user, character, repo, storage, settings = scene
    night = repo.add_asset(user, "background", window_png(scenery(True)), "image/png", 2048, 576)
    storage.upload(night.storage_path, window_png(scenery(True)), "image/png")
    seed_conn.execute(
        "update public.window_view_jobs set night_asset_id=%s where id=%s",
        (night.id, done["id"]),
    )
    app.dependency_overrides[get_database] = lambda: database
    app.dependency_overrides[get_storage] = lambda: storage
    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_current_user] = lambda: CurrentUser(user)
    body = TestClient(app).get(f"/v1/characters/{character}/window-view").json()
    assert body["day"] and body["night"]["assetId"] == str(night.id)
