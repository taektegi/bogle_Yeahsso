"""친구 초기 설정과 소개 문구. 2026-10-09 사용자 결정."""

from typing import Literal
from uuid import UUID

import regex
from pydantic import field_validator

from app.schemas import CamelModel

FAVORITE_THINGS = ("사과", "친구랑 놀기", "산책", "구름", "낮잠", "그림", "노래", "바다")
INTRODUCTIONS = (
    "너랑 친구가 되어서 기뻐! 앞으로 잘 지내보자~!",
    "우리 이제 진짜 친구다! 앞으로 잘 부탁해~",
    "드디어 만났다! 우리 재미있게 지내자~",
    "너의 새로운 친구가 되어줄게!",
    "우리 앞으로 어떤 이야기를 만들어볼까?",
    "너랑 함께할 생각에 두근두근해!",
    "안녕! 이제부터 내가 너의 친구야~",
    "우리 친구가 됐어! 같이 놀러 가볼까? 좋다",
)


class SaveFriendIn(CamelModel):
    generation_job_id: UUID
    name: str
    personality_type: Literal["cheerful_curious", "quiet_brave", "gentle_smiling", "imaginative"]
    favorite_things: list[str]
    speech_style: Literal["~지요!", "해요체", "반말"]

    @field_validator("name")
    @classmethod
    def valid_name(cls, value: str) -> str:
        value = "".join(value.split())
        if not 1 <= len(regex.findall(r"\X", value)) <= 12 or len(value) > 48:
            raise ValueError("이름은 공백을 빼고 1~12글자로 입력해 주세요.")
        return value

    @field_validator("favorite_things")
    @classmethod
    def valid_favorites(cls, values: list[str]) -> list[str]:
        if not 1 <= len(values) <= 8 or len(set(values)) != len(values):
            raise ValueError("좋아하는 것은 중복 없이 1~8개를 골라 주세요.")
        if any(value not in FAVORITE_THINGS for value in values):
            raise ValueError("목록에 있는 좋아하는 것을 골라 주세요.")
        return values
