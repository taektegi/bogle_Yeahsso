"""대화 API 계약을 DB 없이 확인한다."""

from datetime import UTC, datetime
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient

from app.ai_chat import CharacterChatProfile, ChatReply, ConversationMessage, get_chat_ai
from app.clock import get_now
from app.idempotency import idempotency_conflict
from app.repositories.messages import (
    MessagePage,
    MessageRecord,
    get_message_repository,
)
from tests.tokens import bearer, hs256_token

AWAKE = datetime(2026, 10, 5, 3, 0, tzinfo=UTC)  # 한국 시간 12:00
ASLEEP = datetime(2026, 10, 5, 14, 0, tzinfo=UTC)  # 한국 시간 23:00
CHARACTER_ID = uuid4()


class FakeChat:
    def __init__(self) -> None:
        self.calls: list[tuple[CharacterChatProfile, list[ConversationMessage], str]] = []

    def reply(self, *, friend, history, user_text) -> ChatReply:
        self.calls.append((friend, list(history), user_text))
        return ChatReply("구름을 보며 놀았어요!", "ai")


class FakeRepository:
    def __init__(self, *, owns: bool = True) -> None:
        self.profile = (
            CharacterChatProfile("구름이", "calm", ("구름",), "해요체", "안녕!") if owns else None
        )
        self.users: dict[str, tuple[str, MessageRecord]] = {}
        self.replies: dict[UUID, MessageRecord] = {}
        self.history = [ConversationMessage("user", "어제 안녕이라고 했어")]
        self.items: list[MessageRecord] = []

    def get_friend_profile(self, user_id, character_id):
        return self.profile

    def start_user_message(self, user_id, character_id, client_message_id, text):
        if self.profile is None:
            return None
        existing = self.users.get(client_message_id)
        if existing:
            old_text, message = existing
            if old_text != text:
                raise idempotency_conflict()
            return message, False
        message = MessageRecord(uuid4(), "user", text, None, AWAKE)
        self.users[client_message_id] = (text, message)
        return message, True

    def get_user_message_by_client_id(self, user_id, character_id, client_message_id, text):
        existing = self.users.get(client_message_id)
        if not existing:
            return None
        old_text, message = existing
        if old_text != text:
            raise idempotency_conflict()
        return message

    def get_reply(self, user_id, character_id, user_message_id):
        return self.replies.get(user_message_id)

    def save_reply(self, user_id, character_id, user_message_id, text, source):
        return self.replies.setdefault(
            user_message_id,
            MessageRecord(uuid4(), "assistant", text, source, AWAKE),
        )

    def recent_context(self, user_id, character_id, before, limit=20):
        return self.history[-limit:]

    def list_messages(
        self,
        user_id,
        character_id,
        *,
        limit,
        before_created_at=None,
        before_id=None,
    ):
        if self.profile is None:
            return None
        return MessagePage(self.items[:limit], len(self.items) > limit)


@pytest.fixture
def chat() -> FakeChat:
    return FakeChat()


def use(app, repo: FakeRepository, chat: FakeChat, now: datetime = AWAKE) -> None:
    app.dependency_overrides[get_message_repository] = lambda: repo
    app.dependency_overrides[get_chat_ai] = lambda: chat
    app.dependency_overrides[get_now] = lambda: now


def post(client: TestClient, text: str = "오늘 뭐 했어?", key: str = "message_key_001"):
    return client.post(
        f"/v1/characters/{CHARACTER_ID}/messages",
        json={"clientMessageId": key, "text": text},
        headers=bearer(hs256_token()),
    )


def test_send_message_saves_user_and_ai_reply(app, client: TestClient, chat: FakeChat) -> None:
    repo = FakeRepository()
    use(app, repo, chat)

    response = post(client, "  오늘 뭐 했어?  ")

    assert response.status_code == 200
    body = response.json()
    assert body["userMessage"]["text"] == "오늘 뭐 했어?"
    assert body["userMessage"]["role"] == "user"
    assert "source" not in body["userMessage"]
    assert body["assistantMessage"]["text"] == "구름을 보며 놀았어요!"
    assert body["assistantMessage"]["source"] == "ai"
    assert chat.calls[0][1] == repo.history


def test_same_client_message_id_returns_same_pair_once(
    app, client: TestClient, chat: FakeChat
) -> None:
    repo = FakeRepository()
    use(app, repo, chat)

    first = post(client)
    second = post(client)

    assert second.status_code == 200
    assert second.json() == first.json()
    assert len(repo.users) == len(repo.replies) == len(chat.calls) == 1


def test_same_client_message_id_with_different_text_is_409(
    app, client: TestClient, chat: FakeChat
) -> None:
    use(app, FakeRepository(), chat)
    post(client, "첫 번째")

    response = post(client, "다른 내용")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "idempotency_key_conflict"


def test_other_users_character_is_404(app, client: TestClient, chat: FakeChat) -> None:
    use(app, FakeRepository(owns=False), chat)

    response = post(client)

    assert response.status_code == 404
    assert chat.calls == []


def test_sleeping_character_rejects_a_new_message(app, client: TestClient, chat: FakeChat) -> None:
    repo = FakeRepository()
    use(app, repo, chat, ASLEEP)

    response = post(client)

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "character_asleep"
    assert repo.users == {}


def test_retry_returns_the_saved_pair_even_after_bedtime(
    app, client: TestClient, chat: FakeChat
) -> None:
    repo = FakeRepository()
    use(app, repo, chat)
    first = post(client)
    app.dependency_overrides[get_now] = lambda: ASLEEP

    second = post(client)

    assert second.status_code == 200
    assert second.json() == first.json()


@pytest.mark.parametrize("text", ["", "   ", "가" * 201])
def test_text_must_be_1_to_200_trimmed_characters(app, client, chat, text) -> None:
    use(app, FakeRepository(), chat)

    response = post(client, text)

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


def test_list_is_newest_first_and_has_a_cursor(app, client: TestClient, chat: FakeChat) -> None:
    repo = FakeRepository()
    repo.items = [
        MessageRecord(uuid4(), "assistant", "최신 답", "script", AWAKE),
        MessageRecord(uuid4(), "user", "이전 질문", None, AWAKE),
    ]
    use(app, repo, chat)

    response = client.get(
        f"/v1/characters/{CHARACTER_ID}/messages?limit=1",
        headers=bearer(hs256_token()),
    )

    assert response.status_code == 200
    assert [item["text"] for item in response.json()["items"]] == ["최신 답"]
    assert response.json()["nextCursor"] is not None


def test_list_last_page_returns_null_cursor(app, client: TestClient, chat: FakeChat) -> None:
    repo = FakeRepository()
    repo.items = [MessageRecord(uuid4(), "assistant", "마지막 답", "script", AWAKE)]
    use(app, repo, chat)

    response = client.get(
        f"/v1/characters/{CHARACTER_ID}/messages",
        headers=bearer(hs256_token()),
    )

    assert response.status_code == 200
    assert response.json()["nextCursor"] is None


def test_invalid_history_cursor_is_422(app, client: TestClient, chat: FakeChat) -> None:
    use(app, FakeRepository(), chat)

    response = client.get(
        f"/v1/characters/{CHARACTER_ID}/messages?before=not-a-cursor",
        headers=bearer(hs256_token()),
    )

    assert response.status_code == 422
    assert response.json()["error"]["fieldErrors"] == {"before": "invalid_cursor"}


def test_openapi_documents_message_endpoints(client: TestClient) -> None:
    path = client.get("/openapi.json").json()["paths"]["/v1/characters/{character_id}/messages"]
    assert set(path) == {"get", "post"}
