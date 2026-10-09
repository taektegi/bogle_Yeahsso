"""실제 PNG/JPEG 바이트와 AI 응답을 사용한 이미지·입력 계약 검증."""

import asyncio
import base64
import io
import json

import httpx2
import pytest
from PIL import Image, ImageDraw
from pydantic import ValidationError

from app.config import Settings
from app.friend_settings import SaveFriendIn
from app.image_provider import GenerationError, OpenRouterImages
from app.images import InvalidImage, character_image, input_reference, open_image
from app.repositories.creation import MODEL


def png(transparent=True, size=(256, 256), color=(240, 180, 200, 255)):
    image = Image.new("RGBA", size, (0, 0, 0, 0) if transparent else color)
    ImageDraw.Draw(image).ellipse((40, 30, 215, 225), fill=color)
    output = io.BytesIO()
    image.save(output, "PNG")
    return output.getvalue()


def test_result_alpha_thumbnail_accent_and_input_reference():
    data = png()
    result = character_image(data)
    assert (result.width, result.height) == (256, 256)
    assert result.accent_argb == 0xFFF0B4C8
    assert Image.open(io.BytesIO(result.thumbnail)).size == (256, 256)
    assert input_reference(data).startswith("data:image/jpeg;base64,")


@pytest.mark.parametrize("data", [b"not an image", png(False), png(size=(32, 32))])
def test_invalid_output(data):
    with pytest.raises(InvalidImage):
        character_image(data)


def test_real_jpeg_input_and_corrupted_png_rejected():
    output = io.BytesIO()
    Image.new("RGB", (1024, 768), "white").save(output, "JPEG")
    assert open_image(output.getvalue()).format == "JPEG"
    with pytest.raises(InvalidImage):
        open_image(png()[:50])


def settings_payload(**overrides):
    return {
        "generationJobId": "00000000-0000-0000-0000-000000000001",
        "name": "구 름 이",
        "personalityType": "imaginative",
        "favoriteThings": ["산책", "구름"],
        "speechStyle": "반말",
        **overrides,
    }


def test_name_uses_visible_graphemes_and_preserves_favorite_order():
    assert SaveFriendIn(**settings_payload()).name == "구름이"
    assert SaveFriendIn(**settings_payload(name="👨‍👩‍👧‍👦" * 2)).name == "👨‍👩‍👧‍👦" * 2
    with pytest.raises(ValidationError):
        SaveFriendIn(**settings_payload(name="가" * 13))


@pytest.mark.parametrize(
    "overrides",
    [
        {"personalityType": "calm"},
        {"favoriteThings": []},
        {"favoriteThings": ["사과", "사과"]},
        {"favoriteThings": ["키위"]},
        {"speechStyle": "존댓말"},
    ],
)
def test_invalid_settings(overrides):
    with pytest.raises(ValidationError):
        SaveFriendIn(**settings_payload(**overrides))


def test_provider_exact_payload_one_call_and_error_redaction():
    calls = []

    def handler(request):
        calls.append(json.loads(request.content))
        return httpx2.Response(200, json={"data": [{"b64_json": base64.b64encode(png()).decode()}]})

    provider = OpenRouterImages(
        Settings(_env_file=None, openrouter_api_key="fake-test-key"),
        transport=httpx2.MockTransport(handler),
    )
    assert asyncio.run(provider.generate("data:image/png;base64,test")) == png()
    assert len(calls) == 1
    assert calls[0]["model"] == MODEL
    assert calls[0]["quality"] == "medium"
    assert calls[0]["background"] == "transparent"
    assert calls[0]["provider"] == {"only": ["openai"], "allow_fallbacks": False}


@pytest.mark.parametrize(
    "status,body,code,retryable",
    [
        (
            400,
            {"error": {"code": "content_policy_violation", "message": "private"}},
            "generation_rejected",
            False,
        ),
        (422, {}, "invalid_source_image", False),
        (401, {}, "generation_unavailable", False),
        (
            404,
            {"error": {"code": "data_policy", "message": "No endpoints match your data policy"}},
            "generation_unavailable",
            False,
        ),
        (429, {}, "generation_unavailable", True),
        (503, {}, "generation_unavailable", True),
        (200, {"data": []}, "generation_invalid_result", True),
    ],
)
def test_provider_failure_no_auto_retry(status, body, code, retryable):
    calls = []

    def handler(request):
        calls.append(request)
        return httpx2.Response(status, json=body)

    provider = OpenRouterImages(
        Settings(_env_file=None, openrouter_api_key="fake-test-key"),
        transport=httpx2.MockTransport(handler),
    )
    with pytest.raises(GenerationError) as exc:
        asyncio.run(provider.generate("data:image/png;base64,test"))
    assert exc.value.code == code and exc.value.retryable is retryable
    assert "private" not in str(exc.value)
    assert len(calls) == 1
