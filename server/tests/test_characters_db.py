"""보관함 API를 실제 PostgreSQL(마이그레이션 적용)로 확인한다.

핵심은 소유권 차단이다: 다른 사용자의 친구는 목록에도 상세에도 나오지 않는다 (FR-01.4).
TEST_DATABASE_URL이 없으면 이 파일의 테스트는 건너뛴다.
"""

from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.db import Database, get_database
from app.repositories.characters import CharacterRepository
from app.storage import get_storage
from tests.db_support import FakeStorage, make_character, make_user
from tests.tokens import bearer, hs256_token


@pytest.fixture
def storage() -> FakeStorage:
    return FakeStorage()


@pytest.fixture
def api(app, client: TestClient, database: Database, storage: FakeStorage) -> TestClient:
    app.dependency_overrides[get_database] = lambda: database
    app.dependency_overrides[get_storage] = lambda: storage
    return client


def token_for(user_id) -> dict[str, str]:
    return bearer(hs256_token(sub=str(user_id)))


def test_list_contains_only_my_characters_newest_first(api, seed_conn) -> None:
    me, other = make_user(seed_conn), make_user(seed_conn)
    make_character(seed_conn, me, "가장 오래된", created_at="2026-10-01T00:00:00Z")
    make_character(seed_conn, me, "가장 최근", created_at="2026-10-03T00:00:00Z")
    make_character(seed_conn, me, "중간", created_at="2026-10-02T00:00:00Z")
    make_character(seed_conn, other, "남의 친구", created_at="2026-10-04T00:00:00Z")

    response = api.get("/v1/characters", headers=token_for(me))

    assert response.status_code == 200
    assert [c["name"] for c in response.json()["items"]] == ["가장 최근", "중간", "가장 오래된"]


def test_each_user_sees_only_their_own_list(api, seed_conn) -> None:
    a, b = make_user(seed_conn), make_user(seed_conn)
    make_character(seed_conn, a, "A의 친구")
    make_character(seed_conn, b, "B의 친구 1")
    make_character(seed_conn, b, "B의 친구 2")

    names_a = [c["name"] for c in api.get("/v1/characters", headers=token_for(a)).json()["items"]]
    names_b = [c["name"] for c in api.get("/v1/characters", headers=token_for(b)).json()["items"]]

    assert names_a == ["A의 친구"]
    assert sorted(names_b) == ["B의 친구 1", "B의 친구 2"]


def test_new_user_gets_an_empty_list(api, seed_conn) -> None:
    user = make_user(seed_conn)

    response = api.get("/v1/characters", headers=token_for(user))

    assert response.status_code == 200
    assert response.json() == {"items": [], "nextCursor": None}


def test_other_users_character_detail_is_404(api, seed_conn) -> None:
    owner, intruder = make_user(seed_conn), make_user(seed_conn)
    character_id = make_character(seed_conn, owner, "비밀 친구")

    own = api.get(f"/v1/characters/{character_id}", headers=token_for(owner))
    stolen = api.get(f"/v1/characters/{character_id}", headers=token_for(intruder))
    missing = api.get(f"/v1/characters/{uuid4()}", headers=token_for(intruder))

    assert own.status_code == 200
    assert own.json()["name"] == "비밀 친구"
    assert stolen.status_code == 404
    # 남의 친구와 없는 친구는 응답이 구분되지 않는다 (requestId만 다르다).
    assert stolen.json()["error"]["code"] == missing.json()["error"]["code"] == "not_found"
    assert stolen.json()["error"]["message"] == missing.json()["error"]["message"]
    assert "비밀 친구" not in stolen.text


def test_other_users_asset_urls_are_never_signed(api, seed_conn, storage) -> None:
    me, other = make_user(seed_conn), make_user(seed_conn)
    make_character(seed_conn, me, "내 친구")
    make_character(seed_conn, other, "남의 친구")

    api.get("/v1/characters", headers=token_for(me))

    [paths] = storage.calls
    assert len(paths) == 3
    assert all(p.startswith(f"{me}/") for p in paths)


def test_timestamps_are_utc_even_if_the_db_session_is_not(api, seed_conn) -> None:
    user = make_user(seed_conn)
    # 한국 시간 14:00 == 05:00 UTC. 테스트 풀의 DB 세션 시간대는 Asia/Seoul이다.
    make_character(seed_conn, user, "시간 확인", created_at="2026-10-05T14:00:00+09:00")

    [character] = api.get("/v1/characters", headers=token_for(user)).json()["items"]

    assert character["createdAt"] == "2026-10-05T05:00:00Z"


