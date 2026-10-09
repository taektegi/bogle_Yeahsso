"""생성된 캐릭터 PNG에서 얼굴 좌표를 읽고 검증한다.

OpenRouter 호출은 친구 생성의 부가 단계다. 호출·파싱·검증이 실패하면 호출하는 쪽은
``analyze_face_best_effort``의 ``None``을 저장하고 친구 생성은 계속한다.
"""

import base64
import json
import logging
import math
from collections.abc import Mapping
from functools import lru_cache
from io import BytesIO
from pathlib import Path
from typing import Any, Literal, Protocol

import httpx2
from PIL import Image, UnidentifiedImageError
from pydantic import ConfigDict, ValidationError, ValidationInfo, field_validator, model_validator

from app.config import Settings
from app.schemas import CamelModel

logger = logging.getLogger(__name__)

Box = tuple[float, float, float, float]
Circle = tuple[float, float, float]


class FaceMap(CamelModel):
    """Flutter의 ``.face.json`` version 1과 같은 픽셀 좌표 규격."""

    model_config = ConfigDict(
        alias_generator=CamelModel.model_config["alias_generator"],
        populate_by_name=True,
        extra="forbid",
    )

    version: Literal[1]
    size: tuple[int, int]
    facing: Literal["left", "right", "front"]
    head: Box | None
    eyes: list[Circle]
    mouth: Box | None
    cheeks: list[Circle]

    @field_validator("version", mode="before")
    @classmethod
    def _version_is_exactly_one(cls, value: Any) -> Any:
        if type(value) is not int or value != 1:
            raise ValueError("version must be the integer 1")
        return value

    @field_validator("size", mode="before")
    @classmethod
    def _valid_size(cls, value: Any) -> tuple[int, int]:
        if not isinstance(value, list) or len(value) != 2:
            raise ValueError("size must contain width and height")
        if any(type(number) is not int for number in value):
            raise ValueError("size values must be integers")
        width, height = value
        if not (1 <= width <= 8192 and 1 <= height <= 8192):
            raise ValueError("size is outside the supported range")
        return width, height

    @staticmethod
    def _numbers(value: Any, length: int, name: str) -> tuple[float, ...]:
        if not isinstance(value, list) or len(value) != length:
            raise ValueError(f"{name} has the wrong shape")
        if any(type(number) not in (int, float) for number in value):
            raise ValueError(f"{name} must contain only numbers")
        numbers = tuple(float(number) for number in value)
        if not all(math.isfinite(number) for number in numbers):
            raise ValueError(f"{name} must contain finite numbers")
        return numbers

    @field_validator("head", "mouth", mode="before")
    @classmethod
    def _valid_optional_box(cls, value: Any, info: ValidationInfo) -> Box | None:
        if value is None:
            return None
        return cls._numbers(value, 4, info.field_name)  # type: ignore[return-value]

    @field_validator("eyes", "cheeks", mode="before")
    @classmethod
    def _valid_circles(cls, value: Any, info: ValidationInfo) -> list[Circle]:
        if not isinstance(value, list) or len(value) > 2:
            raise ValueError(f"{info.field_name} must contain at most two circles")
        return [
            cls._numbers(circle, 3, info.field_name)  # type: ignore[misc]
            for circle in value
        ]

    @model_validator(mode="after")
    def _coordinates_fit_the_image(self, info: ValidationInfo) -> "FaceMap":
        width, height = self.size
        expected_size = (info.context or {}).get("expected_size")
        if expected_size is not None and tuple(expected_size) != self.size:
            raise ValueError("reported size does not match the PNG")

        def check_box(box: Box | None, name: str, *, centered: bool = False) -> None:
            if box is None:
                return
            x, y, box_width, box_height = box
            if box_width <= 0 or box_height <= 0:
                raise ValueError(f"{name} must have a positive size")
            if centered:
                x -= box_width / 2
                y -= box_height / 2
            if x < 0 or y < 0 or x + box_width > width or y + box_height > height:
                raise ValueError(f"{name} is outside the PNG")

        def check_circle(circle: Circle, name: str) -> None:
            x, y, radius = circle
            if radius <= 0 or radius > min(width, height) / 4:
                raise ValueError(f"{name} has an invalid radius")
            if x - radius < 0 or y - radius < 0 or x + radius > width or y + radius > height:
                raise ValueError(f"{name} is outside the PNG")

        check_box(self.head, "head")
        check_box(self.mouth, "mouth", centered=True)
        for circle in self.eyes:
            check_circle(circle, "eye")
        for circle in self.cheeks:
            check_circle(circle, "cheek")

        if not self.eyes and self.mouth is None:
            raise ValueError("at least an eye or mouth is required")

        if self.head is not None:
            head_x, head_y, head_width, head_height = self.head

            def in_head(x: float, y: float) -> bool:
                return head_x <= x <= head_x + head_width and head_y <= y <= head_y + head_height

            centres = [(x, y) for x, y, _ in (*self.eyes, *self.cheeks)]
            if self.mouth is not None:
                centres.append((self.mouth[0], self.mouth[1]))
            if any(not in_head(x, y) for x, y in centres):
                raise ValueError("a facial feature centre is outside the head")

            for _, _, radius in self.eyes:
                if radius > max(head_width, head_height) * 0.35:
                    raise ValueError("an eye is too large for the head")
            if self.mouth is not None:
                _, _, mouth_width, mouth_height = self.mouth
                if mouth_width > head_width or mouth_height > head_height * 0.75:
                    raise ValueError("mouth is too large for the head")

        return self


