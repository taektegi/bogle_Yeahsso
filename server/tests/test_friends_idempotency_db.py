"""friends 테이블에 멱등 키 헬퍼를 붙였을 때의 동작 (실제 PostgreSQL, 마이그레이션 적용)."""

from uuid import uuid4

import psycopg
import pytest

from app.errors import ApiError
from app.idempotency import fingerprint, insert_or_replay
from tests.db_support import make_asset, make_character, make_user

UNIQUE = ("user_id", "idempotency_key")


def friend_values(conn, user, key: str | None, *, name: str = "구름이", job=None) -> dict:
    if job is not None:
        source = make_asset(conn, user, "source")[0]
        conn.execute(
            "insert into public.generation_jobs "
            "(id,user_id,source_asset_id,source_type,idempotency_key,"
            "request_fingerprint,model,prompt_version) "
            "values (%s,%s,%s,'drawing',%s,'test','test','test') on conflict(id) do nothing",
            (job, user, source, str(job)),
        )
    values = {
        "user_id": user,
        "name": name,
        "personality_type": "calm",
        "favorite_things": ["구름", "사과"],
        "speech_style": "해요체",
        "art_asset_id": make_asset(conn, user, "art")[0],
        "thumbnail_asset_id": make_asset(conn, user, "thumbnail")[0],
        "accent_argb": 4289974783,
        "generation_job_id": job,
    }
    if key is not None:
        values["idempotency_key"] = key
    return values


def request_of(values: dict) -> dict:
    return {k: values[k] for k in ("name", "personality_type", "favorite_things", "speech_style")}


def create(database, values: dict):
    with database.connection() as conn:
        return insert_or_replay(
            conn,
            table="public.friends",
            values=values,
            unique_columns=UNIQUE,
            request_fingerprint=fingerprint(request_of(values)),
        )


def friend_count(conn, user) -> int:
    return conn.execute(
        "select count(*) as n from public.friends where user_id = %s", (user,)
    ).fetchone()["n"]


def test_a_request_creates_a_friend_and_a_resend_returns_the_same_one(database, seed_conn) -> None:
    user = make_user(seed_conn)
    values = friend_values(seed_conn, user, "key-00000001")

    first, created = create(database, values)
    again, created_again = create(database, values)

    assert (created, created_again) == (True, False)
    assert again["id"] == first["id"]
    assert first["name"] == "구름이"
    assert friend_count(seed_conn, user) == 1


def test_the_same_key_with_different_content_is_a_conflict(database, seed_conn) -> None:
    user = make_user(seed_conn)
    create(database, friend_values(seed_conn, user, "key-00000001", name="구름이"))

    with pytest.raises(ApiError) as excinfo:
        create(database, friend_values(seed_conn, user, "key-00000001", name="다른이름"))

    assert excinfo.value.status_code == 409
    assert excinfo.value.code == "idempotency_key_conflict"
    assert friend_count(seed_conn, user) == 1


def test_users_can_use_the_same_key(database, seed_conn) -> None:
    a, b = make_user(seed_conn), make_user(seed_conn)

    row_a, created_a = create(database, friend_values(seed_conn, a, "shared-key-001"))
    row_b, created_b = create(database, friend_values(seed_conn, b, "shared-key-001"))

    assert (created_a, created_b) == (True, True)
    assert row_a["id"] != row_b["id"]


def test_a_second_key_for_the_same_generation_job_hits_the_job_constraint(
    database, seed_conn
) -> None:
    """다른 키로 이미 쓴 작업을 다시 쓰면 헬퍼가 아니라 job 유일 제약이 막는다.

    이 오류를 409로 바꾸는 것은 호출하는 쪽이다.
    """
    user = make_user(seed_conn)
    job = uuid4()
    create(database, friend_values(seed_conn, user, "key-00000001", job=job))

    with pytest.raises(psycopg.errors.UniqueViolation) as excinfo:
        create(database, friend_values(seed_conn, user, "key-00000002", job=job))

    assert excinfo.value.diag.constraint_name == "friends_generation_job_id_key"
    assert friend_count(seed_conn, user) == 1


def test_a_resend_with_the_same_key_is_not_blocked_by_the_job_constraint(
    database, seed_conn
) -> None:
    user = make_user(seed_conn)
    job = uuid4()
    values = friend_values(seed_conn, user, "key-00000001", job=job)
    first, _ = create(database, values)

    again, created = create(database, values)  # 같은 키 → 재전송이므로 job 제약까지 가지 않는다

    assert created is False
    assert again["id"] == first["id"]


def test_friends_without_a_key_never_conflict(seed_conn) -> None:
    user = make_user(seed_conn)

    make_character(seed_conn, user, "시드 1")
    make_character(seed_conn, user, "시드 2")

    assert friend_count(seed_conn, user) == 2


@pytest.mark.parametrize("key", ["short", "x" * 65, "has space 123", "slash/slash/slash"])
def test_the_database_rejects_malformed_keys(seed_conn, key: str) -> None:
    user = make_user(seed_conn)
    values = {
        **friend_values(seed_conn, user, None),
        "idempotency_key": key,
        "request_fingerprint": "x",
    }
    columns = list(values)

    with pytest.raises(psycopg.errors.CheckViolation):
        seed_conn.execute(
            f"insert into public.friends ({', '.join(columns)})"
            f" values ({', '.join(f'%({c})s' for c in columns)})",
            values,
        )


def test_key_and_fingerprint_must_come_together(seed_conn) -> None:
    user = make_user(seed_conn)
    values = {**friend_values(seed_conn, user, "key-00000001"), "request_fingerprint": None}
    columns = list(values)

    with pytest.raises(psycopg.errors.CheckViolation) as excinfo:
        seed_conn.execute(
            f"insert into public.friends ({', '.join(columns)})"
            f" values ({', '.join(f'%({c})s' for c in columns)})",
            values,
        )

    assert excinfo.value.diag.constraint_name == "friends_idempotency_check"