def test_same_timestamp_keeps_a_stable_order(api, seed_conn) -> None:
    user = make_user(seed_conn)
    ids = [
        make_character(seed_conn, user, f"동시 {i}", created_at="2026-10-05T00:00:00Z")
        for i in range(3)
    ]

    first = [c["id"] for c in api.get("/v1/characters", headers=token_for(user)).json()["items"]]
    second = [c["id"] for c in api.get("/v1/characters", headers=token_for(user)).json()["items"]]

    assert first == second == [str(i) for i in sorted(ids, reverse=True)]


def test_character_without_source_is_listed_with_null_source(api, seed_conn) -> None:
    user = make_user(seed_conn)
    make_character(seed_conn, user, "원본 없음", with_source=False)

    [character] = api.get("/v1/characters", headers=token_for(user)).json()["items"]

    assert character["source"] is None
    assert character["art"]["contentType"] == "image/png"


def test_response_carries_the_stored_values(api, seed_conn) -> None:
    user = make_user(seed_conn)
    character_id = make_character(seed_conn, user, "뭉글이", personality_type="gentle")

    character = api.get(f"/v1/characters/{character_id}", headers=token_for(user)).json()

    assert character["id"] == str(character_id)
    assert character["personalityType"] == "gentle"
    assert character["personalityLabel"] == "다정하고 따뜻해요"
    assert character["favoriteThings"] == ["사과", "산책"]
    assert character["speechStyle"] == "해요체"
    assert character["introduction"] == "뭉글이의 소개"
    assert character["accentArgb"] == 4289974783  # 부호 없는 32비트 값이 그대로 나온다
    assert character["art"]["width"] == 640
    assert character["face"] is None


def test_response_carries_a_valid_face_map(api, seed_conn) -> None:
    user = make_user(seed_conn)
    face = {
        "version": 1,
        "size": [640, 480],
        "facing": "front",
        "head": [160, 60, 320, 300],
        "eyes": [[250, 160, 24], [390, 160, 24]],
        "mouth": [320, 260, 90, 36],
        "cheeks": [[225, 225, 28], [415, 225, 28]],
    }
    character_id = make_character(seed_conn, user, "얼굴 친구", face=face)

    character = api.get(f"/v1/characters/{character_id}", headers=token_for(user)).json()

    assert character["face"] == face


def test_invalid_stored_face_is_omitted_without_hiding_the_character(api, seed_conn) -> None:
    user = make_user(seed_conn)
    invalid_face = {
        "version": 1,
        "size": [641, 480],
        "facing": "front",
        "head": [160, 60, 320, 300],
        "eyes": [[250, 160, 24]],
        "mouth": [320, 260, 90, 36],
        "cheeks": [],
    }
    character_id = make_character(seed_conn, user, "좌표 오류", face=invalid_face)

    response = api.get(f"/v1/characters/{character_id}", headers=token_for(user))

    assert response.status_code == 200
    assert response.json()["face"] is None


def test_repository_filters_by_owner_in_sql(database: Database, seed_conn) -> None:
    a, b = make_user(seed_conn), make_user(seed_conn)
    a_character = make_character(seed_conn, a, "A")
    repo = CharacterRepository(database)

    assert [r.name for r in repo.list_for_user(a)] == ["A"]
    assert repo.list_for_user(b) == []
    assert repo.get_for_user(a, a_character) is not None
    assert repo.get_for_user(b, a_character) is None


def test_status_of_another_users_character_is_404(api, seed_conn) -> None:
    owner, intruder = make_user(seed_conn), make_user(seed_conn)
    character_id = make_character(seed_conn, owner, "자는 친구")

    own = api.get(f"/v1/characters/{character_id}/status", headers=token_for(owner))
    stolen = api.get(f"/v1/characters/{character_id}/status", headers=token_for(intruder))

    assert own.status_code == 200
    assert set(own.json()) == {"asleep", "nextChangeAt", "serverTime"}
    assert stolen.status_code == 404


def asset_count(conn, user_id) -> int:
    return conn.execute(
        "select count(*) as n from public.assets where user_id = %s", (user_id,)
    ).fetchone()["n"]


def character_exists(conn, character_id) -> bool:
    return (
        conn.execute("select 1 from public.friends where id = %s", (character_id,)).fetchone()
        is not None
    )