def validate_face_payload(payload: Any, *, width: int, height: int) -> FaceMap:
    """AI나 DB에서 읽은 값을 실제 PNG 크기와 대조해 검증한다."""

    return FaceMap.model_validate(payload, context={"expected_size": (width, height)})


class FaceAnalysisError(Exception):
    """외부 호출·응답 해석 실패. 이미지나 외부 응답 본문을 메시지에 담지 않는다."""


class FaceAnalyzer(Protocol):
    def analyze(
        self, image: bytes, *, width: int, height: int, content_type: str
    ) -> FaceMap | None:
        """얼굴 지도를 돌려준다. 설정상 비활성이면 ``None``."""


class DisabledFaceAnalyzer:
    def analyze(self, image: bytes, *, width: int, height: int, content_type: str) -> None:
        return None


def _png_alpha(image: bytes, *, width: int, height: int) -> Image.Image:
    """실제 PNG를 디코딩하고 투명도 채널을 읽는다. 알파가 없으면 전부 불투명하다."""

    if not (1 <= width <= 8192 and 1 <= height <= 8192):
        raise FaceAnalysisError("PNG dimensions are outside the supported range")
    try:
        with Image.open(BytesIO(image)) as png:
            if png.format != "PNG" or png.size != (width, height):
                raise FaceAnalysisError("PNG dimensions or format do not match")
            return png.convert("RGBA").getchannel("A")
    except (OSError, ValueError, UnidentifiedImageError, Image.DecompressionBombError):
        raise FaceAnalysisError("cannot decode PNG alpha channel") from None


def filter_face_by_alpha(face: FaceMap, alpha: Image.Image) -> FaceMap | None:
    """특징 중심과 주변 4점을 검사하고, 남은 좌표를 다시 검증한다."""

    def accepted(item: Circle | Box, *, mouth: bool = False) -> bool:
        x, y = item[:2]
        rx = item[2] / 4
        ry = item[3] / 4 if mouth else rx
        samples = []
        for dx, dy in ((0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)):
            px, py = round(x + dx * rx), round(y + dy * ry)
            samples.append(
                alpha.getpixel((px, py)) if 0 <= px < alpha.width and 0 <= py < alpha.height else 0
            )
        return samples[0] >= 128 and sum(value >= 128 for value in samples) >= 3

    payload = face.model_dump(mode="json", by_alias=True)
    for field in ("eyes", "cheeks"):
        payload[field] = [item for item in payload[field] if accepted(item)]
    if face.mouth is not None and not accepted(face.mouth, mouth=True):
        payload["mouth"] = None
    if not payload["eyes"] and payload["mouth"] is None:
        return None
    return validate_face_payload(payload, width=alpha.width, height=alpha.height)


