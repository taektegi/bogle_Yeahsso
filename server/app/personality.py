"""성격 유형 목록. 서버가 관리하며, 목록 내용은 기획에서 바뀔 수 있다 (OI-01).

앱은 `GET /v1/personality-types`의 응답을 그대로 표시하고 `code`를 하드코딩하지 않는다.
이미 만든 친구의 `personality_type`은 목록이 바뀌어도 그대로 남는다.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class PersonalityType:
    code: str
    label: str


# 순서가 곧 화면 표시 순서다.
LEGACY_PERSONALITY_TYPES: tuple[PersonalityType, ...] = (
    PersonalityType("cheerful", "활발하고 씩씩해요"),
    PersonalityType("gentle", "다정하고 따뜻해요"),
    PersonalityType("curious", "호기심이 많아요"),
    PersonalityType("shy", "수줍음이 많아요"),
    PersonalityType("calm", "느긋하고 차분해요"),
    PersonalityType("playful", "장난꾸러기예요"),
)

PERSONALITY_TYPES: tuple[PersonalityType, ...] = (
    PersonalityType("cheerful_curious", "활발하고 호기심이 많아요"),
    PersonalityType("quiet_brave", "조용하지만 용감해요"),
    PersonalityType("gentle_smiling", "다정하고 잘 웃어요"),
    PersonalityType("imaginative", "엉뚱한 상상가예요"),
)

_LABELS = {item.code: item.label for item in (*LEGACY_PERSONALITY_TYPES, *PERSONALITY_TYPES)}


def personality_label(code: str) -> str:
    """목록에서 빠진 옛 코드는 코드를 그대로 돌려준다 (이미 만든 친구가 깨지지 않게)."""
    return _LABELS.get(code, code)