def test_delete_removes_the_character_files_and_asset_rows(api, seed_conn, storage) -> None:
    user = make_user(seed_conn)
    character_id = make_character(seed_conn, user, "지울 친구")
    paths = [
        r["storage_path"]
        for r in seed_conn.execute(
            "select storage_path from public.assets where user_id = %s", (user,)
        ).fetchall()
    ]

    response = api.delete(f"/v1/characters/{character_id}", headers=token_for(user))

    assert response.status_code == 204
    assert response.content == b""
    assert not character_exists(seed_conn, character_id)
    assert asset_count(seed_conn, user) == 0
    [removed] = storage.removed
    assert sorted(removed) == sorted(paths)
    assert api.get(f"/v1/characters/{character_id}", headers=token_for(user)).status_code == 404
    assert api.get("/v1/characters", headers=token_for(user)).json()["items"] == []


def test_files_are_removed_after_the_character_row_is_gone(api, seed_conn, storage) -> None:
    user = make_user(seed_conn)
    character_id = make_character(seed_conn, user, "순서 확인")
    seen: list[bool] = []
    storage.on_remove = lambda: seen.append(character_exists(seed_conn, character_id))

    api.delete(f"/v1/characters/{character_id}", headers=token_for(user))

    assert seen == [False]


def test_delete_without_a_source_asset(api, seed_conn, storage) -> None:
    user = make_user(seed_conn)
    character_id = make_character(seed_conn, user, "원본 없음", with_source=False)

    response = api.delete(f"/v1/characters/{character_id}", headers=token_for(user))

    assert response.status_code == 204
    assert len(storage.removed[0]) == 2
    assert asset_count(seed_conn, user) == 0


def test_delete_of_another_users_character_is_404_and_changes_nothing(
    api, seed_conn, storage
) -> None:
    owner, intruder = make_user(seed_conn), make_user(seed_conn)
    character_id = make_character(seed_conn, owner, "지키는 친구")

    response = api.delete(f"/v1/characters/{character_id}", headers=token_for(intruder))

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "not_found"
    assert character_exists(seed_conn, character_id)
    assert asset_count(seed_conn, owner) == 3
    assert storage.removed == []


def test_delete_of_an_unknown_character_is_404(api, seed_conn, storage) -> None:
    user = make_user(seed_conn)

    response = api.delete(f"/v1/characters/{uuid4()}", headers=token_for(user))

    assert response.status_code == 404
    assert storage.removed == []


def test_deleting_twice_is_404_the_second_time(api, seed_conn, storage) -> None:
    user = make_user(seed_conn)
    character_id = make_character(seed_conn, user, "한 번만")

    first = api.delete(f"/v1/characters/{character_id}", headers=token_for(user))
    second = api.delete(f"/v1/characters/{character_id}", headers=token_for(user))

    assert (first.status_code, second.status_code) == (204, 404)
    assert len(storage.removed) == 1


def test_delete_leaves_other_characters_and_users_alone(api, seed_conn, storage) -> None:
    me, other = make_user(seed_conn), make_user(seed_conn)
    doomed = make_character(seed_conn, me, "지울 친구")
    sibling = make_character(seed_conn, me, "남는 친구")
    others = make_character(seed_conn, other, "남의 친구")

    api.delete(f"/v1/characters/{doomed}", headers=token_for(me))

    assert character_exists(seed_conn, sibling)
    assert character_exists(seed_conn, others)
    assert asset_count(seed_conn, me) == 3
    assert asset_count(seed_conn, other) == 3
    assert [c["id"] for c in api.get("/v1/characters", headers=token_for(me)).json()["items"]] == [
        str(sibling)
    ]


def test_storage_failure_still_deletes_the_character_and_keeps_rows_for_cleanup(
    app, api, seed_conn
) -> None:
    user = make_user(seed_conn)
    character_id = make_character(seed_conn, user, "파일 삭제 실패")
    app.dependency_overrides[get_storage] = lambda: FakeStorage(fail_remove=True)

    response = api.delete(f"/v1/characters/{character_id}", headers=token_for(user))

    assert response.status_code == 204
    assert not character_exists(seed_conn, character_id)
    # 파일 삭제가 실패했으므로 경로를 알 수 있게 에셋 행이 남아 있다 (나중에 정리).
    assert asset_count(seed_conn, user) == 3
    assert api.get("/v1/characters", headers=token_for(user)).json()["items"] == []


def test_deleting_the_avatar_character_resets_the_avatar(api, seed_conn) -> None:
    user = make_user(seed_conn)
    character_id = make_character(seed_conn, user, "아바타 친구")
    api.patch("/v1/me", json={"avatarCharacterId": str(character_id)}, headers=token_for(user))

    api.delete(f"/v1/characters/{character_id}", headers=token_for(user))

    assert api.get("/v1/me", headers=token_for(user)).json()["avatarCharacterId"] is None


def test_delete_requires_login(client: TestClient) -> None:
    assert client.delete(f"/v1/characters/{uuid4()}").status_code == 401
