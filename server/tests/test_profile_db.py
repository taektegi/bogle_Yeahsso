"""프로필 API를 실제 PostgreSQL로 확인한다. TEST_DATABASE_URL이 없으면 건너뛴다."""

from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.db import Database, get_database
from tests.db_support import make_character, make_user
from tests.tokens import bearer, hs256_token


@pytest.fixture
def api(app, client: TestClient, database: Database) -> TestClient:
    app.dependency_overrides[get_database] = lambda: database
    return client


def token_for(user_id) -> dict[str, str]:
    return bearer(hs256_token(sub=str(user_id)))


def test_new_user_gets_the_default_profile(api, seed_conn) -> None:
    user = make_user(seed_conn)

    response = api.get("/v1/me", headers=token_for(user))

    assert response.status_code == 200
    assert response.json() == {
        "nickname": "그린고블린",
        "avatarCharacterId": None,
        "friendNotifications": True,
        "orderNotifications": True,
        "characterCount": 0,
    }


def test_character_count_counts_only_my_characters(api, seed_conn) -> None:
    me, other = make_user(seed_conn), make_user(seed_conn)
    make_character(seed_conn, me, "하나")
    make_character(seed_conn, me, "둘")
    make_character(seed_conn, other, "남의 친구")

    assert api.get("/v1/me", headers=token_for(me)).json()["characterCount"] == 2
    assert api.get("/v1/me", headers=token_for(other)).json()["characterCount"] == 1


def test_patch_updates_and_returns_the_whole_profile(api, seed_conn) -> None:
    user = make_user(seed_conn)

    response = api.patch(
        "/v1/me",
        json={"nickname": "  초코  ", "friendNotifications": False},
        headers=token_for(user),
    )

    assert response.json() == {
        "nickname": "초코",
        "avatarCharacterId": None,
        "friendNotifications": False,
        "orderNotifications": True,
        "characterCount": 0,
    }
    assert api.get("/v1/me", headers=token_for(user)).json()["nickname"] == "초코"


def test_patch_leaves_other_fields_alone(api, seed_conn) -> None:
    user = make_user(seed_conn)
    api.patch(
        "/v1/me", json={"nickname": "초코", "orderNotifications": False}, headers=token_for(user)
    )

    profile = api.patch(
        "/v1/me", json={"friendNotifications": False}, headers=token_for(user)
    ).json()

    assert profile["nickname"] == "초코"
    assert profile["orderNotifications"] is False
    assert profile["friendNotifications"] is False


def test_patch_only_changes_my_own_profile(api, seed_conn) -> None:
    me, other = make_user(seed_conn), make_user(seed_conn)

    api.patch("/v1/me", json={"nickname": "나만"}, headers=token_for(me))

    assert api.get("/v1/me", headers=token_for(other)).json()["nickname"] == "그린고블린"


def test_twelve_korean_characters_fit_in_the_database(api, seed_conn) -> None:
    user = make_user(seed_conn)

    response = api.patch(
        "/v1/me", json={"nickname": "가나다라마바사아자차카타"}, headers=token_for(user)
    )

    assert response.status_code == 200
    assert response.json()["nickname"] == "가나다라마바사아자차카타"


def test_avatar_can_be_one_of_my_characters(api, seed_conn) -> None:
    user = make_user(seed_conn)
    character = make_character(seed_conn, user, "내 친구")

    response = api.patch(
        "/v1/me", json={"avatarCharacterId": str(character)}, headers=token_for(user)
    )

    assert response.status_code == 200
    assert response.json()["avatarCharacterId"] == str(character)


def test_avatar_cannot_be_another_users_character(api, seed_conn) -> None:
    me, other = make_user(seed_conn), make_user(seed_conn)
    stolen = make_character(seed_conn, other, "남의 친구")

    response = api.patch(
        "/v1/me",
        json={"nickname": "바뀌면 안 됨", "avatarCharacterId": str(stolen)},
        headers=token_for(me),
    )

    assert response.status_code == 422
    error = response.json()["error"]
    assert error["code"] == "validation_error"
    assert error["fieldErrors"] == {"avatarCharacterId": "character_not_found"}
    # 실패한 요청은 다른 필드도 바꾸지 않는다.
    assert api.get("/v1/me", headers=token_for(me)).json()["nickname"] == "그린고블린"


def test_avatar_cannot_be_an_unknown_character(api, seed_conn) -> None:
    user = make_user(seed_conn)

    response = api.patch(
        "/v1/me", json={"avatarCharacterId": str(uuid4())}, headers=token_for(user)
    )

    assert response.status_code == 422
    assert response.json()["error"]["fieldErrors"] == {"avatarCharacterId": "character_not_found"}


def test_null_resets_the_avatar_to_default(api, seed_conn) -> None:
    user = make_user(seed_conn)
    character = make_character(seed_conn, user, "내 친구")
    api.patch("/v1/me", json={"avatarCharacterId": str(character)}, headers=token_for(user))

    response = api.patch("/v1/me", json={"avatarCharacterId": None}, headers=token_for(user))

    assert response.json()["avatarCharacterId"] is None


def test_deleting_the_avatar_character_resets_the_avatar(api, seed_conn) -> None:
    user = make_user(seed_conn)
    character = make_character(seed_conn, user, "내 친구")
    api.patch("/v1/me", json={"avatarCharacterId": str(character)}, headers=token_for(user))

    seed_conn.execute("delete from public.friends where id = %s", (character,))

    profile = api.get("/v1/me", headers=token_for(user)).json()
    assert profile["avatarCharacterId"] is None
    assert profile["nickname"] == "그린고블린"


def test_a_missing_profile_row_is_created_on_read(api, seed_conn) -> None:
    user = make_user(seed_conn)
    seed_conn.execute("delete from public.profiles where id = %s", (user,))

    response = api.get("/v1/me", headers=token_for(user))

    assert response.status_code == 200
    assert response.json()["nickname"] == "그린고블린"


def test_a_token_for_a_deleted_account_is_unauthenticated(api, seed_conn) -> None:
    user = make_user(seed_conn)
    seed_conn.execute("delete from auth.users where id = %s", (user,))

    for response in (
        api.get("/v1/me", headers=token_for(user)),
        api.patch("/v1/me", json={"nickname": "유령"}, headers=token_for(user)),
    ):
        assert response.status_code == 401
        assert response.json()["error"]["code"] == "unauthenticated"
