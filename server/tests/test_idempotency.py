"""멱등 키 공통 부분(app/idempotency.py)."""

import threading
import time
from uuid import UUID, uuid4

import pytest
from fastapi import APIRouter
from fastapi.testclient import TestClient
from pydantic import Field

from app.db import Database
from app.errors import ApiError
from app.idempotency import (
    IdempotencyKey,
    IdempotencyKeyHeader,
    fingerprint,
    insert_or_replay,
)
from app.main import API_PREFIX
from app.schemas import CamelModel
from tests.db_support import make_user

# --- fingerprint -------------------------------------------------------------


def test_fingerprint_ignores_key_order() -> None:
    assert fingerprint({"a": 1, "b": 2}) == fingerprint({"b": 2, "a": 1})


def test_fingerprint_detects_any_change() -> None:
    base = {"name": "구름이", "favoriteThings": ["구름", "사과"], "speechStyle": "해요체"}

    assert fingerprint(base) != fingerprint({**base, "name": "구름이2"})
    assert fingerprint(base) != fingerprint(
        {**base, "favoriteThings": ["사과", "구름"]}
    )  # 순서도 내용
    assert fingerprint(base) != fingerprint({**base, "favoriteThings": ["구름"]})
    assert fingerprint(base) != fingerprint({**base, "extra": None})


def test_fingerprint_is_stable_for_the_same_content() -> None:
    payload = {"name": "구름이", "jobId": UUID("11111111-2222-4333-8444-555555555555")}

    assert fingerprint(payload) == fingerprint(dict(payload))
    assert len(fingerprint(payload)) == 64  # SHA-256 hex


def test_fingerprint_accepts_pydantic_models() -> None:
    class Body(CamelModel):
        source_asset_id: UUID
        source_type: str

    body = Body(source_asset_id=uuid4(), source_type="photo")

    assert fingerprint(body) == fingerprint(body.model_dump(mode="json"))
    assert fingerprint(body) != fingerprint(body.model_copy(update={"source_type": "drawing"}))


# --- 헤더·본문 필드 검사 -----------------------------------------------------


class Echo(CamelModel):
    client_message_id: IdempotencyKey
    text: str = Field(min_length=1)


@pytest.fixture
def probe(app) -> None:
    router = APIRouter()

    @router.post("/_idem")
    def with_header(key: IdempotencyKeyHeader) -> dict[str, str]:
        return {"key": key}

    @router.post("/_idem-body")
    def with_body(body: Echo) -> dict[str, str]:
        return {"id": body.client_message_id}

    app.include_router(router, prefix=API_PREFIX)


def post(client: TestClient, key: str | None):
    headers = {} if key is None else {"Idempotency-Key": key}
    return client.post("/v1/_idem", headers=headers)


@pytest.mark.parametrize("key", [str(uuid4()), "abcdefgh", "A_b-C_d-1234", "x" * 64])
def test_valid_keys_are_accepted(probe, client: TestClient, key: str) -> None:
    response = post(client, key)

    assert response.status_code == 200
    assert response.json() == {"key": key}


def test_header_name_is_case_insensitive(probe, client: TestClient) -> None:
    response = client.post("/v1/_idem", headers={"idempotency-key": "abcdefgh"})

    assert response.status_code == 200


def test_missing_key_is_a_validation_error(probe, client: TestClient) -> None:
    response = post(client, None)

    assert response.status_code == 422
    error = response.json()["error"]
    assert error["code"] == "validation_error"
    assert error["fieldErrors"] == {"Idempotency-Key": "missing"}


@pytest.mark.parametrize(
    ("key", "kind"),
    [
        ("short", "string_too_short"),
        ("x" * 65, "string_too_long"),
        ("has space 123", "string_pattern_mismatch"),
        ("slash/slash/slash", "string_pattern_mismatch"),
        ("semi;colon;colon", "string_pattern_mismatch"),
    ],
)
def test_invalid_keys_are_rejected(probe, client: TestClient, key: str, kind: str) -> None:
    response = post(client, key)

    assert response.status_code == 422
    assert response.json()["error"]["fieldErrors"] == {"Idempotency-Key": kind}


def test_body_key_field_uses_the_same_rules(probe, client: TestClient) -> None:
    ok = client.post("/v1/_idem-body", json={"clientMessageId": "client-msg-0001", "text": "안녕"})
    bad = client.post("/v1/_idem-body", json={"clientMessageId": "short", "text": "안녕"})

    assert ok.status_code == 200
    assert bad.status_code == 422
    assert bad.json()["error"]["fieldErrors"] == {"clientMessageId": "string_too_short"}


@pytest.mark.parametrize("key", ["한글키한글키한글키", "has space 123", "slash/slash/slash"])
def test_body_key_field_rejects_unsafe_characters(probe, client: TestClient, key: str) -> None:
    response = client.post("/v1/_idem-body", json={"clientMessageId": key, "text": "안녕"})

    assert response.status_code == 422
    assert response.json()["error"]["fieldErrors"] == {"clientMessageId": "string_pattern_mismatch"}