@lru_cache(maxsize=1)
def _example_messages() -> tuple[dict[str, Any], ...]:
    """배포 패키지 안의 검수된 예시 6장을 읽는다."""

    directory = Path(__file__).with_name("face_examples")
    try:
        bundle = json.loads((directory / "reviewed.json").read_text(encoding="utf-8"))
        examples = bundle["examples"]
        expected_ids = ["016", "028", "dduchi", "021", "023", "029"]
        if (
            bundle["status"] != "reviewed"
            or [example["id"] for example in examples] != expected_ids
            or not all(example["reviewed"] for example in examples)
        ):
            raise ValueError
        messages = []
        for example in examples:
            image = (directory / f"{example['id']}.png").read_bytes()
            width, height = example["face"]["size"]
            _png_alpha(image, width=width, height=height)
            validated = validate_face_payload(example["face"], width=width, height=height)
            messages.extend(
                [
                    {
                        "role": "user",
                        "content": [
                            {"type": "text", "text": "얼굴 좌표를 지정된 JSON 형식으로 답하세요."},
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": "data:image/png;base64,"
                                    + base64.b64encode(image).decode("ascii"),
                                    "detail": "original",
                                },
                            },
                        ],
                    },
                    {
                        "role": "assistant",
                        "content": json.dumps(face_to_json(validated), ensure_ascii=False),
                    },
                ]
            )
        return tuple(messages)
    except (OSError, ValueError, KeyError, TypeError, FaceAnalysisError):
        raise FaceAnalysisError("cannot load reviewed face examples") from None


_FACE_SCHEMA: dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "version": {"type": "integer", "const": 1},
        "size": {
            "type": "array",
            "items": {"type": "integer"},
            "minItems": 2,
            "maxItems": 2,
        },
        "facing": {"type": "string", "enum": ["left", "right", "front"]},
        "head": {
            "anyOf": [
                {
                    "type": "array",
                    "items": {"type": "number"},
                    "minItems": 4,
                    "maxItems": 4,
                },
                {"type": "null"},
            ]
        },
        "eyes": {
            "type": "array",
            "items": {
                "type": "array",
                "items": {"type": "number"},
                "minItems": 3,
                "maxItems": 3,
            },
            "maxItems": 2,
        },
        "mouth": {
            "anyOf": [
                {
                    "type": "array",
                    "items": {"type": "number"},
                    "minItems": 4,
                    "maxItems": 4,
                },
                {"type": "null"},
            ]
        },
        "cheeks": {
            "type": "array",
            "items": {
                "type": "array",
                "items": {"type": "number"},
                "minItems": 3,
                "maxItems": 3,
            },
            "maxItems": 2,
        },
    },
    "required": ["version", "size", "facing", "head", "eyes", "mouth", "cheeks"],
}

