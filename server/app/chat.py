"""친구의 집 대화: 친구의 답 만들기 (FR-09).

1. 아이의 말을 검열한다. 걸리면 AI에 보내지 않고 스크립트 대사로 답한다.
2. AI(app/ai.py)가 친구 설정과 최근 대화 20개를 보고 답한다 (15초 한도).
3. 답도 검열한다. 걸리거나, AI가 실패·시간 초과·빈 답이면 스크립트 대사로 답한다.

어느 경우든 오류가 아니라 정상 답이다 (`source`만 `ai`/`script`로 다르다). 스크립트 대사는 앱의
friend_talk.dart와 같은 결로, 친구의 말투(~지요!·해요체·반말)에 맞춰 고른다.
"""

import logging
import random
from collections.abc import Sequence
from dataclasses import dataclass

from app.ai import AiError, AiServices, FriendBrief, Turn

logger = logging.getLogger(__name__)

AI_TIMEOUT_SECONDS = 15
MODERATION_TIMEOUT_SECONDS = 5
MAX_REPLY_CHARS = 100


@dataclass(frozen=True)
class Reply:
    text: str
    source: str  # ai | script


# (반말, 해요체, ~지요!) — {f}는 좋아하는 것
_LINES: dict[str, list[tuple[str, str, str]]] = {
    "greet": [
        ("안녕! 와 줘서 기뻐", "안녕하세요! 와 줘서 기뻐요", "안녕! 와 줘서 정말 기쁘지요"),
    ],
    "today": [
        ("오늘은 창밖 구름을 세었어", "오늘은 창밖 구름을 세었어요", "오늘은 창밖 구름을 세었지요"),
        (
            "{f} 생각을 하면서 방을 정리했어",
            "{f} 생각을 하면서 방을 정리했어요",
            "{f} 생각을 하면서 방을 정리했지요",
        ),
    ],
    "likes": [
        ("{f}, 그게 제일 좋아", "{f}, 그게 제일 좋아요", "{f}, 그게 제일 좋지요"),
    ],
    "play": [
        ("좋아! 숨바꼭질 하자", "좋아요! 숨바꼭질 해요", "좋지요! 숨바꼭질 하지요"),
    ],
    "love": [
        ("나도 네가 정말 좋아", "나도 네가 정말 좋아요", "나도 네가 정말 좋지요"),
    ],
    "other": [
        ("우와, 그런 생각을 했구나", "우와, 그런 생각을 했군요", "우와, 멋진 생각이지요"),
        ("그 이야기 더 해 줘", "그 이야기 더 해 주세요", "그 이야기 더 듣고 싶지요"),
        ("너랑 이야기하면 즐거워", "같이 이야기하면 즐거워요", "너랑 이야기하면 즐겁지요"),
    ],
}

_TOPICS = [
    ("greet", ("안녕", "하이", "반가")),
    ("today", ("오늘", "뭐 했", "뭐했")),
    ("likes", ("좋아하", "좋아해", "취미")),
    ("play", ("놀자", "놀아", "게임", "숨바꼭질")),
    ("love", ("사랑", "좋아!", "최고", "예뻐", "귀여워")),
]


def script_reply(friend: FriendBrief, text: str, rng: random.Random | None = None) -> str:
    rng = rng or random.Random()
    topic = next((t for t, words in _TOPICS if any(w in text for w in words)), "other")
    line = rng.choice(_LINES[topic])
    style = friend.speech_style
    chosen = line[2] if "지요" in style else line[1] if "해요" in style else line[0]
    favorite = rng.choice(list(friend.favorite_things)) if friend.favorite_things else "반짝이는 것"
    return chosen.replace("{f}", favorite) + "!"


def _flagged(ai: AiServices, text: str) -> bool:
    if ai.moderator is None:
        return False
    try:
        return ai.moderator.flagged(text=text, timeout=MODERATION_TIMEOUT_SECONDS)
    except AiError as exc:
        # 검열을 못 하면 안전하게 스크립트로 답한다.
        logger.warning("chat moderation failed: %s", type(exc).__name__)
        return True


def compose_reply(
    ai: AiServices,
    friend: FriendBrief,
    history: Sequence[Turn],
    text: str,
    rng: random.Random | None = None,
) -> Reply:
    if ai.writer is None or _flagged(ai, text):
        return Reply(script_reply(friend, text, rng), "script")
    try:
        answer = ai.writer.reply(friend, history, text, timeout=AI_TIMEOUT_SECONDS).strip()
    except AiError as exc:
        logger.warning("chat model failed: %s", type(exc).__name__)
        return Reply(script_reply(friend, text, rng), "script")
    if not answer or _flagged(ai, answer):
        return Reply(script_reply(friend, text, rng), "script")
    if len(answer) > MAX_REPLY_CHARS:
        cut = max(answer.rfind(mark, 0, MAX_REPLY_CHARS) for mark in ".!?~")
        answer = answer[: cut + 1] if cut > 20 else answer[:MAX_REPLY_CHARS]
    return Reply(answer, "ai")