def test_header_is_documented_as_required_in_openapi(probe, client: TestClient) -> None:
    operation = client.get("/openapi.json").json()["paths"]["/v1/_idem"]["post"]
    [parameter] = [p for p in operation["parameters"] if p["name"] == "Idempotency-Key"]

    assert parameter["in"] == "header"
    assert parameter["required"] is True
    assert parameter["schema"]["minLength"] == 8
    assert parameter["schema"]["maxLength"] == 64


# --- insert_or_replay (실제 PostgreSQL) ----------------------------------------


@pytest.fixture
def things(seed_conn):
    """키·지문 컬럼을 가진 테스트용 테이블. generation_jobs/friends가 따를 모양이다."""
    seed_conn.execute(
        "create table public.test_things ("
        " id uuid primary key default gen_random_uuid(),"
        " user_id uuid not null,"
        " idempotency_key text not null,"
        " request_fingerprint text not null,"
        " payload text,"
        " unique (user_id, idempotency_key))"
    )
    yield "public.test_things"
    seed_conn.execute("drop table public.test_things")


def values_for(user_id, key: str, payload: str = "내용") -> dict:
    return {"user_id": user_id, "idempotency_key": key, "payload": payload}


def count(conn, table: str) -> int:
    return conn.execute(f"select count(*) as n from {table}").fetchone()["n"]


def call(database: Database, table: str, user_id, key: str, payload: str = "내용"):
    with database.connection() as conn:
        return insert_or_replay(
            conn,
            table=table,
            values=values_for(user_id, key, payload),
            unique_columns=("user_id", "idempotency_key"),
            request_fingerprint=fingerprint({"payload": payload}),
        )


def test_first_request_creates_the_row(database, seed_conn, things) -> None:
    user = make_user(seed_conn)

    row, created = call(database, things, user, "key-00000001")

    assert created is True
    assert row["payload"] == "내용"
    assert row["request_fingerprint"] == fingerprint({"payload": "내용"})
    assert count(seed_conn, things) == 1


def test_same_key_and_content_replays_the_existing_row(database, seed_conn, things) -> None:
    user = make_user(seed_conn)
    first, created_first = call(database, things, user, "key-00000001")

    again, created_again = call(database, things, user, "key-00000001")

    assert (created_first, created_again) == (True, False)
    assert again["id"] == first["id"]
    assert count(seed_conn, things) == 1


def test_same_key_with_different_content_is_a_conflict(database, seed_conn, things) -> None:
    user = make_user(seed_conn)
    call(database, things, user, "key-00000001", "원래 내용")

    with pytest.raises(ApiError) as excinfo:
        call(database, things, user, "key-00000001", "다른 내용")

    assert excinfo.value.status_code == 409
    assert excinfo.value.code == "idempotency_key_conflict"
    assert excinfo.value.retryable is False
    assert count(seed_conn, things) == 1


def test_a_new_key_creates_a_second_row(database, seed_conn, things) -> None:
    user = make_user(seed_conn)

    first, _ = call(database, things, user, "key-00000001")
    second, created = call(database, things, user, "key-00000002")

    assert created is True
    assert second["id"] != first["id"]


def test_keys_are_scoped_to_the_user(database, seed_conn, things) -> None:
    a, b = make_user(seed_conn), make_user(seed_conn)

    row_a, created_a = call(database, things, a, "shared-key-001", "A의 내용")
    row_b, created_b = call(database, things, b, "shared-key-001", "B의 내용")

    assert (created_a, created_b) == (True, True)  # 다른 사용자의 같은 키는 충돌하지 않는다
    assert row_a["id"] != row_b["id"]
    assert row_b["payload"] == "B의 내용"


def test_a_replay_returns_my_row_even_if_another_user_used_the_same_key(
    database, seed_conn, things
) -> None:
    a, b = make_user(seed_conn), make_user(seed_conn)
    # B가 먼저 같은 키를 썼다. A의 재전송이 B의 행을 돌려주면 안 된다.
    row_b, _ = call(database, things, b, "shared-key-001", "B의 내용")
    row_a, _ = call(database, things, a, "shared-key-001", "A의 내용")

    replay_a, created = call(database, things, a, "shared-key-001", "A의 내용")

    assert created is False
    assert replay_a["id"] == row_a["id"] != row_b["id"]
    assert replay_a["user_id"] == a
    assert replay_a["payload"] == "A의 내용"

    # 내용이 다르면 A의 행과 비교해서 충돌이다 (B의 내용과 우연히 같아도 상관없다).
    with pytest.raises(ApiError) as excinfo:
        call(database, things, a, "shared-key-001", "B의 내용")
    assert excinfo.value.code == "idempotency_key_conflict"


def test_a_failure_after_the_insert_rolls_the_key_back(database, seed_conn, things) -> None:
    user = make_user(seed_conn)

    with pytest.raises(RuntimeError), database.connection() as conn:
        insert_or_replay(
            conn,
            table=things,
            values=values_for(user, "key-00000001"),
            unique_columns=("user_id", "idempotency_key"),
            request_fingerprint=fingerprint({"payload": "내용"}),
        )
        raise RuntimeError("뒤따르는 작업이 실패했다")

    assert count(seed_conn, things) == 0
    _, created = call(database, things, user, "key-00000001")  # 같은 키로 다시 시도할 수 있다
    assert created is True


