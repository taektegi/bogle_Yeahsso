"""앱 말투 코드의 저장 계약, AI 지침과 장애 시 대체 대사의 일치를 확인한다."""

import json
from dataclasses import replace
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.ai_chat import CharacterChatProfile, ChatAiService, script_reply
from app.friend_settings import EditFriendIn, SaveFriendIn
from app.speech_styles import render_speech_line
from tests.test_creation_images import settings_payload

APP_CATALOG = json.loads(
    (Path(__file__).parents[2] / "frontend/lib/src/data/speech_catalog.json").read_text(
        encoding="utf-8"
    )
)
STYLES = (
    "~지요!",
    "해요체",
    "반말",
    "plain_casual",
    "plain_polite",
    "bouncy_casual",
    "bouncy_polite",
    "story_casual",
    "story_polite",
    "robot_casual",
    "robot_polite",
)


@pytest.mark.parametrize("style", STYLES)
def test_create_and_edit_accept_all_app_styles(style):
    assert SaveFriendIn(**settings_payload(speechStyle=style)).speech_style == style
    assert EditFriendIn(speechStyle=style).speech_style == style


@pytest.mark.parametrize("style", ["robot", "robot_rude", "unknown_polite", "존댓말", "", None])
def test_create_and_edit_reject_unknown_or_null_styles(style):
    with pytest.raises(ValidationError):
        SaveFriendIn(**settings_payload(speechStyle=style))
    with pytest.raises(ValidationError):
        EditFriendIn(speechStyle=style)


@pytest.mark.parametrize("manner", ["plain", "bouncy", "story", "robot"])
@pytest.mark.parametrize("polite", [False, True])
def test_ai_prompt_explains_the_app_manner_and_register(manner, polite):
    friend = CharacterChatProfile(
        "구름이", "imaginative", ("구름",), f"{manner}_{'polite' if polite else 'casual'}"
    )
    prompt = ChatAiService._system_prompt(friend)
    entry = APP_CATALOG["manners"][manner]
    assert entry["label"] in prompt
    assert entry["guidance"] in prompt
    assert ("공손한 해요체" if polite else "편한 반말") in prompt
    assert "차분하고 다정하게 반응한다" in prompt
    assert "개인정보를 묻지 않는다" in prompt


@pytest.mark.parametrize("style", STYLES[3:])
@pytest.mark.parametrize(
    "topic,text",
    [
        ("greet", "안녕"),
        ("today", "오늘 뭐 했어?"),
        ("likes", "뭘 좋아해?"),
        ("play", "같이 놀자!"),
        ("love", "사랑해!"),
        ("snack", "간식 먹자"),
        ("sleep", "잘 자"),
        ("other", "이야기하자"),
    ],
)
def test_fallback_uses_the_app_manner_and_register_without_template_tokens(style, topic, text):
    manner, register = style.split("_")
    friend = CharacterChatProfile("별이", "imaginative", ("구름",), style)
    answer = script_reply(friend, text)
    pairs = APP_CATALOG["manners"][manner]["lines"][topic]
    # 앱 카탈로그의 대사와 같은 높임 열을 선택해야 한다.
    expected = {
        line[register == "polite"]
        .replace("{f:이/가}", "구름이")
        .replace("{f:을/를}", "구름을")
        .replace("{f}", "구름")
        for line in pairs
    }
    assert answer in expected
    assert "{" not in answer
    assert script_reply(replace(friend), text) == answer


def test_catalog_is_packaged_and_matches_all_app_dialogue_topics():
    catalog = json.loads(
        (Path(__file__).parents[1] / "app/speech_catalog.json").read_text(encoding="utf-8")
    )
    assert catalog["version"] == APP_CATALOG["version"]
    for manner, entry in catalog["manners"].items():
        assert entry["label"] == APP_CATALOG["manners"][manner]["label"]
        assert entry["guidance"] == APP_CATALOG["manners"][manner]["guidance"]
        for topic, lines in entry["lines"].items():
            assert lines == APP_CATALOG["manners"][manner]["lines"][topic]


def test_korean_particles_and_template_values_are_not_evaluated_again():
    assert render_speech_line("{f:이/가} 좋아요", favorite="사과", name="별이") == "사과가 좋아요"
    assert render_speech_line("{f:을/를} 좋아해", favorite="구름", name="별이") == "구름을 좋아해"
    assert render_speech_line("{f}", favorite="{n}", name="별이") == "{n}"
