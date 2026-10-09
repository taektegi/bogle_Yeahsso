import json
import struct
from pathlib import Path

from app.face_analysis import FaceMap, validate_face_payload
from scripts.check_face_analysis import main, read_png


def png_header(width: int, height: int) -> bytes:
    return b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR" + struct.pack(">II", width, height)


def face(width: int, height: int) -> FaceMap:
    return validate_face_payload(
        {
            "version": 1,
            "size": [width, height],
            "facing": "front",
            "head": [10, 10, 80, 80],
            "eyes": [[35, 40, 5], [65, 40, 5]],
            "mouth": [50, 65, 20, 8],
            "cheeks": [],
        },
        width=width,
        height=height,
    )


class FakeAnalyzer:
    def __init__(self, result: FaceMap) -> None:
        self.result = result
        self.calls: list[dict] = []

    def analyze(self, image: bytes, **kwargs) -> FaceMap:
        self.calls.append({"image": image, **kwargs})
        return self.result


def test_read_png_reads_ihdr_size(tmp_path: Path) -> None:
    image_path = tmp_path / "character.png"
    image_path.write_bytes(png_header(320, 240))

    image, width, height = read_png(image_path)

    assert image == image_path.read_bytes()
    assert (width, height) == (320, 240)


def test_main_analyzes_png_and_writes_json(tmp_path: Path) -> None:
    image_path = tmp_path / "character.png"
    output_path = tmp_path / "result" / "character.ai.face.json"
    image_path.write_bytes(png_header(100, 100))
    analyzer = FakeAnalyzer(face(100, 100))

    exit_code = main(
        [str(image_path), "--output", str(output_path)],
        analyzer=analyzer,
    )

    assert exit_code == 0
    assert json.loads(output_path.read_text(encoding="utf-8"))["size"] == [100, 100]
    assert analyzer.calls == [
        {
            "image": image_path.read_bytes(),
            "width": 100,
            "height": 100,
            "content_type": "image/png",
        }
    ]


def test_main_does_not_overwrite_result_without_force(tmp_path: Path) -> None:
    image_path = tmp_path / "character.png"
    output_path = tmp_path / "character.ai.face.json"
    image_path.write_bytes(png_header(100, 100))
    output_path.write_text("keep", encoding="utf-8")

    exit_code = main(
        [str(image_path), "--output", str(output_path)],
        analyzer=FakeAnalyzer(face(100, 100)),
    )

    assert exit_code == 2
    assert output_path.read_text(encoding="utf-8") == "keep"