def test_two_simultaneous_requests_with_the_same_key_create_one_row(
    database, seed_conn, things
) -> None:
    user = make_user(seed_conn)
    inserted = threading.Event()
    release = threading.Event()
    results: dict[str, tuple] = {}

    def first_request() -> None:
        with database.connection() as conn:
            row, created = insert_or_replay(
                conn,
                table=things,
                values=values_for(user, "key-00000001"),
                unique_columns=("user_id", "idempotency_key"),
                request_fingerprint=fingerprint({"payload": "내용"}),
            )
            results["first"] = (row, created)
            inserted.set()
            release.wait(5)  # 아직 커밋하지 않은 채로 기다린다

    def second_request() -> None:
        results["second"] = call(database, things, user, "key-00000001")

    t1 = threading.Thread(target=first_request)
    t1.start()
    assert inserted.wait(5)
    t2 = threading.Thread(target=second_request)
    t2.start()
    time.sleep(0.3)
    assert "second" not in results  # 첫 요청이 끝나기를 기다리는 중이다
    release.set()
    t1.join(5)
    t2.join(5)

    first_row, first_created = results["first"]
    second_row, second_created = results["second"]
    assert (first_created, second_created) == (True, False)
    assert second_row["id"] == first_row["id"]
    assert count(seed_conn, things) == 1


def test_if_the_first_simultaneous_request_fails_the_second_one_creates_the_row(
    database, seed_conn, things
) -> None:
    user = make_user(seed_conn)
    inserted = threading.Event()
    release = threading.Event()
    results: dict[str, tuple] = {}

    def failing_request() -> None:
        try:
            with database.connection() as conn:
                insert_or_replay(
                    conn,
                    table=things,
                    values=values_for(user, "key-00000001"),
                    unique_columns=("user_id", "idempotency_key"),
                    request_fingerprint=fingerprint({"payload": "내용"}),
                )
                inserted.set()
                release.wait(5)
                raise RuntimeError("실패")
        except RuntimeError:
            pass

    def second_request() -> None:
        results["second"] = call(database, things, user, "key-00000001")

    t1 = threading.Thread(target=failing_request)
    t1.start()
    assert inserted.wait(5)
    t2 = threading.Thread(target=second_request)
    t2.start()
    time.sleep(0.3)
    release.set()
    t1.join(5)
    t2.join(5)

    _, created = results["second"]
    assert created is True
    assert count(seed_conn, things) == 1


def test_other_unique_constraints_still_raise_to_the_caller(database, seed_conn) -> None:
    """예: friends.generation_job_id. 호출하는 쪽이 제약 이름을 보고 409로 바꾼다."""
    import psycopg

    seed_conn.execute(
        "create table public.test_jobs_used ("
        " user_id uuid not null, idempotency_key text not null,"
        " request_fingerprint text not null, job_id uuid unique,"
        " unique (user_id, idempotency_key))"
    )
    try:
        user = make_user(seed_conn)
        job = uuid4()

        def create(key: str):
            with database.connection() as conn:
                return insert_or_replay(
                    conn,
                    table="public.test_jobs_used",
                    values={"user_id": user, "idempotency_key": key, "job_id": job},
                    unique_columns=("user_id", "idempotency_key"),
                    request_fingerprint=fingerprint({"job": str(job)}),
                )

        assert create("key-00000001")[1] is True
        assert create("key-00000001")[1] is False  # 같은 키 → 재전송
        with pytest.raises(psycopg.errors.UniqueViolation) as excinfo:
            create("key-00000002")  # 다른 키로 같은 작업 → job_id 유일 제약
        assert excinfo.value.diag.constraint_name == "test_jobs_used_job_id_key"
    finally:
        seed_conn.execute("drop table public.test_jobs_used")


def test_unsafe_identifiers_are_rejected_before_any_sql_runs(database, seed_conn) -> None:
    user = make_user(seed_conn)
    with database.connection() as conn:
        for table in ("friends; drop table friends", 'public."friends"', "Friends"):
            with pytest.raises(ValueError):
                insert_or_replay(
                    conn,
                    table=table,
                    values={"user_id": user, "idempotency_key": "key-00000001"},
                    unique_columns=("user_id", "idempotency_key"),
                    request_fingerprint="x",
                )
        with pytest.raises(ValueError):
            insert_or_replay(
                conn,
                table="public.test_things",
                values={"user_id": user, "idempotency_key": "key-00000001"},
                unique_columns=("user_id; --",),
                request_fingerprint="x",
            )


def test_values_must_include_the_unique_columns(database, seed_conn, things) -> None:
    with database.connection() as conn, pytest.raises(ValueError):
        insert_or_replay(
            conn,
            table=things,
            values={"payload": "x"},
            unique_columns=("user_id", "idempotency_key"),
            request_fingerprint="x",
        )
