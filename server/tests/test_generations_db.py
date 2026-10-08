"""업로드 → 생성 시작 → 처리 → 조회·취소를 실제 PostgreSQL로 확인한다."""

import io
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.ai import AiRejected, get_ai
from app.db import Database, get_database
from app.rate_limit import generation_limiter, upload_limiter
from app.repositories.generations import GenerationRepository
from app.storage import get_storage
from app.workers import process_generation
from tests.ai_support import FakeArtist, child_drawing, fake_ai, front_character, jpeg
from tests.db_support import FakeStorage, make_user
from tests.tokens import bearer, hs256_token


@pytest.fixture(autouse=True)
def _fresh_limits():
    for limiter in (upload_limiter, generation_limiter):
        limiter._hits.clear()


@pytest.fixture(autouse=True)
def _no_jobs_left_over(seed_conn) -> None:
    """한 세션의 DB를 여러 테스트가 같이 쓴다. 다른 테스트가 남긴 대기 작업을 치운다."""
    seed_conn.execute(
        "update public.generation_jobs set status = 'cancelled'"
        " where status in ('queued', 'processing')"
    )


@pytest.fixture
def storage() -> FakeStorage:
    return FakeStorage()


@pytest.fixture
def api(app, client: TestClient, database: Database, storage: FakeStorage) -> TestClient:
    app.dependency_overrides[get_database] = lambda: database
    app.dependency_overrides[get_storage] = lambda: storage
    app.dependency_overrides[get_ai] = lambda: fake_ai()
    return client


def auth(user) -> dict[str, str]:
    return bearer(hs256_token(sub=str(user)))


def upload(api: TestClient, user, data: bytes, name: str = "drawing.png") -> dict:
    response = api.post("/v1/assets", headers=auth(user), files={"file": (name, data)})
    assert response.status_code == 201, response.text
    return response.json()


def start(api: TestClient, user, asset_id: str, key: str = "gen-key-0001", kind="drawing"):
    return api.post(
        "/v1/generations",
        headers={**auth(user), "Idempotency-Key": key},
        json={"sourceAssetId": asset_id, "sourceType": kind},
    )


def work(database: Database, storage: FakeStorage, ai=None) -> str:
    repo = GenerationRepository(database)
    job = repo.claim_next()
    assert job is not None
    return process_generation(job, repo=repo, storage=storage, ai=ai or fake_ai(), timeout=240)


# ---------------------------------------------------------------------------
# 업로드
# ---------------------------------------------------------------------------


def test_upload_returns_an_image_reference_and_keeps_the_file(api, seed_conn, storage) -> None:
    user = make_user(seed_conn)

    ref = upload(api, user, child_drawing())

    assert ref["contentType"] == "image/png"
    assert (ref["width"], ref["height"]) == (1200, 800)
    [path] = storage.uploaded
    assert path.startswith(f"{user}/sources/")
    refreshed = api.get(f"/v1/assets/{ref['assetId']}", headers=auth(user))
    assert refreshed.status_code == 200
    assert refreshed.json()["assetId"] == ref["assetId"]


def test_upload_reads_the_format_from_the_content(api, seed_conn) -> None:
    user = make_user(seed_conn)

    ref = upload(api, user, jpeg(front_character((255, 255, 255))), name="looks-like.png")

    assert ref["contentType"] == "image/jpeg"


@pytest.mark.parametrize(
    ("data", "status", "code"),
    [
        (b"not an image at all", 422, "invalid_image"),
        (b"\x89PNG\r\n\x1a\n" + b"\0" * 100, 422, "invalid_image"),
        ("tiny", 422, "invalid_image"),
        ("huge", 413, "file_too_large"),
    ],
)
def test_upload_rejects_what_cannot_be_used(api, seed_conn, data, status, code) -> None:
    user = make_user(seed_conn)
    if data == "tiny":
        buffer = io.BytesIO()
        Image.new("RGB", (32, 32), "white").save(buffer, format="PNG")
        data = buffer.getvalue()
    elif data == "huge":
        data = b"\x89PNG\r\n\x1a\n" + b"\0" * (10 * 1024 * 1024 + 1)

    response = api.post("/v1/assets", headers=auth(user), files={"file": ("x.png", data)})

    assert response.status_code == status
    assert response.json()["error"]["code"] == code


def test_someone_elses_asset_is_not_found(api, seed_conn) -> None:
    me, other = make_user(seed_conn), make_user(seed_conn)
    ref = upload(api, other, child_drawing())

    response = api.get(f"/v1/assets/{ref['assetId']}", headers=auth(me))

    assert response.status_code == 404


# ---------------------------------------------------------------------------
# 생성
# ---------------------------------------------------------------------------


def test_a_job_is_queued_then_succeeds_with_art_and_a_face_map(
    api, seed_conn, database, storage
) -> None:
    user = make_user(seed_conn)
    source = upload(api, user, child_drawing())

    first = start(api, user, source["assetId"])
    assert first.status_code == 202
    job = first.json()
    assert job["status"] == "queued"
    assert job["pollAfterMs"] == 2000

    assert work(database, storage) == "succeeded"

    done = api.get(f"/v1/generations/{job['jobId']}", headers=auth(user)).json()
    assert done["status"] == "succeeded"
    assert done["art"]["contentType"] == "image/png"
    assert done["thumbnail"]["width"] == 256
    assert done["accentArgb"] >> 24 == 0xFF
    assert len(done["face"]["eyes"]) == 2
    assert len(done["face"]["mouth"]) == 4
    assert "pollAfterMs" not in done
    assert any(p.endswith("/art.png") for p in storage.uploaded)


