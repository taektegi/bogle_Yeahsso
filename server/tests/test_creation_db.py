"""실제 PostgreSQL을 사용하는 업로드→생성→저장과 소유권·경합 검증."""

import asyncio
import threading
import time
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.auth import CurrentUser, get_current_user
from app.cleanup import cleanup_assets
from app.config import Settings, get_settings
from app.db import get_database
from app.errors import ApiError
from app.face_analysis import validate_face_payload
from app.friend_settings import INTRODUCTIONS, SaveFriendIn
from app.generation_worker import GenerationWorker
from app.repositories.characters import CharacterRepository
from app.repositories.creation import CreationRepository
from app.storage import StorageError, get_storage
from tests.db_support import FakeStorage, make_user
from tests.test_creation_images import png, settings_payload


class FakeProvider:
    def __init__(self, result=None, delay=0):
        self.result = result if result is not None else png()
        self.delay = delay
        self.calls = 0

    async def generate(self, reference):
        self.calls += 1
        await asyncio.sleep(self.delay)
        return self.result


@pytest.fixture
def creation(database, seed_conn):
    user = make_user(seed_conn)
    repo = CreationRepository(database)
    storage = FakeStorage()
    settings = Settings(
        _env_file=None,
        openrouter_api_key="fake-key",
        openrouter_face_model="",
        generation_timeout_seconds=3,
    )
    yield user, repo, storage, settings
    # 각 테스트가 남긴 대기 작업을 다음 테스트의 전역 워커가 처리하지 않게 격리한다.
    seed_conn.execute("delete from auth.users where id=%s", (user,))
    seed_conn.execute("delete from public.generation_worker_lease")


def uploaded(creation, data=None):
    user, repo, storage, _ = creation
    data = data if data is not None else png()
    asset = repo.add_asset(user, "source", data, "image/png", 256, 256)
    storage.upload(asset.storage_path, data, "image/png")
    return asset


def complete(creation, database, asset=None, provider=None, analyzer=None):
    user, repo, storage, settings = creation
    asset = asset or uploaded(creation)
    row, _ = repo.enqueue(user, asset.id, "drawing", str(uuid4()))
    worker = GenerationWorker(database, storage, settings, provider or FakeProvider(), analyzer)
    assert repo.acquire_lease(worker.owner)
    job = repo.claim(worker.owner)
    assert job["id"] == row["id"]
    asyncio.run(worker.process(job))
    repo.release_lease(worker.owner)
    return repo.job(user, job["id"])


def payload(job):
    return SaveFriendIn(**settings_payload(generationJobId=str(job["id"])))


def test_real_upload_generate_save_query_delete(app, database, seed_conn, creation):
    user, repo, storage, settings = creation
    app.dependency_overrides[get_database] = lambda: database
    app.dependency_overrides[get_storage] = lambda: storage
    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_current_user] = lambda: CurrentUser(user)
    client = TestClient(app)
    response = client.post("/v1/assets", files={"file": ("wrong.jpg", png(), "text/plain")})
    assert response.status_code == 201
    assert response.json()["contentType"] == "image/png"
    source_id = response.json()["assetId"]
    body = {"sourceAssetId": source_id, "sourceType": "drawing"}
    header = {"Idempotency-Key": str(uuid4())}
    response = client.post("/v1/generations", json=body, headers=header)
    assert response.status_code == 202
    job_id = response.json()["jobId"]
    repeat = client.post("/v1/generations", json=body, headers=header)
    assert repeat.status_code == 200 and repeat.json()["jobId"] == job_id
    worker = GenerationWorker(database, storage, settings, FakeProvider())
    repo.acquire_lease(worker.owner)
    job = repo.claim(worker.owner)
    asyncio.run(worker.process(job))
    repo.release_lease(worker.owner)
    response = client.get(f"/v1/generations/{job_id}")
    assert response.json()["status"] == "succeeded"
    assert response.json()["art"]["width"] == 256
    save = payload(job).model_dump(mode="json", by_alias=True)
    save_key = {"Idempotency-Key": str(uuid4())}
    first = client.post("/v1/characters", json=save, headers=save_key)
    assert first.status_code == 201
    again = client.post("/v1/characters", json=save, headers=save_key)
    assert again.status_code == 200 and again.json() == first.json()
    assert first.json()["introduction"] in INTRODUCTIONS
    assert first.json()["name"] == "구름이"
    other = make_user(seed_conn)
    app.dependency_overrides[get_current_user] = lambda: CurrentUser(other)
    for url in (f"/v1/generations/{job_id}", f"/v1/characters/{first.json()['id']}"):
        assert client.get(url).status_code == 404
    assert client.post(f"/v1/generations/{job_id}/cancel").status_code == 404
    assert (
        client.post(
            "/v1/characters", json=save, headers={"Idempotency-Key": str(uuid4())}
        ).status_code
        == 404
    )
    assert (
        client.post(
            "/v1/generations", json=body, headers={"Idempotency-Key": str(uuid4())}
        ).status_code
        == 404
    )
    app.dependency_overrides[get_current_user] = lambda: CurrentUser(user)
    assert client.delete(f"/v1/characters/{first.json()['id']}").status_code == 204
    assert client.get(f"/v1/generations/{job_id}").status_code == 404
    assert not seed_conn.execute("select 1 from public.assets where user_id=%s", (user,)).fetchone()


