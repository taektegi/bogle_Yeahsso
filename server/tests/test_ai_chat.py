import json
import logging

import httpx2

from app.ai_chat import (
    CharacterChatProfile,
    ChatAiService,
    ConversationMessage,
    script_reply,
)
from app.config import Settings

FRIEND = CharacterChatProfile(
    name="구름이",
    personality_type="calm",
    favorite_things=("구름", "노래"),
    speech_style="해요체",
    introduction="하늘 산책을 좋아하는 친구예요.",
)


def moderation(flagged: bool) -> httpx2.Response:
    return httpx2.Response(
        200,
        json={"model": "omni-moderation-latest", "results": [{"flagged": flagged}]},
    )


def service(handler, **kwargs) -> ChatAiService:
    return ChatAiService(
        openrouter_api_key="openrouter-secret",
        openai_api_key="openai-secret",
        client=httpx2.Client(transport=httpx2.MockTransport(handler)),
        **kwargs,
    )


def test_ai_settings_have_safe_defaults_and_keep_keys_secret() -> None:
    settings = Settings(
        _env_file=None,
        openrouter_api_key="openrouter-secret",
        openai_api_key="openai-secret",
    )

    assert settings.openrouter_model == "openai/gpt-6-luna"
    assert settings.openai_moderation_model == "omni-moderation-latest"
    assert settings.chat_ai_timeout_seconds == 15.0
    assert str(settings.openrouter_api_key) == "**********"
    assert str(settings.openai_api_key) == "**********"


def test_safe_input_and_output_return_ai_reply_with_privacy_policy() -> None:
    requests: list[httpx2.Request] = []

    def handler(request: httpx2.Request) -> httpx2.Response:
        requests.append(request)
        if str(request.url).endswith("/moderations"):
            return moderation(False)
        return httpx2.Response(
            200,
            json={
                "model": "openai/gpt-6-luna",
                "choices": [{"message": {"role": "assistant", "content": "반가워요!"}}],
            },
        )

    history = [ConversationMessage("user", f"지난 말 {index}") for index in range(25)]
    result = service(handler).reply(friend=FRIEND, history=history, user_text="안녕!")

    assert result.text == "반가워요!"
    assert result.source == "ai"
    assert [request.url.path for request in requests] == [
        "/v1/moderations",
        "/api/v1/chat/completions",
        "/v1/moderations",
    ]
    assert requests[0].headers["authorization"] == "Bearer openai-secret"
    chat_body = json.loads(requests[1].content)
    assert requests[1].headers["authorization"] == "Bearer openrouter-secret"
    assert chat_body["model"] == "openai/gpt-6-luna"
    assert chat_body["provider"] == {"zdr": True, "data_collection": "deny"}
    assert len(chat_body["messages"]) == 22  # system + 최근 20개 + 새 사용자 입력
    assert chat_body["messages"][1]["content"] == "지난 말 5"
    assert "개인정보를 묻지 않는다" in chat_body["messages"][0]["content"]
    assert json.loads(requests[2].content)["input"] == "반가워요!"


def test_flagged_input_skips_generation_and_returns_script() -> None:
    requests: list[httpx2.Request] = []

    def handler(request: httpx2.Request) -> httpx2.Response:
        requests.append(request)
        return moderation(True)

    result = service(handler).reply(friend=FRIEND, history=(), user_text="안녕")

    assert result.source == "script"
    assert result.text
    assert len(requests) == 1


def test_flagged_output_returns_script() -> None:
    moderation_count = 0

    def handler(request: httpx2.Request) -> httpx2.Response:
        nonlocal moderation_count
        if str(request.url).endswith("/moderations"):
            moderation_count += 1
            return moderation(moderation_count == 2)
        return httpx2.Response(200, json={"choices": [{"message": {"content": "검사할 AI 답변"}}]})

    result = service(handler).reply(friend=FRIEND, history=(), user_text="오늘 뭐 했어?")

    assert result.source == "script"
    assert result.text != "검사할 AI 답변"


