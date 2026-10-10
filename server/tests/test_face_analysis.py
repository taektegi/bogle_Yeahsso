import json
from io import BytesIO
from pathlib import Path

import pytest
from PIL import Image
from pydantic import SecretStr, ValidationError

from app.config import Settings
from app.face_analysis import (
    DisabledFaceAnalyzer,
    FaceAnalysisError,
    OpenRouterFaceAnalyzer,
    analyze_face_best_effort,
    build_face_analyzer,
    face_to_json,
    filter_face_by_alpha,
    validate_face_payload,
)


def png_bytes(*, opaque: bool = True) -> bytes:
    image = Image.new("RGBA", (640, 480), (255, 255, 255, 255 if opaque else 0))
    stream = BytesIO()
    image.save(stream, format="PNG")
    return stream.getvalue()


def valid_face() -> dict:
    return {
        "version": 1,
        "size": [640, 480],
        "facing": "front",
        "head": [160, 60, 320, 300],
        "eyes": [[250, 160, 24], [390, 160, 24]],
        "mouth": [320, 260, 90, 36],
        "cheeks": [[225, 225, 28], [415, 225, 28]],
    }


class Response:
    def __init__(self, body: dict, status_code: int = 200) -> None:
        self.body = body
        self.status_code = status_code

    def json(self) -> dict:
        return self.body


class Client:
    def __init__(self, response: Response) -> None:
        self.response = response
        self.calls: list[tuple[str, dict]] = []

    def post(self, url: str, **kwargs):
        self.calls.append((url, kwargs))
        return self.response


def analyzer_for(face: dict, *, status_code: int = 200) -> tuple[OpenRouterFaceAnalyzer, Client]:
    client = Client(
        Response(
            {
                "choices": [{"message": {"content": json.dumps(face)}}],
                "usage": {
                    "prompt_tokens": 100,
                    "completion_tokens": 50,
                    "total_tokens": 150,
                    "cost": 0.00012,
                },
            },
            status_code=status_code,
        )
    )
    return (
        OpenRouterFaceAnalyzer(api_key="secret", model="provider/vision", client=client),
        client,
    )


def test_openrouter_request_uses_image_and_strict_schema() -> None:
    analyzer, client = analyzer_for(valid_face())

    face = analyzer.analyze(png_bytes(), width=640, height=480, content_type="image/png")

    assert face_to_json(face) == valid_face()
    [(url, call)] = client.calls
    assert url == "https://openrouter.ai/api/v1/chat/completions"
    assert call["headers"]["Authorization"] == "Bearer secret"
    assert call["json"]["model"] == "provider/vision"
    assert call["json"]["provider"] == {"require_parameters": True}
    assert call["json"]["usage"] == {"include": True}
    assert call["json"]["response_format"]["json_schema"]["strict"] is True
    messages = call["json"]["messages"]
    assert len(messages) == 14
    assert messages[0]["role"] == "system"
    expected_ids = ["016", "028", "dduchi", "021", "023", "029"]
    for index, _ in enumerate(expected_ids):
        assert messages[1 + 2 * index]["role"] == "user"
        example = json.loads(messages[2 + 2 * index]["content"])
        assert example["cheeks"]
    assert json.loads(messages[12]["content"])["facing"] == "left"
    image_url = messages[-1]["content"][1]["image_url"]["url"]
    assert image_url.startswith("data:image/png;base64,")
    assert messages[-1]["content"][1]["image_url"]["detail"] == "original"
    assert call["json"]["reasoning"] == {"effort": "high"}
    assert call["json"]["max_tokens"] == 16000
    assert "temperature" not in call["json"]
    assert "max_completion_tokens" not in call["json"]
    assert analyzer.last_usage == {
        "prompt_tokens": 100,
        "completion_tokens": 50,
        "total_tokens": 150,
        "cost": 0.00012,
    }


@pytest.mark.parametrize(
    "change",
    [
        {"version": 2},
        {"size": [641, 480]},
        {"eyes": [[250, 160, float("inf")]]},
        {"eyes": [[10, 10, 24]]},
        {"eyes": [[250, 160, 24], [390, 160, 24], [320, 200, 10]]},
        {"mouth": [630, 260, 90, 36]},
        {"head": [160, 60, -1, 300]},
    ],
)
def test_invalid_face_maps_are_rejected(change: dict) -> None:
    payload = valid_face() | change

    with pytest.raises(ValidationError):
        validate_face_payload(payload, width=640, height=480)


def test_unknown_fields_are_rejected() -> None:
    with pytest.raises(ValidationError):
        validate_face_payload(valid_face() | {"confidence": 0.9}, width=640, height=480)


def test_http_or_invalid_response_is_an_analysis_error() -> None:
    analyzer, _ = analyzer_for(valid_face(), status_code=503)
    with pytest.raises(FaceAnalysisError):
        analyzer.analyze(png_bytes(), width=640, height=480, content_type="image/png")


def test_best_effort_never_fails_friend_generation() -> None:
    class Broken:
        def analyze(self, image: bytes, **kwargs):
            raise RuntimeError("provider response must not escape")

    assert (
        analyze_face_best_effort(Broken(), b"png", width=640, height=480, content_type="image/png")
        is None
    )