def test_idempotency_conflict_cancel_and_failed_retry(creation):
    user, repo, _, _ = creation
    asset = uploaded(creation)
    first, new = repo.enqueue(user, asset.id, "drawing", "same-key-001")
    assert new
    repeat, new = repo.enqueue(user, asset.id, "drawing", "same-key-001")
    assert not new and repeat["id"] == first["id"]
    with pytest.raises(ApiError) as exc:
        repo.enqueue(user, asset.id, "photo", "same-key-001")
    assert exc.value.code == "idempotency_key_conflict"
    assert repo.cancel(user, first["id"])["status"] == "cancelled"
    repeat, _ = repo.enqueue(user, asset.id, "drawing", "same-key-001")
    assert repeat["status"] == "cancelled"
    other, new = repo.enqueue(user, asset.id, "drawing", "different-key-001")
    assert new and other["id"] != first["id"]
    with pytest.raises(ApiError) as exc:
        repo.save_friend(user, payload(other), "save-key-001")
    assert exc.value.code == "generation_not_ready"


@pytest.mark.parametrize(
    "provider,expected",
    [
        (FakeProvider(png(False)), "generation_invalid_result"),
        (FakeProvider(b"wrong"), "generation_invalid_result"),
    ],
)
def test_bad_output_never_succeeds(creation, database, provider, expected):
    row = complete(creation, database, provider=provider)
    assert row["status"] == "failed" and row["error_code"] == expected
    assert provider.calls == 1


def test_readback_failure_is_not_success(creation, database):
    user, repo, storage, _ = creation
    original_download = storage.download

    def broken_download(path):
        if "/art/" in path:
            raise StorageError("unreadable result")
        return original_download(path)

    storage.download = broken_download
    job = complete(creation, database)
    assert job["status"] == "failed" and job["error_retryable"]


def test_timeout_restart_and_requery_no_automatic_paid_retry(creation, database):
    user, repo, storage, settings = creation
    settings.generation_timeout_seconds = 0.05
    provider = FakeProvider(delay=1)
    job = complete(creation, database, provider=provider)
    assert job["status"] == "failed" and job["error_code"] == "generation_timeout"
    assert provider.calls == 1
    settings.generation_timeout_seconds = 3
    source = uploaded(creation)
    processing, _ = repo.enqueue(user, source.id, "drawing", str(uuid4()))
    owner = uuid4()
    repo.acquire_lease(owner)
    repo.claim(owner)
    queued, _ = repo.enqueue(user, source.id, "drawing", str(uuid4()))
    repo.recover()
    assert repo.job(user, processing["id"])["error_code"] == "generation_interrupted"
    assert repo.job(user, queued["id"])["status"] == "queued"
    repo.release_lease(owner)