_PROMPT = """투명 배경 캐릭터 한 명의 얼굴 애니메이션용 위치를 분석하세요.
원본 이미지 전체 크기는 가로 {width} 픽셀, 세로 {height} 픽셀입니다.
좌표 원점은 이미지 왼쪽 위이고, x는 화면 오른쪽으로, y는 화면 아래로 증가합니다.
화면에 표시된 이미지 방향을 그대로 사용하세요. 회전·좌우 반전·얼굴 부분 재배치를 하지 마세요.
내부적으로 축소해서 보더라도 최종 좌표는 반드시 원본 전체 이미지의 픽셀 좌표로 환산하세요.

동물·사람·몬스터·로봇 등 다양한 캐릭터가 입력될 수 있습니다.
먼저 실제 눈·입과 얼굴 윤곽을 찾고, 머리와 몸이 구분되는지 확인한 다음 좌표를 작성하세요.

1. head: 얼굴 영역을 둘러싸는 상자 [leftX,topY,width,height].
   머리와 몸이 구분되면 눈·코·입이 위치한 얼굴과 이를 둘러싼 머리의 주요 윤곽을 포함하세요.
   눈 주변만 작은 상자로 잡지 말고, 실제로 보이는 이마·머리 옆면·턱을 포함하세요.
   돌출된 코나 주둥이가 실제로 있으면 그 끝까지 포함하고, 없는 부위를 만들어내지 마세요.
   얼굴과 몸이 하나인 캐릭터는 몸 전체가 아니라 눈·입 등 얼굴 특징을 둘러싼 영역을 잡으세요.
   이 경우 얼굴 특징 사이의 공간과 적절한 주변 여백을 포함하되 팔·다리까지 확장하지 마세요.
   뿔·귀·더듬이·머리카락 끝 등 부속물과, 구분 가능한 목·몸통은 제외하세요.
   특히 눈 위로 뻗은 가느다란 더듬이와
   더듬이 끝의 둥근 장식을 머리나 눈으로 고르지 마세요.
   긴 목이 있는 캐릭터는 목 전체를 얼굴 상자에 포함하지 마세요.
   얼굴이 이미지 가장자리에 닿을 수 있으므로 억지로 여백을 넣지 마세요.

2. facing: 관찰자가 보는 화면을 기준으로 얼굴이 향하는 방향입니다.
   캐릭터 자신의 왼쪽·오른쪽이나 관찰자의 해부학적 방향을 뜻하지 않습니다.
   코·주둥이가 뚜렷한 옆모습에서는 다음 기준을 사용하세요.
   - 코·주둥이 끝의 x가 눈 중심 x보다 작고 얼굴이 화면 왼쪽을 향하면 left.
   - 코·주둥이 끝의 x가 눈 중심 x보다 크고 얼굴이 화면 오른쪽을 향하면 right.
   코·주둥이가 없거나 정면에 가까우면 얼굴 윤곽과 눈·입의 배치·대칭으로 판단하세요.
   얼굴 특징이 중앙에 대칭적으로 배치되고 관찰자를 향하면 front입니다.
   얼굴 윤곽과 특징 배치가 명확한 옆모습을 나타낼 때만 left 또는 right를 선택하세요.
   좌우를 구분할 근거가 부족하면 front를 사용하고, 없는 코·주둥이를 추정해 좌우를 정하지 마세요.
   예: 눈이 오른쪽에 있고 주둥이가 화면 왼쪽으로 길게 나온 옆모습은 left입니다.
   예: 눈이 왼쪽에 있고 주둥이가 화면 오른쪽으로 길게 나온 옆모습은 right입니다.
   몸·목·꼬리의 위치나 눈동자가 바라보는 방향으로 facing을 정하지 마세요.
   눈 하나만 있는 정면 캐릭터도 있으므로 눈 개수만으로 정면·옆모습이나 좌우를 결정하지 마세요.

3. eyes: 실제 보이는 눈마다 [centerX,centerY,radius], 최대 2개.
   흰자·눈 테두리·동공으로 구성된 실제 눈의 중심과 외곽 크기를 사용하세요.
   존재하지 않는 반대쪽 눈을 추가하거나 더듬이 끝·몸의 무늬를 눈으로 고르지 마세요.

4. mouth: 중심 기준 [centerX,centerY,width,height].
   이미지에 실제로 그려진 입의 선·윤곽·열린 입 모양이 명확하게 보일 때만 좌표를 반환하세요.
   입으로 보이는 형체가 없거나 입인지 판단하기 어려우면 반드시 mouth=null로 두세요.
   애니메이션용으로 입이 있을 법한 위치를 추정하거나 새로운 입 좌표를 만들지 마세요.
   코·주둥이 끝, 얼굴 외곽선, 몸의 무늬·장식, 투명한 빈 공간을 입으로 간주하지 마세요.
   예를 들어 옆모습 동물에 눈만 있고 입 선이 없으면 eyes는 반환하고 mouth는 null입니다.
   실제 입이 있는 경우에는 입 전체를 감싸는 크기를 사용하고 머리 안에 있도록 하세요.

5. cheeks: [centerX,centerY,radius], 최대 2개.
   눈 아래와 입 사이의 실제 얼굴 영역에 놓고, 더듬이·투명 배경·목에는 놓지 마세요.
   적절한 볼 위치를 판단할 수 없으면 빈 배열로 두세요.

최종 검토: head가 실제 얼굴 특징과 적절한 주요 윤곽을 포함하는지,
실제로 있는 돌출된 코·주둥이가 누락되지 않았는지, 실제 눈 중심이 head 안에 있는지,
mouth가 실제로 보이는 입을 가리키는지, 입이 없으면 null인지,
볼이 얼굴 형태에 맞게 배치됐는지, facing이 얼굴의 화면 방향과 일치하는지
다시 확인하세요. 보이지 않는 특징을 억지로 만들지 마세요.
size는 반드시 [{width}, {height}], version은 1입니다.
모든 좌표는 원본 이미지 안에 있어야 합니다. 판단할 수 없는 head와 mouth는 null,
보이지 않는 eyes와 cheeks는 빈 배열로 두고 지정된 JSON 객체만 반환하세요."""


