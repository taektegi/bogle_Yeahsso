"""앱의 말투 코드, AI 지침과 안전한 대체 대사를 같은 규칙으로 해석한다.

speech_catalog.json은 Flutter 카탈로그의 대화 주제만 포함한다.
테스트에서 앱 원본과 비교해 문구와 높임 구분이 달라지지 않게 한다.
"""

import json
import re
from functools import lru_cache
from pathlib import Path
from typing import Literal

SpeechStyle = Literal[
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
]


@lru_cache
def _catalog() -> dict:
    return json.loads(Path(__file__).with_name("speech_catalog.json").read_text(encoding="utf-8"))


def _profile(value: str) -> tuple[dict, bool] | None:
    manner, _, register = value.rpartition("_")
    if register not in ("casual", "polite"):
        return None
    entry = _catalog()["manners"].get(manner)
    return (entry, register == "polite") if entry else None


def speech_guidance(value: str) -> str:
    """코드를 한국어 말투 지침으로 바꾸고 기존 세 말투는 그대로 유지한다."""
    profile = _profile(value)
    if profile is None:
        return value
    entry, polite = profile
    ending = "공손한 해요체를 쓴다." if polite else "친구처럼 편한 반말을 쓴다."
    return (
        f"{entry['label']}. {entry['guidance']} {ending} "
        "위험하거나 힘든 이야기에는 과장 없이 차분하고 다정하게 반응한다."
    )


def speech_lines(value: str, topic: str) -> tuple[str, ...] | None:
    """새 말투의 주제별 대사만 반환한다. 기존 말투는 기존 스크립트를 사용한다."""
    profile = _profile(value)
    if profile is None:
        return None
    entry, polite = profile
    return tuple(pair[int(polite)] for pair in entry["lines"][topic])


def render_speech_line(template: str, *, favorite: str, name: str) -> str:
    """앱과 같이 받침에 맞는 조사를 붙인다. 입력값을 다시 템플릿으로 해석하지 않는다."""
    values = {"f": favorite, "n": name}

    def replace(match: re.Match) -> str:
        value = values[match[1]].strip()
        if match[2] is None:
            return value
        last = ord(value[-1]) if value else 0
        has_final = 0xAC00 <= last <= 0xD7A3 and (last - 0xAC00) % 28 != 0
        return value + (match[2] if has_final else match[3])

    return re.sub(r"\{([fn])(?::([^{}:/]+)/([^{}:/]+))?\}", replace, template)