def test_cancel_races_late_image_result(creation, database):
    user, repo, storage, settings = creation
    source = uploaded(creation)
    row, _ = repo.enqueue(user, source.id, "drawing", str(uuid4()))
    worker = GenerationWorker(database, storage, settings, FakeProvider(delay=0.08))
    repo.acquire_lease(worker.owner)
    job = repo.claim(worker.owner)

    async def scenario():
        task = asyncio.create_task(worker.process(job))
        await asyncio.sleep(0.03)
        await asyncio.to_thread(repo.cancel, user, row["id"])
        await task

    asyncio.run(scenario())
    assert repo.job(user, job["id"])["status"] == "cancelled"
    repo.release_lease(worker.owner)
    assert all(
        "/source/" in path or kind == "image/png" for path, (_, kind) in storage.uploaded.items()
    )


def test_saved_friend_survives_job_expiry_and_replays_same_intro(creation, database, seed_conn):
    user, repo, storage, _ = creation
    job = complete(creation, database)
    first, _ = repo.save_friend(user, payload(job), "save-after-expiry-001")
    seed_conn.execute(
        "update public.generation_jobs set created_at=now()-interval '25 hours' where id=%s",
        (job["id"],),
    )
    repo.cleanup_jobs()
    again, new = repo.save_friend(user, payload(job), "save-after-expiry-001")
    assert first == again and not new
    cleanup_assets(database, storage, timedelta(hours=24))
    assert CharacterRepository(database).get_for_user(user, first) is not None


def test_one_source_cannot_make_two_saved_friends(creation, database):
    user, repo, _, _ = creation
    source = uploaded(creation)
    a = complete(creation, database, source)
    b = complete(creation, database, source)
    repo.save_friend(user, payload(a), str(uuid4()))
    with pytest.raises(ApiError) as exc:
        repo.save_friend(user, payload(b), str(uuid4()))
    assert exc.value.code == "generation_job_already_used"


def test_owner_fk_and_rls_block_other_user(creation, seed_conn):
    user, repo, _, _ = creation
    source = uploaded(creation)
    job, _ = repo.enqueue(user, source.id, "drawing", str(uuid4()))
    other = make_user(seed_conn)
    with seed_conn.transaction():
        seed_conn.execute("set local role authenticated")
        seed_conn.execute("select set_config('request.jwt.claim.sub',%s,true)", (str(other),))
        assert not seed_conn.execute(
            "select id from public.generation_jobs where id=%s", (job["id"],)
        ).fetchone()


def test_worker_max_two_and_result_source_mapping(creation, database):
    user, repo, storage, settings = creation
    expected = {}
    for _ in range(3):
        source = uploaded(creation)
        job, _ = repo.enqueue(user, source.id, "drawing", str(uuid4()))
        expected[job["id"]] = source.id

    class BlockingProvider:
        def __init__(self):
            self.running = 0
            self.maximum = 0
            self.calls = 0
            self.release = asyncio.Event()

        async def generate(self, reference):
            self.calls += 1
            self.running += 1
            self.maximum = max(self.maximum, self.running)
            await self.release.wait()
            self.running -= 1
            return png()

    async def scenario():
        provider = BlockingProvider()
        worker = GenerationWorker(database, storage, settings, provider)
        task = asyncio.create_task(worker.run())
        try:
            async with asyncio.timeout(8):
                while provider.calls < 2:
                    await asyncio.sleep(0.02)
                assert provider.calls == 2 and provider.maximum == 2
                provider.release.set()
                while not all(repo.job(user, key)["status"] == "succeeded" for key in expected):
                    await asyncio.sleep(0.05)
            assert provider.calls == 3 and provider.maximum == 2
        finally:
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)

    asyncio.run(scenario())
    for key, source in expected.items():
        assert repo.job(user, key)["source_asset_id"] == source


FACE = {
    "version": 1,
    "size": [256, 256],
    "facing": "front",
    "head": [40, 30, 176, 196],
    "eyes": [[95, 100, 12], [165, 100, 12]],
    "mouth": [130, 160, 40, 15],
    "cheeks": [[90, 140, 10], [170, 140, 10]],
}


class FakeFaceAnalyzer:
    def __init__(self, mode="success", delay=0):
        self.mode = mode
        self.delay = delay
        self.calls = []

    def analyze(self, image, *, width, height, content_type):
        self.calls.append((image, width, height, content_type, threading.get_ident()))
        time.sleep(self.delay)
        if self.mode == "error":
            raise RuntimeError("private provider failure")
        if self.mode == "none":
            return None
        return validate_face_payload(FACE, width=width, height=height)