class _HttpClient(Protocol):
    def post(self, url: str, **kwargs: Any) -> Any: ...


class OpenRouterFaceAnalyzer:
    """OpenRouter의 이미지 입력 모델에 구조화 출력으로 얼굴 좌표를 요청한다."""

    def __init__(
        self,
        *,
        api_key: str,
        model: str,
        timeout_seconds: float = 120.0,
        client: _HttpClient | None = None,
        base_url: str = "https://openrouter.ai/api/v1",
    ) -> None:
        self._api_key = api_key
        self._model = model
        self._base_url = base_url.rstrip("/")
        self._client = client or httpx2.Client(timeout=timeout_seconds)
        self.last_usage: Mapping[str, Any] | None = None

    def analyze(
        self, image: bytes, *, width: int, height: int, content_type: str
    ) -> FaceMap | None:
        if content_type != "image/png":
            raise FaceAnalysisError("face analysis requires PNG")
        self.last_usage = None
        alpha = _png_alpha(image, width=width, height=height)
        encoded = base64.b64encode(image).decode("ascii")
        payload = {
            "model": self._model,
            "messages": [
                {"role": "system", "content": _PROMPT.format(width=width, height=height)},
                *_example_messages(),
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": "위 예시의 좌표 기준을 참고해 다음 이미지의 JSON만 반환하세요.",
                        },
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/png;base64,{encoded}",
                                "detail": "original",
                            },
                        },
                    ],
                },
            ],
            "response_format": {
                "type": "json_schema",
                "json_schema": {"name": "bogle_face_map", "strict": True, "schema": _FACE_SCHEMA},
            },
            "provider": {"require_parameters": True},
            "usage": {"include": True},
            "reasoning": {"effort": "high"},
            "max_tokens": 16000,
        }
        try:
            response = self._client.post(
                f"{self._base_url}/chat/completions",
                headers={
                    "Authorization": f"Bearer {self._api_key}",
                    "Content-Type": "application/json",
                },
                json=payload,
            )
        except httpx2.HTTPError as exc:
            raise FaceAnalysisError(f"OpenRouter request failed: {type(exc).__name__}") from None
        if response.status_code != 200:
            raise FaceAnalysisError(f"OpenRouter returned HTTP {response.status_code}")
        try:
            body = response.json()
            usage = body.get("usage")
            self.last_usage = dict(usage) if isinstance(usage, Mapping) else None
            content = body["choices"][0]["message"]["content"]
            if not isinstance(content, str):
                raise TypeError
            parsed = json.loads(
                content,
                parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)),
            )
            face = validate_face_payload(parsed, width=width, height=height)
            return filter_face_by_alpha(face, alpha)
        except (KeyError, IndexError, TypeError, ValueError, json.JSONDecodeError, ValidationError):
            raise FaceAnalysisError("OpenRouter returned an invalid face map") from None


def build_face_analyzer(settings: Settings) -> FaceAnalyzer:
    """모델·키가 모두 있을 때만 외부 호출을 활성화한다."""

    if (
        settings.openrouter_api_key is None
        or not settings.openrouter_api_key.get_secret_value().strip()
        or not settings.openrouter_face_model.strip()
    ):
        return DisabledFaceAnalyzer()
    return OpenRouterFaceAnalyzer(
        api_key=settings.openrouter_api_key.get_secret_value(),
        model=settings.openrouter_face_model.strip(),
        timeout_seconds=settings.face_analysis_timeout_seconds,
    )


def analyze_face_best_effort(
    analyzer: FaceAnalyzer,
    image: bytes,
    *,
    width: int,
    height: int,
    content_type: str = "image/png",
) -> FaceMap | None:
    """얼굴 분석 실패가 친구 생성 실패로 번지지 않게 하는 생성 파이프라인 경계."""

    try:
        return analyzer.analyze(image, width=width, height=height, content_type=content_type)
    except Exception as exc:  # 외부 SDK·mock의 예상 밖 오류도 선택 기능 밖으로 전파하지 않는다.
        logger.warning("face analysis skipped after %s", type(exc).__name__)
        return None


def face_to_json(face: FaceMap | None) -> Mapping[str, Any] | None:
    return None if face is None else face.model_dump(mode="json", by_alias=True)
