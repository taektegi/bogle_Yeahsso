"""대화의 소유권·멱등성·연쇄 삭제를 실제 PostgreSQL로 확인한다."""

from datetime import UTC, datetime

import pytest
from fastapi.testclient import TestClient

from app.ai_chat import ChatReply, get_chat_ai
from app.clock import get_now
from app.db import Database, get_database
from tests.db_support import make_character, make_user
from tests.tokens import bearer, hs256_token

AWAKE = datetime(2026, 10, 5, 3, 0, tzinfo=UTC)


class FixedChat:
    def reply(self, *, friend, history, user_text):
        return ChatReply("안전한 AI 답변이에요!", "ai")


@pytest.fixture
def api(app, client: TestClient, database: Database) -> TestClient:
    app.dependency_overrides[get_database] = lambda: database
    app.dependency_overrides[get_chat_ai] = FixedChat
    app.dependency_overrides[get_now] = lambda: AWAKE
    return client


def token_for(user_id):
    return bearer(hs256_token(sub=str(user_id)))


def send(api, user_id, character_id, key="message_key_001", text="안녕"):
    return api.post(
        f"/v1/characters/{character_id}/messages",
        json={"clientMessageId": key, "text": text},
        headers=token_for(user_id),
    )


def test_message_pair_is_saved_once_and_replayed(api, seed_conn) -> None:
    user = make_user(seed_conn)
    character = make_character(seed_conn, user, "구름이")

    first = send(api, user, character)
    second = send(api, user, character)

    assert first.status_code == second.status_code == 200
    assert first.json() == second.json()
    rows = seed_conn.execute(
        "select role from public.messages where user_id = %s and character_id = %s",
        (user, character),
    ).fetchall()
    assert sorted(row["role"] for row in rows) == ["assistant", "user"]


def test_same_key_with_different_text_conflicts(api, seed_conn) -> None:
    user = make_user(seed_conn)
    character = make_character(seed_conn, user, "구름이")
    send(api, user, character, text="첫 말")

    response = send(api, user, character, text="다른 말")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "idempotency_key_conflict"


def test_other_users_messages_are_404(api, seed_conn) -> None:
    owner, intruder = make_user(seed_conn), make_user(seed_conn)
    character = make_character(seed_conn, owner, "비밀 친구")
    send(api, owner, character)

    sent = send(api, intruder, character, key="intruder_key_01")
    listed = api.get(f"/v1/characters/{character}/messages", headers=token_for(intruder))

    assert sent.status_code == listed.status_code == 404
    assert "안녕" not in listed.text


def test_deleting_character_cascades_messages(api, seed_conn) -> None:
    user = make_user(seed_conn)
    character = make_character(seed_conn, user, "지울 친구")
    send(api, user, character)

    seed_conn.execute(
        "delete from public.friends where id = %s and user_id = %s", (character, user)
    )

    count = seed_conn.execute(
        "select count(*) as n from public.messages where character_id = %s", (character,)
    ).fetchone()["n"]
    assert count == 0
