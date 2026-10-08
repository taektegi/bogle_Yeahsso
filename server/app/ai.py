"""OpenAI 호출: 캐릭터 그림, 얼굴 위치, 소개 문구, 대화, 검열.

OpenAI가 실패하는 방식은 여러 가지라서, 호출하는 쪽이 사용자에게 알맞은 오류를 고를 수 있게
네 가지 예외로 나눈다 (API 계약 3.3절의 생성 실패 코드와 맞춘다).

| 예외 | 언제 | 생성 작업의 결과 |
|---|---|---|
| `AiRejected` | 안전 정책으로 거절(모델 쪽 거부) | `generation_rejected` (재시도 소용없음) |
| `AiBadInput` | 입력 이미지를 읽지 못함 | `invalid_source_image` (재시도 소용없음) |
| `AiTimeout` | 응답 시간 초과 | `generation_timeout` (재시도 가능) |
| `AiUnavailable` | 요청 과다·서버 오류·연결 실패·키 문제 | `generation_unavailable` (재시도 가능) |

OpenAI 원문 오류는 로그에만 종류를 남기고 응답에는 넣지 않는다 (NFR-09). 테스트와 키 없는 개발을
위해 모든 기능은 Protocol로 정의하고, `get_ai()` 의존성을 바꿔 끼운다.
"""

import base64
import logging
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Annotated, Any, Protocol

import openai
from fastapi import Depends
from pydantic import BaseModel, Field

from app.config import Settings, get_settings

logger = logging.getLogger(__name__)


class AiError(Exception):
    """OpenAI 호출 실패. 아래 네 가지 중 하나로 낸다."""


class AiRejected(AiError):
    pass


class AiBadInput(AiError):
    pass


class AiTimeout(AiError):
    pass


class AiUnavailable(AiError):
    pass


_REJECTED_CODES = {
    "moderation_blocked",
    "content_policy_violation",
    "content_filter",
    "safety_violation",
    "image_generation_user_error",
}
_BAD_INPUT_CODES = {
    "invalid_image",
    "invalid_image_format",
    "invalid_image_file",
    "image_parse_error",
    "unsupported_image",
    "invalid_image_size",
}


def _code_and_message(exc: Exception) -> tuple[str, str]:
    """오류 코드와 문구. SDK가 본문을 펼친 경우와 `{"error": {...}}` 그대로인 경우 모두."""
    body = getattr(exc, "body", None)
    inner = body.get("error") if isinstance(body, dict) else None
    inner = inner if isinstance(inner, dict) else {}
    code = getattr(exc, "code", None) or inner.get("code") or ""
    message = inner.get("message") or getattr(exc, "message", "") or ""
    return str(code).lower(), str(message).lower()


def translate(exc: Exception) -> AiError:
    """OpenAI SDK 예외를 네 가지 중 하나로 바꾼다."""
    if isinstance(exc, AiError):
        return exc
    if isinstance(exc, openai.APITimeoutError):
        return AiTimeout("openai timed out")
    if isinstance(exc, openai.BadRequestError | openai.UnprocessableEntityError):
        code, message = _code_and_message(exc)
        if code in _REJECTED_CODES or "safety" in message or "policy" in message:
            return AiRejected(code or "rejected")
        if code in _BAD_INPUT_CODES or ("image" in message and "invalid" in message):
            return AiBadInput(code or "bad_input")
        logger.error("openai rejected the request: code=%s", code or "-")
        return AiUnavailable(code or "bad_request")
    if isinstance(exc, openai.AuthenticationError | openai.PermissionDeniedError):
        logger.error("openai credentials are not usable: %s", type(exc).__name__)
        return AiUnavailable("credentials")
    if isinstance(exc, openai.RateLimitError):
        return AiUnavailable(_code_and_message(exc)[0] or "rate_limited")
    if isinstance(exc, openai.APIConnectionError | openai.InternalServerError):
        return AiUnavailable(type(exc).__name__)
    if isinstance(exc, openai.APIStatusError):
        return AiUnavailable(f"http_{exc.status_code}")
    return AiUnavailable(type(exc).__name__)


# ---------------------------------------------------------------------------
# 기능별 Protocol
# ---------------------------------------------------------------------------