def test_each_external_failure_returns_script() -> None:
    def network_failure(request: httpx2.Request) -> httpx2.Response:
        raise httpx2.ReadTimeout("timeout")

    def http_failure(request: httpx2.Request) -> httpx2.Response:
        return httpx2.Response(503, json={"error": {"message": "sensitive provider response"}})

    def malformed(request: httpx2.Request) -> httpx2.Response:
        return httpx2.Response(200, json={"results": []})

    for handler in (network_failure, http_failure, malformed):
        result = service(handler).reply(friend=FRIEND, history=(), user_text="같이 놀자!")
        assert result.source == "script"
        assert result.text


def test_output_moderation_failure_returns_script() -> None:
    calls = 0

    def handler(request: httpx2.Request) -> httpx2.Response:
        nonlocal calls
        calls += 1
        if calls == 1:
            return moderation(False)
        if calls == 2:
            return httpx2.Response(200, json={"choices": [{"message": {"content": "AI 답변"}}]})
        raise httpx2.ConnectError("offline")

    result = service(handler).reply(friend=FRIEND, history=(), user_text="안녕")

    assert result.source == "script"
    assert calls == 3


def test_total_deadline_is_shared_by_all_calls() -> None:
    now = 0.0
    calls = 0

    def clock() -> float:
        return now

    def handler(request: httpx2.Request) -> httpx2.Response:
        nonlocal now, calls
        calls += 1
        now += 6.0
        if calls == 1:
            return moderation(False)
        if calls == 2:
            return httpx2.Response(200, json={"choices": [{"message": {"content": "AI 답변"}}]})
        return moderation(False)

    result = service(handler, timeout_seconds=15.0, clock=clock).reply(
        friend=FRIEND, history=(), user_text="안녕"
    )

    assert result.source == "script"
    assert calls == 3


def test_missing_credentials_never_calls_external_service() -> None:
    def handler(request: httpx2.Request) -> httpx2.Response:
        raise AssertionError("외부 서비스를 호출하면 안 됨")

    ai = ChatAiService(
        openrouter_api_key="",
        openai_api_key="",
        client=httpx2.Client(transport=httpx2.MockTransport(handler)),
    )
    assert ai.reply(friend=FRIEND, history=(), user_text="안녕").source == "script"


def test_expired_caller_deadline_never_calls_external_service() -> None:
    def handler(request: httpx2.Request) -> httpx2.Response:
        raise AssertionError("기록 조회 중 제한 시간이 끝나면 외부 호출을 하면 안 됨")

    result = service(handler, clock=lambda: 20.0).reply(
        friend=FRIEND, history=(), user_text="안녕", deadline=19.0
    )

    assert result.source == "script"


def test_logs_do_not_contain_message_key_or_provider_body(caplog) -> None:
    secret_text = "아이의 비밀 대화"
    caplog.set_level(logging.WARNING)

    def handler(request: httpx2.Request) -> httpx2.Response:
        return httpx2.Response(500, json={"message": "provider private body"})

    result = service(handler).reply(friend=FRIEND, history=(), user_text=secret_text)

    assert result.source == "script"
    logs = caplog.text
    assert secret_text not in logs
    assert "openrouter-secret" not in logs
    assert "openai-secret" not in logs
    assert "provider private body" not in logs


def test_script_reply_preserves_friend_talk_register_and_favorite() -> None:
    polite = script_reply(FRIEND, "뭘 좋아해?")
    jiyo = script_reply(CharacterChatProfile("별이", "curious", ("바다",), "~지요!"), "뭘 좋아해?")
    casual = script_reply(CharacterChatProfile("콩이", "playful", ("사과",), "반말"), "뭘 좋아해?")

    assert "요" in polite
    assert "바다" in jiyo and "지요" in jiyo
    assert "사과" in casual and "요" not in casual
