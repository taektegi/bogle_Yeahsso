"""아이 그림 → 친구 캐릭터 (FR-04). 작업 하나를 처리하는 순수한 부분.

순서
1. 입력 검사: 비어 있거나 단색인 그림은 모델에 보내지 않고 `invalid_source_image`.
2. 입력 검열: 걸리면 `generation_rejected` (검열 자체가 실패하면 건너뛴다. 모델도 검열한다).
3. 그림 모델: 흰 종이 위의 그림으로 캐릭터 PNG를 받는다. 일시 오류는 시간 안에서 다시 시도한다.
4. 후처리 (app/imaging.py): 남은 배경 걷기 → 떨어진 얼룩 지우기 → 캐릭터만 남게 자르고 여백 맞추기.
   캐릭터가 거의 없으면 `generation_rejected` (모델이 캐릭터를 그리지 못함).
5. 얼굴 지도 (app/face_map.py): 모델에게 묻고 그림과 대조해 고친다. 실패하면 그림만 보고 추정한다.
   얼굴 지도가 없어도 작업은 성공이다. 앱은 몸 전체 모션만 한다.
6. 썸네일·대표색.

실패는 모두 `GenerationFailure(code, retryable)`로 낸다. 코드는 API 계약 3.3절과 같다.
"""

import io
import logging
import time
from collections.abc import Callable
from dataclasses import dataclass

from PIL import Image

from app import face_map, imaging
from app.ai import AiBadInput, AiError, AiRejected, AiServices, AiTimeout, AiUnavailable

logger = logging.getLogger(__name__)

# 모델에 보낼 입력은 긴 변 1536px까지 줄인다 (요청 크기·비용)
_INPUT_MAX_SIDE = 1536
# 후처리 뒤 캐릭터가 그림에서 차지해야 하는 최소 비율
_MIN_FIGURE_COVERAGE = 0.02
# 일시 오류 재시도 간격(초). 작업 시간 안에서만 다시 시도한다.
_RETRY_DELAYS = (2.0, 5.0)


@dataclass(frozen=True)
class GenerationFailure(Exception):
    code: str
    retryable: bool

    def __str__(self) -> str:
        return self.code


def REJECTED() -> GenerationFailure:  # noqa: N802 — 상수처럼 읽히게
    return GenerationFailure("generation_rejected", retryable=False)


def INVALID_SOURCE() -> GenerationFailure:  # noqa: N802
    return GenerationFailure("invalid_source_image", retryable=False)


def TIMEOUT() -> GenerationFailure:  # noqa: N802
    return GenerationFailure("generation_timeout", retryable=True)


def UNAVAILABLE() -> GenerationFailure:  # noqa: N802
    return GenerationFailure("generation_unavailable", retryable=True)


@dataclass(frozen=True)
class GeneratedCharacter:
    art_png: bytes
    width: int
    height: int
    thumbnail_png: bytes
    accent_argb: int
    face: dict | None


def _failure(error: AiError) -> GenerationFailure:
    if isinstance(error, AiRejected):
        return REJECTED()
    if isinstance(error, AiBadInput):
        return INVALID_SOURCE()
    if isinstance(error, AiTimeout):
        return TIMEOUT()
    return UNAVAILABLE()


def prepare_page(source: bytes) -> bytes:
    """원본을 흰 종이 위의 RGB PNG로. 투명한 그림판 그림도 종이에 그린 것처럼 만든다."""
    try:
        image = imaging.open_rgba(source)
    except OSError:
        raise INVALID_SOURCE() from None
    if imaging.is_blank_drawing(image):
        raise INVALID_SOURCE()
    if imaging.has_clear_ground(image):
        # 그림판 그림: 그림 둘레만 남기고 여백을 둔다 (모델이 작은 그림을 크게 그리도록).
        image = imaging.frame_figure(image)
    page = imaging.flatten_on_white(image, padding=max(8, max(image.size) // 20))
    page.thumbnail((_INPUT_MAX_SIDE, _INPUT_MAX_SIDE), Image.Resampling.LANCZOS)
    out = io.BytesIO()
    page.save(out, format="PNG")
    return out.getvalue()


def finish_art(raw_png: bytes) -> Image.Image:
    """모델이 준 그림을 앱이 쓰는 모양으로: 투명 배경, 캐릭터 하나, 일정한 여백."""
    try:
        image = imaging.open_rgba(raw_png)
    except OSError:
        raise UNAVAILABLE() from None
    image = imaging.remove_background(image)
    image = imaging.keep_largest_figure(image)
    if imaging.coverage(image) < _MIN_FIGURE_COVERAGE * 0.5:
        raise REJECTED()
    framed = imaging.frame_figure(image)
    if imaging.coverage(framed) < _MIN_FIGURE_COVERAGE:
        raise REJECTED()
    return framed


def locate_face(art: Image.Image, ai: AiServices, timeout: float) -> dict | None:
    """얼굴 지도. 모델 답을 그림과 대조해 고치고, 모델을 못 쓰면 그림만 보고 추정한다."""
    proposed = None
    if ai.locator is not None and timeout > 3:
        try:
            answer = ai.locator.locate(
                imaging.png_bytes(art), width=art.width, height=art.height, timeout=min(timeout, 40)
            )
            proposed = face_map.parse(answer, art.width, art.height)
        except AiError as exc:
            logger.warning("face locator failed (%s); estimating from the art", type(exc).__name__)
    face = face_map.refine(proposed, art)
    return face.to_json() if face else None


def make_character(
    source: bytes,
    *,
    source_type: str,
    ai: AiServices,
    timeout: float,
    clock: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
) -> GeneratedCharacter:
    """작업 하나. `timeout`초 안에 끝내지 못하면 `generation_timeout`."""
    deadline = clock() + timeout

    def left() -> float:
        return deadline - clock()

    page = prepare_page(source)

    if ai.moderator is not None:
        try:
            if ai.moderator.flagged(image_png=page, timeout=min(15, max(1, left()))):
                raise REJECTED()
        except AiError as exc:
            logger.warning("input moderation skipped: %s", type(exc).__name__)

    raw: bytes | None = None
    for attempt in range(len(_RETRY_DELAYS) + 1):
        if left() <= 1:
            raise TIMEOUT()
        try:
            raw = ai.artist.draw(page, source_type=source_type, timeout=left())
            break
        except (AiTimeout, AiUnavailable) as exc:
            if attempt == len(_RETRY_DELAYS) or left() <= _RETRY_DELAYS[attempt] + 5:
                raise _failure(exc) from None
            logger.info("image model failed (%s); retrying", type(exc).__name__)
            sleep(_RETRY_DELAYS[attempt])
        except AiError as exc:
            raise _failure(exc) from None
    assert raw is not None

    art = finish_art(raw)
    face = locate_face(art, ai, left())
    return GeneratedCharacter(
        art_png=imaging.png_bytes(art),
        width=art.width,
        height=art.height,
        thumbnail_png=imaging.png_bytes(imaging.thumbnail(art)),
        accent_argb=imaging.accent_argb(art),
        face=face,
    )