class CharacterArtist(Protocol):
    def draw(self, page_png: bytes, *, source_type: str, timeout: float) -> bytes:
        """흰 종이 위의 아이 그림(또는 사진)으로 캐릭터 한 명의 PNG를 만든다."""
        ...


class FaceLocator(Protocol):
    def locate(self, art_png: bytes, *, width: int, height: int, timeout: float) -> dict | None:
        """캐릭터 그림을 보고 얼굴 지도 JSON을 답한다 (app/face_map.py 형식). 모르면 None."""
        ...


@dataclass(frozen=True)
class FriendBrief:
    """AI에게 주는 친구 설정. 아이의 이름이나 개인 정보는 넣지 않는다."""

    name: str
    personality: str
    favorite_things: Sequence[str]
    speech_style: str
    introduction: str = ""


@dataclass(frozen=True)
class Turn:
    role: str  # "user" | "assistant"
    text: str


class Writer(Protocol):
    def introduction(self, friend: FriendBrief, *, timeout: float) -> str: ...

    def reply(
        self, friend: FriendBrief, history: Sequence[Turn], text: str, *, timeout: float
    ) -> str: ...


class Moderator(Protocol):
    def flagged(
        self, *, text: str | None = None, image_png: bytes | None = None, timeout: float
    ) -> bool:
        """검열에 걸리면 True. 검열 자체가 실패하면 AiError."""
        ...


@dataclass(frozen=True)
class AiServices:
    artist: CharacterArtist
    locator: FaceLocator | None
    writer: Writer | None
    moderator: Moderator | None


# ---------------------------------------------------------------------------
# 프롬프트
# ---------------------------------------------------------------------------

ART_PROMPT = {
    "drawing": (
        "This is a young child's drawing on white paper. Turn it into ONE friendly character "
        "for a children's picture-book app. Keep the drawing's overall shape, colours, and the "
        "number of eyes, arms and legs, so the child recognises their own drawing."
    ),
    "photo": (
        "This is a photo of a young child's drawing on paper. Ignore the paper, lines, shadows "
        "and background, and turn the drawn figure into ONE friendly character for a children's "
        "picture-book app. Keep its overall shape, colours, and the number of eyes, arms and "
        "legs, so the child recognises their own drawing."
    ),
}
ART_STYLE = (
    " Style: flat 2D vector illustration, simple rounded shapes, smooth soft gradients, gentle "
    "pastel colours, no outlines. Give it clearly visible eyes and a mouth on its face. "
    "Composition: the whole character, standing, centred, filling about 85% of the image with "
    "an even margin all round; nothing cut off at the edges. Background: fully transparent. "
    "Nothing but the character: no ground, no cast shadow, no frame, no text, no extra objects."
)

FACE_PROMPT = """이 이미지는 아이의 그림으로 만든 캐릭터 한 명이에요
(배경 투명, 가로 {w}px × 세로 {h}px).
애니메이션과 간식 먹는 모습을 위해 얼굴 위치를 픽셀 좌표로 알려 주세요. 원점은 왼쪽 위예요.

- facing: 캐릭터 얼굴이 향하는 쪽. 옆모습이면 코·주둥이 끝이 있는 쪽("left"/"right"),
  정면이면 "front".
- head: 머리를 감싸는 상자 [x, y, 너비, 높이]. 뿔·귀·더듬이·머리카락 끝은 빼고 얼굴이 있는 부분만.
- eyes: 보이는 눈마다 [중심x, 중심y, 반지름]. 눈동자와 흰자를 합친 크기. 옆모습이면 한 개.
- mouth: 입의 [중심x, 중심y, 너비, 높이]. 입이 그려져 있지 않으면,
  이 동물이나 캐릭터의 입이 있을 자리
  (옆모습은 주둥이 끝 아래쪽). 간식이 이 자리에 닿으니 반드시 캐릭터 몸 위의 점이어야 해요.
- cheeks: 볼마다 [중심x, 중심y, 반지름]. 눈과 입 사이, 눈 아래쪽.

모르는 항목은 빈 목록으로 두고, 추측한 값도 이미지 안의 캐릭터 몸 위에 오도록 해 주세요.
size는 반드시 [{w}, {h}]로 답해 주세요."""

