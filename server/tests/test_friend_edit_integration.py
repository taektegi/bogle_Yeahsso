"""앱 편집 계약: 실제 DB 왕복, 소유권, 대화와 수면 설정 공유."""

from datetime import UTC, datetime

import pytest

from app.clock import get_now
from app.db import get_database
from app.repositories.messages import MessageRepository
from app.storage import get_storage
from tests.db_support import FakeStorage, make_character, make_user
from tests.tokens import bearer, hs256_token


@pytest.fixture
def owned(app, client, database, seed_conn):
    me, other = make_user(seed_conn), make_user(seed_conn)
    friend = make_character(seed_conn, me, "원래이름")
    app.dependency_overrides[get_database] = lambda: database
    app.dependency_overrides[get_storage] = FakeStorage
    return client, me, other, friend


def headers(user, offset=540):
    return {**bearer(hs256_token(sub=str(user))), "X-Bogle-Utc-Offset-Minutes": str(offset)}


def test_app_edit_round_trip_and_chat_profile(owned, database):
    client, me, _, friend = owned
    body = {
        "name": "새 이름",
        "personality": "상상 놀이를 좋아해요",
        "introduction": "함께 놀자!",
        "speechStyle": "반말",
        "bedtime": 20 * 60,
        "wakeTime": 8 * 60,
    }
    first = client.patch(f"/v1/characters/{friend}", json=body, headers=headers(me))
    assert first.status_code == 200
    for key, value in body.items():
        assert first.json()[key] == value
    # 재전송과 재조회 후에도 값·ID·검증된 이미지가 유지된다.
    again = client.patch(f"/v1/characters/{friend}", json=body, headers=headers(me))
    got = client.get(f"/v1/characters/{friend}", headers=headers(me)).json()
    assert again.json() == got == first.json()
    profile = MessageRepository(database).get_friend_profile(me, friend)
    assert profile.name == "새 이름"
    assert profile.personality_type == body["personality"]
    assert profile.speech_style == "반말"
    assert (profile.bedtime, profile.wake_time) == (1200, 480)


def test_edit_ownership_and_no_login(owned):
    client, me, other, friend = owned
    path = f"/v1/characters/{friend}"
    assert client.patch(path, json={"name": "도용"}).status_code == 401
    assert client.patch(path, json={"name": "도용"}, headers=headers(other)).status_code == 404
    assert client.get(path, headers=headers(me)).json()["name"] == "원래이름"


@pytest.mark.parametrize(
    "style",
    [
        "plain_casual",
        "plain_polite",
        "bouncy_casual",
        "bouncy_polite",
        "story_casual",
        "story_polite",
        "robot_casual",
        "robot_polite",
    ],
)
def test_new_speech_style_edit_is_kept_in_db_and_chat_profile(owned, database, style):
    client, me, other, friend = owned
    path = f"/v1/characters/{friend}"
    assert (
        client.patch(path, json={"speechStyle": style}, headers=headers(other)).status_code == 404
    )
    result = client.patch(path, json={"speechStyle": style}, headers=headers(me))
    assert result.status_code == 200
    assert result.json()["speechStyle"] == style
    assert client.get(path, headers=headers(me)).json()["speechStyle"] == style
    assert MessageRepository(database).get_friend_profile(me, friend).speech_style == style


def test_edit_counts_visible_characters_and_partial_patch_keeps_settings(owned):
    client, me, _, friend = owned
    path = f"/v1/characters/{friend}"
    intro = "☁️" * 70
    assert client.patch(path, json={"introduction": intro}, headers=headers(me)).status_code == 200
    changed = client.patch(path, json={"name": "구름 이"}, headers=headers(me)).json()
    assert changed["name"] == "구름 이"
    assert changed["introduction"] == intro
    assert changed["bedtime"] == 1260 and changed["wakeTime"] == 420


@pytest.mark.parametrize(
    "body",
    [
        {"name": " "},
        {"name": "가" * 13},
        {"name": None},
        {"personality": "가" * 31},
        {"personality": None},
        {"introduction": "가" * 71},
        {"introduction": None},
        {"speechStyle": "다정하게"},
        {"bedtime": -1},
        {"wakeTime": 1440},
        {"bedtime": True},
        {"wakeTime": None},
        {"userId": "other"},
        {"art": "untrusted"},
    ],
)
def test_edit_validation_preserves_existing(owned, body):
    client, me, _, friend = owned
    path = f"/v1/characters/{friend}"
    assert client.patch(path, json=body, headers=headers(me)).status_code == 422
    assert client.get(path, headers=headers(me)).json()["name"] == "원래이름"


def test_individual_sleep_and_device_offset_guard_chat(owned, app):
    client, me, _, friend = owned
    path = f"/v1/characters/{friend}"
    # 21:00 KST는 변경한 앱 기본값의 정확한 취침 경계다.
    app.dependency_overrides[get_now] = lambda: datetime(2026, 10, 31, 12, tzinfo=UTC)
    assert client.get(path + "/status", headers=headers(me)).json()["asleep"] is True
    message = {"clientMessageId": "sleep-boundary", "text": "안녕"}
    assert client.post(path + "/messages", json=message, headers=headers(me)).status_code == 409
    # 같은 서버 순간에 UTC 기기는 12시이므로 깨어 있다.
    assert client.get(path + "/status", headers=headers(me, 0)).json()["asleep"] is False
    # 친구 일정을 22~06으로 바꾸면 KST 21시에도 대화할 수 있다.
    assert (
        client.patch(path, json={"bedtime": 1320, "wakeTime": 360}, headers=headers(me)).status_code
        == 200
    )
    assert client.post(path + "/messages", json=message, headers=headers(me)).status_code == 200
    assert (
        client.patch(path, json={"bedtime": 0, "wakeTime": 0}, headers=headers(me)).status_code
        == 200
    )
    assert client.get(path + "/status", headers=headers(me)).json()["nextChangeAt"] is None


def test_invalid_offset_is_rejected(owned):
    client, me, _, friend = owned
    assert (
        client.get(f"/v1/characters/{friend}/status", headers=headers(me, 841)).status_code == 422
    )
