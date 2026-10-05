"""프로필 API의 입력 검증과 부분 수정 의미. DB 없이 가짜 repository로 확인한다."""

from typing import Any
from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from app.repositories.profiles import ProfileRecord, get_profile_repository
from tests.tokens import USER_ID, bearer, hs256_token

DEFAULT = ProfileRecord(
    nickname="그린고블린",
    avatar_character_id=None,
    friend_notifications=True,
    order_notifications=True,
    character_count=0,
)


class FakeProfileRepository:
    def __init__(self) -> None:
        self.updates: list[tuple[UUID, dict[str, Any]]] = []

    def get(self, user_id: UUID) -> ProfileRecord:
        return DEFAULT

    def update(self, user_id: UUID, changes: dict[str, Any]) -> ProfileRecord:
        self.updates.append((user_id, changes))
        return DEFAULT


@pytest.fixture
def repo(app) -> FakeProfileRepository:
    fake = FakeProfileRepository()
    app.dependency_overrides[get_profile_repository] = lambda: fake
    return fake


def patch(client: TestClient, body: dict[str, Any]):
    return client.patch("/v1/me", json=body, headers=bearer(hs256_token()))


def test_get_me_shape_is_camel_case(client: TestClient, repo) -> None:
    response = client.get("/v1/me", headers=bearer(hs256_token()))

    assert response.status_code == 200
    assert response.json() == {
        "nickname": "그린고블린",
        "avatarCharacterId": None,
        "friendNotifications": True,
        "orderNotifications": True,
        "characterCount": 0,
    }


def test_only_the_sent_fields_are_updated(client: TestClient, repo) -> None:
    patch(client, {"friendNotifications": False})

    assert repo.updates == [(UUID(USER_ID), {"friend_notifications": False})]


def test_user_id_comes_from_the_token(client: TestClient, repo) -> None:
    patch(client, {"nickname": "초코", "userId": "99999999-9999-4999-8999-999999999999"})

    [(user_id, changes)] = repo.updates
    assert user_id == UUID(USER_ID)
    assert changes == {"nickname": "초코"}


def test_empty_patch_changes_nothing(client: TestClient, repo) -> None:
    response = patch(client, {})

    assert response.status_code == 200
    assert repo.updates == [(UUID(USER_ID), {})]


def test_read_only_fields_cannot_be_set(client: TestClient, repo) -> None:
    patch(client, {"characterCount": 99, "avatarFriendId": "x"})

    assert repo.updates == [(UUID(USER_ID), {})]


def test_nickname_is_trimmed(client: TestClient, repo) -> None:
    patch(client, {"nickname": "  초코 우유  "})

    assert repo.updates[0][1] == {"nickname": "초코 우유"}


def test_nickname_of_exactly_12_characters_is_accepted(client: TestClient, repo) -> None:
    response = patch(client, {"nickname": "가" * 12})

    assert response.status_code == 200
    assert repo.updates[0][1] == {"nickname": "가" * 12}


@pytest.mark.parametrize(
    ("nickname", "kind"),
    [("", "string_too_short"), ("   ", "string_too_short"), ("가" * 13, "string_too_long")],
)
def test_invalid_nickname_is_a_validation_error(client: TestClient, repo, nickname, kind) -> None:
    response = patch(client, {"nickname": nickname})

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"
    assert response.json()["error"]["fieldErrors"] == {"nickname": kind}
    assert repo.updates == []


def test_whitespace_around_a_too_long_nickname_does_not_help(client: TestClient, repo) -> None:
    response = patch(client, {"nickname": "  " + "가" * 13 + "  "})

    assert response.status_code == 422
    assert response.json()["error"]["fieldErrors"] == {"nickname": "string_too_long"}


def test_avatar_can_be_reset_to_default_with_null(client: TestClient, repo) -> None:
    patch(client, {"avatarCharacterId": None})

    assert repo.updates[0][1] == {"avatar_character_id": None}


def test_avatar_is_untouched_when_it_is_not_sent(client: TestClient, repo) -> None:
    patch(client, {"nickname": "초코"})

    assert "avatar_character_id" not in repo.updates[0][1]


def test_avatar_must_be_a_uuid(client: TestClient, repo) -> None:
    response = patch(client, {"avatarCharacterId": "not-a-uuid"})

    assert response.status_code == 422
    assert list(response.json()["error"]["fieldErrors"]) == ["avatarCharacterId"]


@pytest.mark.parametrize("field", ["nickname", "friendNotifications", "orderNotifications"])
def test_null_is_rejected_for_fields_that_cannot_be_null(client: TestClient, repo, field) -> None:
    response = patch(client, {field: None})

    assert response.status_code == 422
    assert response.json()["error"]["fieldErrors"] == {field: "not_null"}
    assert repo.updates == []


def test_notification_flags_must_be_booleans(client: TestClient, repo) -> None:
    response = patch(client, {"orderNotifications": "maybe"})

    assert response.status_code == 422
    assert list(response.json()["error"]["fieldErrors"]) == ["orderNotifications"]


@pytest.mark.parametrize("method", ["get", "patch"])
def test_login_is_required(client: TestClient, method: str) -> None:
    response = getattr(client, method)("/v1/me")

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthenticated"


def test_missing_database_configuration_is_a_503(client: TestClient) -> None:
    response = client.get("/v1/me", headers=bearer(hs256_token()))

    assert response.status_code == 503
    assert response.json()["error"]["retryable"] is True