SPEECH_STYLE_GUIDE = {
    "~지요!": "문장을 '~지요!', '~했지요'처럼 '지요'로 끝내요.",
    "해요체": "다정한 해요체로 말해요 ('~해요', '~예요').",
    "반말": "친구에게 하듯 다정한 반말로 말해요 ('~해', '~야').",
}

INTRO_PROMPT = """아이가 그림으로 만든 캐릭터 친구의 자기소개 한두 문장을 써 주세요.
- 이름: {name}
- 성격: {personality}
- 좋아하는 것: {things}
- 말투: {style}
조건: 한국어 70자 이내, 캐릭터가 직접 말하듯이, 어디에서 온 어떤 친구인지 상상해서.
아이의 이름·나이·
사는 곳 같은 개인 정보는 쓰지 않아요. 무섭거나 슬픈 내용은 쓰지 않아요. 문장만 답해 주세요."""

CHAT_SYSTEM = """너는 아이가 그림으로 만든 캐릭터 친구 '{name}'이야. 5–9살 아이와 이야기해.
- 성격: {personality}
- 좋아하는 것: {things}
- 소개: {introduction}
- 말투: {style}
규칙: 한국어로 1–2문장, 100자 이내. 다정하고 밝게, 아이 눈높이로.
아이의 이름·주소·학교·전화번호 같은
개인 정보를 묻거나 기억하지 않아. 위험하거나 무섭거나 어른스러운 주제는 부드럽게 다른 놀이 이야기로
돌려. 너는 그림 속 친구라서 직접 만나러 가거나 물건을 사 줄 수 없어. 링크나 광고를 말하지 않아."""


def _data_url(png: bytes) -> str:
    return "data:image/png;base64," + base64.b64encode(png).decode()


class _FaceAnswer(BaseModel):
    """얼굴 위치 모델의 구조화 출력."""

    version: int = 1
    size: list[int] = Field(min_length=2, max_length=2)
    facing: str
    head: list[float] = Field(default_factory=list)
    eyes: list[list[float]] = Field(default_factory=list)
    mouth: list[float] = Field(default_factory=list)
    cheeks: list[list[float]] = Field(default_factory=list)


# ---------------------------------------------------------------------------
# OpenAI 구현
# ---------------------------------------------------------------------------