def test_analysis_is_disabled_until_key_and_model_are_configured() -> None:
    assert isinstance(build_face_analyzer(Settings(_env_file=None)), DisabledFaceAnalyzer)
    assert isinstance(
        build_face_analyzer(Settings(_env_file=None, openrouter_api_key=SecretStr(""))),
        DisabledFaceAnalyzer,
    )
    assert isinstance(
        build_face_analyzer(
            Settings(
                _env_file=None,
                openrouter_api_key=SecretStr("secret"),
                openrouter_face_model="",
            )
        ),
        DisabledFaceAnalyzer,
    )


def test_default_face_model_is_the_decided_model() -> None:
    settings = Settings(_env_file=None, openrouter_api_key=SecretStr("secret"))

    analyzer = build_face_analyzer(settings)

    assert isinstance(analyzer, OpenRouterFaceAnalyzer)
    assert analyzer._model == "openai/gpt-6-luna"


def test_mouth_bounds_use_center_not_top_left() -> None:
    payload = valid_face() | {"head": None, "mouth": [615, 450, 50, 40]}
    assert validate_face_payload(payload, width=640, height=480).mouth == (615, 450, 50, 40)
    for mouth in ([10, 30, 40, 20], [40, 5, 20, 20], [630, 300, 40, 20]):
        with pytest.raises(ValidationError):
            validate_face_payload(payload | {"mouth": mouth}, width=640, height=480)


def test_alpha_filter_removes_transparent_features_and_keeps_opaque_ones() -> None:
    face = validate_face_payload(valid_face(), width=640, height=480)
    alpha = Image.new("L", (640, 480), 255)
    alpha.putpixel((250, 160), 0)
    alpha.putpixel((320, 260), 0)
    alpha.putpixel((225, 225), 0)
    filtered = filter_face_by_alpha(face, alpha)
    assert filtered is not None
    assert filtered.eyes == [(390, 160, 24)]
    assert filtered.mouth is None
    assert filtered.cheeks == [(415, 225, 28)]
    assert face.mouth is not None


def test_alpha_filter_requires_opaque_center_and_three_of_five_samples() -> None:
    face = validate_face_payload(valid_face(), width=640, height=480)
    alpha = Image.new("L", (640, 480), 0)
    alpha.putpixel((250, 160), 128)
    alpha.putpixel((244, 160), 255)
    assert filter_face_by_alpha(face, alpha) is None
    alpha.putpixel((256, 160), 255)
    assert filter_face_by_alpha(face, alpha).eyes == [(250, 160, 24)]


def test_analyzer_filters_actual_png_and_returns_none_without_features() -> None:
    analyzer, _ = analyzer_for(valid_face())
    assert (
        analyzer.analyze(png_bytes(opaque=False), width=640, height=480, content_type="image/png")
        is None
    )


def test_invalid_or_wrong_size_png_is_rejected_before_paid_call() -> None:
    analyzer, client = analyzer_for(valid_face())
    for image, width in ((b"not-png", 640), (png_bytes(), 641)):
        with pytest.raises(FaceAnalysisError):
            analyzer.analyze(image, width=width, height=480, content_type="image/png")
    assert client.calls == []


def test_best_effort_handles_alpha_and_provider_failure() -> None:
    analyzer, _ = analyzer_for(valid_face(), status_code=503)
    assert analyze_face_best_effort(analyzer, png_bytes(), width=640, height=480) is None


def test_failed_call_clears_previous_usage() -> None:
    analyzer, client = analyzer_for(valid_face())
    analyzer.analyze(png_bytes(), width=640, height=480, content_type="image/png")
    assert analyzer.last_usage is not None
    client.response.status_code = 503
    with pytest.raises(FaceAnalysisError):
        analyzer.analyze(png_bytes(), width=640, height=480, content_type="image/png")
    assert analyzer.last_usage is None


def test_bundled_examples_preserve_reviewed_coordinates() -> None:
    directory = Path(__file__).parents[1] / "app" / "face_examples"
    bundle = json.loads((directory / "reviewed.json").read_text())
    assert bundle["status"] == "reviewed"
    assert [e["id"] for e in bundle["examples"]] == ["016", "028", "dduchi", "021", "023", "029"]
    for example in bundle["examples"]:
        assert example["reviewed"] is True
        with Image.open(directory / f"{example['id']}.png") as image:
            width, height = image.size
        validate_face_payload(example["face"], width=width, height=height)
    assert bundle["examples"][-1]["face"]["facing"] == "left"
    assert bundle["examples"][-1]["face"]["cheeks"] == [[540, 461, 40]]


def test_png_without_alpha_is_treated_as_opaque() -> None:
    image = Image.new("RGB", (640, 480), "white")
    stream = BytesIO()
    image.save(stream, format="PNG")
    analyzer, _ = analyzer_for(valid_face())
    result = analyzer.analyze(stream.getvalue(), width=640, height=480, content_type="image/png")
    assert face_to_json(result) == valid_face()


def test_palette_png_transparency_is_filtered() -> None:
    image = Image.new("P", (640, 480), 0)
    stream = BytesIO()
    image.save(stream, format="PNG", transparency=0)
    analyzer, _ = analyzer_for(valid_face())
    assert (
        analyzer.analyze(stream.getvalue(), width=640, height=480, content_type="image/png") is None
    )
