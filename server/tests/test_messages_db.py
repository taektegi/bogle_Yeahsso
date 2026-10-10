"""대화의 소유권·멱등성·연쇄 삭제를 실제 PostgreSQL로 확인한다."""

from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from threading import Event

import pytest
from fastapi.testclient import TestClient

from app.ai_chat import ChatReply, get_chat_ai
from app.clock import get_now
from app.db import Database, get_database
from app.repositories.messages import MessageRepository, get_message_repository
from tests.db_support import make_character, make_user
from tests.tokens import bearer, hs256_token

AWAKE = datetime(2026, 10, 5, 3, 0, tzinfo=UTC)


class FixedChat:
    def reply(self, *, friend, history, user_text):
        return ChatReply("안전한 AI 답변이에요!", "ai")


class BlockingChat:
    def __init__(self) -> None:
        self.started = Event()
        self.release = Event()
        self.calls = 0

    def reply(self, *, friend, history, user_text):
        self.calls += 1
        self.started.set()
        if not self.release.wait(timeout=5):
            raise TimeoutError("test did not release the first chat request")
        return ChatReply("첫 요청의 AI 답변이에요!", "ai")


class ObservedMessageRepository(MessageRepository):
    def __init__(self, database: Database, chat: BlockingChat) -> None:
        super().__init__(database)
        self._chat = chat
        self.duplicate_waiting = Event()

    def get_reply(self, user_id, character_id, user_message_id):
        reply = super().get_reply(user_id, character_id, user_message_id)
        if self._chat.started.is_set() and reply is None:
            self.duplicate_waiting.set()
        return reply


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


def test_concurrent_duplicate_waits_for_first_ai_reply(api, app, database, seed_conn) -> None:
    user = make_user(seed_conn)
    character = make_character(seed_conn, user, "구름이")
    chat = BlockingChat()
    repo = ObservedMessageRepository(database, chat)
    app.dependency_overrides[get_chat_ai] = lambda: chat
    app.dependency_overrides[get_message_repository] = lambda: repo

    with ThreadPoolExecutor(max_workers=2) as executor:
        first = executor.submit(send, api, user, character)
        assert chat.started.wait(timeout=3)
        second = executor.submit(send, api, user, character)
        assert repo.duplicate_waiting.wait(timeout=3)
        chat.release.set()
        first_response = first.result(timeout=5)
        second_response = second.result(timeout=5)

    assert first_response.status_code == second_response.status_code == 200
    assert first_response.json() == second_response.json()
    assert first_response.json()["assistantMessage"]["text"] == "첫 요청의 AI 답변이에요!"
    assert chat.calls == 1
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