def test_face_flows_from_generated_png_to_job_response_and_saved_friend(app, creation, database):
    user, repo, storage, settings = creation
    source = uploaded(creation, png(color=(100, 100, 100, 255)))
    generated = png(color=(240, 180, 200, 255))
    analyzer = FakeFaceAnalyzer()
    job = complete(creation, database, source, FakeProvider(generated), analyzer)
    assert job["face"] == FACE
    [(data, width, height, content_type, thread)] = analyzer.calls
    assert data == generated and (width, height, content_type) == (256, 256, "image/png")
    assert thread != threading.get_ident()

    app.dependency_overrides[get_database] = lambda: database
    app.dependency_overrides[get_storage] = lambda: storage
    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[get_current_user] = lambda: CurrentUser(user)
    client = TestClient(app)
    assert client.get(f"/v1/generations/{job['id']}").json()["face"] == FACE
    key = {"Idempotency-Key": "save-face-001"}
    body = payload(job).model_dump(mode="json", by_alias=True)
    first = client.post("/v1/characters", json=body, headers=key)
    assert first.status_code == 201 and first.json()["face"] == FACE
    replay = client.post("/v1/characters", json=body, headers=key)
    assert replay.status_code == 200 and replay.json() == first.json()
    assert client.get(f"/v1/characters/{first.json()['id']}").json()["face"] == FACE
    assert client.get("/v1/characters").json()["items"][0]["face"] == FACE
    assert len(analyzer.calls) == 1  # 저장·집 조회에서 다시 분석하지 않는다.


@pytest.mark.parametrize("mode,delay", [("error", 0), ("none", 0), ("success", 0.15)])
def test_face_failure_or_late_result_keeps_generation_and_friend_successful(
    app, creation, database, mode, delay
):
    user, repo, storage, settings = creation
    settings.face_analysis_timeout_seconds = 0.03
    analyzer = FakeFaceAnalyzer(mode, delay)
    job = complete(creation, database, analyzer=analyzer)
    assert job["status"] == "succeeded" and job["face"] is None
    friend_id, _ = repo.save_friend(user, payload(job), "save-without-face-001")
    assert CharacterRepository(database).get_for_user(user, friend_id).face is None
    app.dependency_overrides[get_database] = lambda: database
    app.dependency_overrides[get_storage] = lambda: storage
    app.dependency_overrides[get_current_user] = lambda: CurrentUser(user)
    response = TestClient(app).get(f"/v1/generations/{job['id']}")
    assert response.status_code == 200 and response.json()["face"] is None
    assert repo.job(user, job["id"])["face"] is None  # 늦게 완료된 분석도 반영하지 않는다.


def test_face_analyzer_is_initialized_once_and_reused(creation, database, monkeypatch):
    user, repo, storage, settings = creation
    analyzer = FakeFaceAnalyzer()
    built = []

    def build(received_settings):
        built.append(received_settings)
        return analyzer

    monkeypatch.setattr("app.generation_worker.build_face_analyzer", build)
    worker = GenerationWorker(database, storage, settings, FakeProvider())
    repo.acquire_lease(worker.owner)
    try:
        for _ in range(2):
            source = uploaded(creation)
            repo.enqueue(user, source.id, "drawing", str(uuid4()))
            job = repo.claim(worker.owner)
            asyncio.run(worker.process(job))
            assert repo.job(user, job["id"])["face"] == FACE
    finally:
        repo.release_lease(worker.owner)
    assert built == [settings] and len(analyzer.calls) == 2


def test_face_analysis_skipped_when_only_file_storage_budget_remains():
    analyzer = FakeFaceAnalyzer()
    settings = Settings(_env_file=None)
    worker = GenerationWorker(None, None, settings, FakeProvider(), analyzer)
    job = {"id": uuid4(), "started_at": datetime.now(UTC) - timedelta(seconds=220)}
    image = SimpleNamespace(art=png(), width=256, height=256)
    assert asyncio.run(worker.analyze_face(job, image)) is None
    assert analyzer.calls == []