def test_the_same_key_returns_the_same_job_with_200(api, seed_conn) -> None:
    user = make_user(seed_conn)
    source = upload(api, user, child_drawing())

    first = start(api, user, source["assetId"]).json()
    again = start(api, user, source["assetId"])

    assert again.status_code == 200
    assert again.json()["jobId"] == first["jobId"]


def test_the_same_key_with_other_content_is_a_conflict(api, seed_conn) -> None:
    user = make_user(seed_conn)
    source = upload(api, user, child_drawing())
    start(api, user, source["assetId"])

    response = start(api, user, source["assetId"], kind="photo")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "idempotency_key_conflict"


def test_starting_from_someone_elses_upload_is_not_found(api, seed_conn) -> None:
    me, other = make_user(seed_conn), make_user(seed_conn)
    source = upload(api, other, child_drawing())

    response = start(api, me, source["assetId"])

    assert response.status_code == 404


def test_a_rejected_drawing_reports_why_and_that_retrying_will_not_help(
    api, seed_conn, database, storage
) -> None:
    user = make_user(seed_conn)
    job = start(api, user, upload(api, user, child_drawing())["assetId"]).json()

    work(database, storage, fake_ai(FakeArtist(errors=[AiRejected("moderation_blocked")])))

    done = api.get(f"/v1/generations/{job['jobId']}", headers=auth(user)).json()
    assert done["status"] == "failed"
    assert done["error"]["code"] == "generation_rejected"
    assert done["error"]["retryable"] is False
    assert done["error"]["message"]
    assert "art" not in done


def test_a_cancelled_job_never_gets_its_result(api, seed_conn, database, storage) -> None:
    user = make_user(seed_conn)
    job = start(api, user, upload(api, user, child_drawing())["assetId"]).json()
    repo = GenerationRepository(database)
    claimed = repo.claim_next()

    cancelled = api.post(f"/v1/generations/{job['jobId']}/cancel", headers=auth(user))
    outcome = process_generation(claimed, repo=repo, storage=storage, ai=fake_ai(), timeout=240)

    assert cancelled.json() == {"jobId": job["jobId"], "status": "cancelled"}
    assert outcome == "cancelled"
    final = api.get(f"/v1/generations/{job['jobId']}", headers=auth(user)).json()
    assert final["status"] == "cancelled"
    assert not any(p.endswith("/art.png") for p in storage.uploaded)


def test_cancelling_a_finished_job_reports_its_final_state(
    api, seed_conn, database, storage
) -> None:
    user = make_user(seed_conn)
    job = start(api, user, upload(api, user, child_drawing())["assetId"]).json()
    work(database, storage)

    response = api.post(f"/v1/generations/{job['jobId']}/cancel", headers=auth(user))

    assert response.status_code == 200
    assert response.json()["status"] == "succeeded"


def test_a_retry_after_failure_uses_a_new_key_and_the_same_upload(
    api, seed_conn, database, storage
) -> None:
    user = make_user(seed_conn)
    source = upload(api, user, child_drawing())["assetId"]
    start(api, user, source, key="first-try-1")
    work(database, storage, fake_ai(FakeArtist(errors=[AiRejected("x")])))

    retry = start(api, user, source, key="second-try-2")
    work(database, storage)

    assert retry.status_code == 202
    done = api.get(f"/v1/generations/{retry.json()['jobId']}", headers=auth(user)).json()
    assert done["status"] == "succeeded"


def test_a_stuck_job_times_out_and_an_interrupted_one_is_picked_up_again(
    api, seed_conn, database
) -> None:
    user = make_user(seed_conn)
    stuck = start(api, user, upload(api, user, child_drawing())["assetId"], key="stuck-0001")
    interrupted = start(api, user, upload(api, user, child_drawing())["assetId"], key="cut-00001")
    repo = GenerationRepository(database)
    repo.claim_next()
    repo.claim_next()
    seed_conn.execute(
        "update public.generation_jobs set started_at = now() - interval '10 minutes'"
        " where id = %s",
        (stuck.json()["jobId"],),
    )

    assert repo.fail_stale(300) == 1
    assert repo.requeue_interrupted() == 1

    timed_out = api.get(f"/v1/generations/{stuck.json()['jobId']}", headers=auth(user)).json()
    assert timed_out["error"]["code"] == "generation_timeout"
    assert timed_out["error"]["retryable"] is True
    again = api.get(f"/v1/generations/{interrupted.json()['jobId']}", headers=auth(user)).json()
    assert again["status"] == "queued"


def test_unknown_job_is_not_found(api, seed_conn) -> None:
    user = make_user(seed_conn)

    assert api.get(f"/v1/generations/{uuid4()}", headers=auth(user)).status_code == 404
    assert api.post(f"/v1/generations/{uuid4()}/cancel", headers=auth(user)).status_code == 404
