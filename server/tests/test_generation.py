"""캐릭터 생성 작업 하나: 후처리와 실패 코드 (API 계약 3.3절)."""

import httpx2
import openai
import pytest
from PIL import Image

from app import imaging
from app.ai import AiBadInput, AiRejected, AiTimeout, AiUnavailable, translate
from app.generation import GenerationFailure, make_character, prepare_page
from tests.ai_support import (
    FakeArtist,
    FakeLocator,
    FakeModerator,
    child_drawing,
    fake_ai,
    front_character,
    png,
)


def run(ai, source: bytes | None = None, timeout: float = 240, **kwargs):
    slept: list[float] = []
    result = make_character(
        source or child_drawing(),
        source_type="drawing",
        ai=ai,
        timeout=timeout,
        sleep=slept.append,
        **kwargs,
    )
    return result, slept


def failure_of(ai, source: bytes | None = None, **kwargs) -> GenerationFailure:
    with pytest.raises(GenerationFailure) as excinfo:
        run(ai, source, **kwargs)
    return excinfo.value


def test_the_result_is_a_transparent_cut_out_with_a_face_map() -> None:
    # 모델이 투명 배경 요청을 무시하고 흰 배경을 그려도
    result, _ = run(fake_ai(FakeArtist(result=png(front_character((252, 252, 248))))))

    art = imaging.open_rgba(result.art_png)
    assert imaging.has_clear_ground(art)
    assert (art.width, art.height) == (result.width, result.height)
    # 캐릭터만 남기고 여백은 일정하게 (긴 변의 4% + 2px 안팎)
    box = imaging.drawn_box(art)
    assert box is not None
    assert box[0] <= 20 and box[1] <= 20
    assert art.width - box[2] <= 20 and art.height - box[3] <= 20
    # 눈 두 개와 입이 그림 위에 있는 얼굴 지도
    face = result.face
    assert face is not None
    assert face["size"] == [art.width, art.height]
    assert len(face["eyes"]) == 2
    mx, my, _, _ = face["mouth"]
    assert imaging.alpha(art)[int(my), int(mx)] > 0
    # 썸네일과 대표색
    assert Image.open(__import__("io").BytesIO(result.thumbnail_png)).size == (256, 256)
    assert result.accent_argb >> 24 == 0xFF


def test_a_model_face_map_is_used_after_being_checked() -> None:
    locator = FakeLocator(
        answer={"size": [1, 1], "facing": "front", "eyes": [], "mouth": [0.5, 0.5, 0.1, 0.05]}
    )
    result, _ = run(fake_ai(locator=locator))

    assert result.face is not None
    assert result.face["source"] == "model"
    assert len(result.face["eyes"]) == 2  # 모델이 빼먹은 눈은 그림에서 찾아 채운다


def test_a_failing_face_model_does_not_fail_the_job() -> None:
    result, _ = run(fake_ai(locator=FakeLocator(error=AiUnavailable("down"))))

    assert result.face is not None
    assert result.face["source"] == "estimate"


@pytest.mark.parametrize(
    ("error", "code", "retryable"),
    [
        (AiRejected("moderation_blocked"), "generation_rejected", False),
        (AiBadInput("invalid_image"), "invalid_source_image", False),
    ],
)
def test_model_refusals_are_not_retried(error, code, retryable) -> None:
    artist = FakeArtist(errors=[error])

    failure = failure_of(fake_ai(artist))

    assert (failure.code, failure.retryable) == (code, retryable)
    assert artist.calls == 1


def test_temporary_model_errors_are_retried_within_the_time_limit() -> None:
    artist = FakeArtist(errors=[AiUnavailable("rate_limited"), AiTimeout("slow")])

    result, slept = run(fake_ai(artist))

    assert artist.calls == 3
    assert slept == [2.0, 5.0]
    assert result.face is not None


def test_a_model_that_stays_down_ends_as_unavailable() -> None:
    artist = FakeArtist(errors=[AiUnavailable("x"), AiUnavailable("x"), AiUnavailable("x")])

    failure = failure_of(fake_ai(artist))

    assert (failure.code, failure.retryable) == ("generation_unavailable", True)


def test_a_model_that_keeps_timing_out_ends_as_timeout() -> None:
    artist = FakeArtist(errors=[AiTimeout("slow")] * 3)

    failure = failure_of(fake_ai(artist))

    assert (failure.code, failure.retryable) == ("generation_timeout", True)


def test_no_time_left_is_a_timeout() -> None:
    ticks = iter([0.0, 300.0, 300.0, 300.0, 300.0])

    failure = failure_of(fake_ai(), clock=lambda: next(ticks))

    assert failure.code == "generation_timeout"


def test_a_blank_drawing_never_reaches_the_model() -> None:
    artist = FakeArtist()
    blank = png(Image.new("RGBA", (800, 600), (0, 0, 0, 0)))

    failure = failure_of(fake_ai(artist), blank)

    assert (failure.code, failure.retryable) == ("invalid_source_image", False)
    assert artist.calls == 0


def test_an_unreadable_source_is_invalid() -> None:
    failure = failure_of(fake_ai(), b"\x89PNG\r\n\x1a\nbroken")

    assert failure.code == "invalid_source_image"


def test_an_empty_result_means_the_model_could_not_draw_a_character() -> None:
    empty = png(Image.new("RGBA", (1024, 1024), (255, 255, 255, 255)))

    failure = failure_of(fake_ai(FakeArtist(result=empty)))

    assert (failure.code, failure.retryable) == ("generation_rejected", False)


def test_a_flagged_input_is_rejected_before_drawing() -> None:
    artist = FakeArtist()

    failure = failure_of(fake_ai(artist, moderator=FakeModerator(flag_images=True)))

    assert failure.code == "generation_rejected"
    assert artist.calls == 0


def test_a_drawing_goes_to_the_model_on_white_paper() -> None:
    page = imaging.open_rgba(prepare_page(child_drawing()))

    assert page.getpixel((0, 0))[:3] == (255, 255, 255)
    assert page.getpixel((0, 0))[3] == 255


# ---------------------------------------------------------------------------
# OpenAI 오류 → 네 가지
# ---------------------------------------------------------------------------


def _response(status: int) -> httpx2.Response:
    return httpx2.Response(status, request=httpx2.Request("POST", "https://api.openai.com/v1/x"))


def _status_error(cls, status: int, code: str | None, message: str = "x"):
    body = {"error": {"code": code, "message": message}}
    return cls(message, response=_response(status), body=body)


@pytest.mark.parametrize(
    ("exc", "kind"),
    [
        (_status_error(openai.BadRequestError, 400, "moderation_blocked"), AiRejected),
        (
            _status_error(
                openai.BadRequestError, 400, None, "Your request was rejected by the safety system"
            ),
            AiRejected,
        ),
        (_status_error(openai.BadRequestError, 400, "invalid_image_file"), AiBadInput),
        (_status_error(openai.RateLimitError, 429, "rate_limit_exceeded"), AiUnavailable),
        (_status_error(openai.RateLimitError, 429, "insufficient_quota"), AiUnavailable),
        (_status_error(openai.InternalServerError, 500, None), AiUnavailable),
        (_status_error(openai.AuthenticationError, 401, "invalid_api_key"), AiUnavailable),
        (openai.APITimeoutError(request=httpx2.Request("POST", "https://x")), AiTimeout),
        (openai.APIConnectionError(request=httpx2.Request("POST", "https://x")), AiUnavailable),
        (RuntimeError("boom"), AiUnavailable),
    ],
)
def test_openai_errors_map_to_the_four_kinds(exc, kind) -> None:
    assert isinstance(translate(exc), kind)
