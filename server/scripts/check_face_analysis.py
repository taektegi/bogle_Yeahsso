"""캐릭터 PNG 한 장을 OpenRouter로 분석해 얼굴 좌표 JSON을 확인한다.

공개 API나 Supabase를 거치지 않는 개발용 수동 확인 명령이다.

    cd server
    python -m scripts.check_face_analysis /path/to/character.png \
      --output /tmp/character.ai.face.json
"""

import argparse
import json
import struct
import sys
from collections.abc import Sequence
from pathlib import Path

from app.config import Settings
from app.face_analysis import (
    DisabledFaceAnalyzer,
    FaceAnalysisError,
    FaceAnalyzer,
    build_face_analyzer,
    face_to_json,
)

_PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
_SERVER_DIR = Path(__file__).resolve().parents[1]


class PngReadError(ValueError):
    """수동 확인에 사용할 수 없는 PNG다."""


def read_png(path: Path) -> tuple[bytes, int, int]:
    """PNG 바이트와 IHDR의 가로·세로 크기를 읽는다."""

    try:
        image = path.read_bytes()
    except OSError as exc:
        reason = exc.strerror or type(exc).__name__
        raise PngReadError(f"PNG를 읽을 수 없습니다: {reason}") from None

    if (
        len(image) < 24
        or image[:8] != _PNG_SIGNATURE
        or image[8:12] != b"\x00\x00\x00\r"
        or image[12:16] != b"IHDR"
    ):
        raise PngReadError("올바른 PNG 파일이 아닙니다.")

    width, height = struct.unpack(">II", image[16:24])
    if not (1 <= width <= 8192 and 1 <= height <= 8192):
        raise PngReadError("PNG 크기는 가로·세로 각각 1~8192 픽셀이어야 합니다.")
    return image, width, height


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="투명 배경 캐릭터 PNG의 얼굴 좌표를 OpenRouter로 계산합니다."
    )
    parser.add_argument("image", type=Path, help="분석할 캐릭터 PNG 경로")
    parser.add_argument(
        "--output",
        type=Path,
        help="결과 JSON을 저장할 경로. 생략하면 터미널에 출력합니다.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="이미 존재하는 출력 파일을 덮어씁니다.",
    )
    return parser


def main(argv: Sequence[str] | None = None, *, analyzer: FaceAnalyzer | None = None) -> int:
    args = _parser().parse_args(argv)

    try:
        image, width, height = read_png(args.image)
    except PngReadError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    if analyzer is None:
        settings = Settings(_env_file=_SERVER_DIR / ".env")
        analyzer = build_face_analyzer(settings)
    if isinstance(analyzer, DisabledFaceAnalyzer):
        print(
            "OPENROUTER_API_KEY가 없습니다. server/.env에 키를 입력하세요.",
            file=sys.stderr,
        )
        return 2

    try:
        face = analyzer.analyze(
            image,
            width=width,
            height=height,
            content_type="image/png",
        )
    except FaceAnalysisError as exc:
        print(f"얼굴 좌표 분석에 실패했습니다: {exc}", file=sys.stderr)
        return 1

    if face is None:
        print("얼굴 좌표 결과가 없습니다.", file=sys.stderr)
        return 1

    rendered = json.dumps(face_to_json(face), ensure_ascii=False, indent=2) + "\n"
    usage = getattr(analyzer, "last_usage", None)
    if isinstance(usage, dict):
        prompt_tokens = usage.get("prompt_tokens", "확인 불가")
        completion_tokens = usage.get("completion_tokens", "확인 불가")
        cost = usage.get("cost")
        cost_text = f"${cost:.8f}" if isinstance(cost, (int, float)) else "확인 불가"
        print(
            f"OpenRouter 사용량: 입력 {prompt_tokens}, 출력 {completion_tokens}, 비용 {cost_text}",
            file=sys.stderr,
        )
    if args.output is None:
        print(rendered, end="")
        return 0

    if args.output.exists() and not args.force:
        print(
            f"출력 파일이 이미 있습니다: {args.output} (--force로 덮어쓸 수 있습니다)",
            file=sys.stderr,
        )
        return 2
    try:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
    except OSError as exc:
        print(
            f"결과를 저장할 수 없습니다: {exc.strerror or type(exc).__name__}",
            file=sys.stderr,
        )
        return 2

    print(f"얼굴 좌표를 저장했습니다: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