class OpenAiServices:
    """OpenAI 클라이언트 하나로 네 기능을 모두 구현한다."""

    def __init__(self, settings: Settings, client: openai.OpenAI | None = None) -> None:
        if client is None:
            key = settings.openai_api_key
            if key is None:
                raise AiUnavailable("OPENAI_API_KEY is not set")
            client = openai.OpenAI(api_key=key.get_secret_value(), max_retries=0)
        self._client = client
        self._settings = settings

    # CharacterArtist
    def draw(self, page_png: bytes, *, source_type: str, timeout: float) -> bytes:
        prompt = ART_PROMPT.get(source_type, ART_PROMPT["drawing"]) + ART_STYLE
        try:
            response = self._client.images.edit(
                model=self._settings.openai_image_model,
                image=("drawing.png", page_png, "image/png"),
                prompt=prompt,
                background="transparent",
                output_format="png",
                quality=self._settings.openai_image_quality,  # type: ignore[arg-type]
                size="1024x1024",
                n=1,
                timeout=timeout,
            )
        except Exception as exc:
            raise translate(exc) from None
        data = response.data[0].b64_json if response.data else None
        if not data:
            raise AiUnavailable("empty image response")
        return base64.b64decode(data)

    # FaceLocator
    def locate(self, art_png: bytes, *, width: int, height: int, timeout: float) -> dict | None:
        try:
            response = self._client.responses.parse(
                model=self._settings.openai_vision_model,
                input=[
                    {
                        "role": "user",
                        "content": [
                            {"type": "input_text", "text": FACE_PROMPT.format(w=width, h=height)},
                            {
                                "type": "input_image",
                                "image_url": _data_url(art_png),
                                "detail": "high",
                            },
                        ],
                    }
                ],
                text_format=_FaceAnswer,
                timeout=timeout,
            )
        except Exception as exc:
            raise translate(exc) from None
        parsed = response.output_parsed
        return parsed.model_dump() if parsed else None

    def _text(self, instructions: str, messages: list[dict[str, Any]], timeout: float) -> str:
        try:
            response = self._client.responses.create(
                model=self._settings.openai_chat_model,
                instructions=instructions,
                input=messages,
                max_output_tokens=200,
                timeout=timeout,
            )
        except Exception as exc:
            raise translate(exc) from None
        return (response.output_text or "").strip()

    # Writer
    def introduction(self, friend: FriendBrief, *, timeout: float) -> str:
        prompt = INTRO_PROMPT.format(
            name=friend.name,
            personality=friend.personality or "알려 주지 않았어요",
            things=", ".join(friend.favorite_things),
            style=SPEECH_STYLE_GUIDE.get(friend.speech_style, friend.speech_style),
        )
        return self._text(
            "너는 어린이 그림책 작가야.", [{"role": "user", "content": prompt}], timeout
        )

    def reply(
        self, friend: FriendBrief, history: Sequence[Turn], text: str, *, timeout: float
    ) -> str:
        system = CHAT_SYSTEM.format(
            name=friend.name,
            personality=friend.personality or "다정해요",
            things=", ".join(friend.favorite_things),
            introduction=friend.introduction or "아이의 그림에서 태어났어요",
            style=SPEECH_STYLE_GUIDE.get(friend.speech_style, friend.speech_style),
        )
        messages = [{"role": t.role, "content": t.text} for t in history]
        messages.append({"role": "user", "content": text})
        return self._text(system, messages, timeout)

    # Moderator
    def flagged(
        self, *, text: str | None = None, image_png: bytes | None = None, timeout: float
    ) -> bool:
        items: list[dict[str, Any]] = []
        if text:
            items.append({"type": "text", "text": text})
        if image_png:
            items.append({"type": "image_url", "image_url": {"url": _data_url(image_png)}})
        if not items:
            return False
        try:
            response = self._client.moderations.create(
                model=self._settings.openai_moderation_model, input=items, timeout=timeout
            )
        except Exception as exc:
            raise translate(exc) from None
        return any(result.flagged for result in response.results)


class PassthroughArtist:
    """OpenAI 없이: 아이 그림(흰 종이)을 그대로 돌려준다. 배경 걷기·자르기는 후처리가 한다."""

    def draw(self, page_png: bytes, *, source_type: str, timeout: float) -> bytes:
        return page_png


_clients: dict[tuple, OpenAiServices] = {}


def _openai(settings: Settings) -> OpenAiServices | None:
    """설정(키·모델)마다 클라이언트 하나를 재사용한다. 키가 없으면 None."""
    if settings.openai_api_key is None or not settings.openai_api_key.get_secret_value():
        return None
    key = (
        settings.openai_api_key.get_secret_value(),
        settings.openai_image_model,
        settings.openai_vision_model,
        settings.openai_chat_model,
    )
    if key not in _clients:
        _clients[key] = OpenAiServices(settings)
    return _clients[key]


def build_ai(settings: Settings) -> AiServices:
    """설정에 맞는 AI 기능 묶음. OpenAI 키가 없으면 그림은 passthrough만, 나머지는 None."""
    services = _openai(settings)
    if settings.generation_provider == "passthrough" or services is None:
        artist: CharacterArtist = PassthroughArtist()
        if settings.generation_provider != "passthrough":
            # 키 없이 openai로 설정하면 생성은 generation_unavailable로 끝난다.
            artist = _MissingArtist()
    else:
        artist = services
    return AiServices(artist=artist, locator=services, writer=services, moderator=services)


class _MissingArtist:
    def draw(self, page_png: bytes, *, source_type: str, timeout: float) -> bytes:
        logger.error("GENERATION_PROVIDER=openai but OPENAI_API_KEY is not set")
        raise AiUnavailable("OPENAI_API_KEY is not set")


def get_ai(settings: Annotated[Settings, Depends(get_settings)]) -> AiServices:
    return build_ai(settings)


AiDep = Annotated[AiServices, Depends(get_ai)]
