"""원본 검사, AI 입력 정규화, 투명 PNG 검사·썸네일·대표색."""

import base64
import io
import warnings
from dataclasses import dataclass

from PIL import Image, ImageOps, UnidentifiedImageError

MAX_UPLOAD_BYTES = 10 * 1024 * 1024
MAX_RESULT_BYTES = 30 * 1024 * 1024


class InvalidImage(ValueError):
    pass


def open_image(data: bytes, *, result: bool = False) -> Image.Image:
    if not data or len(data) > (MAX_RESULT_BYTES if result else MAX_UPLOAD_BYTES):
        raise InvalidImage("잘못된 이미지 크기예요.")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(data)) as image:
                allowed = {"PNG"} if result else {"PNG", "JPEG"}
                if image.format not in allowed or getattr(image, "n_frames", 1) != 1:
                    raise InvalidImage("PNG 또는 JPEG 한 장을 올려 주세요.")
                if not all(64 <= size <= 4096 for size in image.size):
                    raise InvalidImage("이미지 가로·세로는 각각 64~4096픽셀이어야 해요.")
                image.verify()
            with Image.open(io.BytesIO(data)) as image:
                image.load()
                copy = image.copy()
                copy.format = image.format
                return copy
    except (
        UnidentifiedImageError,
        OSError,
        Image.DecompressionBombError,
        Image.DecompressionBombWarning,
        SyntaxError,
        ValueError,
    ) as exc:
        if isinstance(exc, InvalidImage):
            raise
        raise InvalidImage("이미지를 읽을 수 없어요.") from None


def input_reference(data: bytes) -> str:
    image = ImageOps.exif_transpose(open_image(data))
    image.thumbnail((1536, 1536), Image.Resampling.LANCZOS)
    output = io.BytesIO()
    # 모델 실측 때 검증한 JPEG 입력 형식을 따른다. 투명 캔버스는 흰 바탕에 합성한다.
    rgba = image.convert("RGBA")
    reference = Image.new("RGB", image.size, "white")
    reference.paste(rgba, mask=rgba.getchannel("A"))
    reference.save(output, "JPEG", quality=92)
    return "data:image/jpeg;base64," + base64.b64encode(output.getvalue()).decode("ascii")


@dataclass(frozen=True)
class CharacterImage:
    art: bytes
    thumbnail: bytes
    width: int
    height: int
    accent_argb: int


def character_image(data: bytes) -> CharacterImage:
    image = open_image(data, result=True).convert("RGBA")
    alpha = image.getchannel("A")
    histogram = alpha.histogram()
    pixels = image.width * image.height
    corners = (
        (0, 0),
        (image.width - 1, 0),
        (0, image.height - 1),
        (image.width - 1, image.height - 1),
    )
    if (
        histogram[0] / pixels < 0.05
        or sum(histogram[200:]) / pixels < 0.01
        or any(alpha.getpixel(point) != 0 for point in corners)
    ):
        raise InvalidImage("투명 배경 캐릭터 PNG를 만들지 못했어요.")
    sample = image.copy()
    sample.thumbnail((128, 128), Image.Resampling.LANCZOS)
    pixels = sample.load()
    opaque = [
        pixels[x, y]
        for y in range(sample.height)
        for x in range(sample.width)
        if pixels[x, y][3] >= 200
    ]
    if not opaque:
        raise InvalidImage("캐릭터의 대표색을 찾을 수 없어요.")
    rgb = [round(sum(p[i] for p in opaque) / len(opaque)) for i in range(3)]
    accent = (255 << 24) | (rgb[0] << 16) | (rgb[1] << 8) | rgb[2]
    thumb = ImageOps.contain(image, (256, 256), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (256, 256))
    canvas.alpha_composite(thumb, ((256 - thumb.width) // 2, (256 - thumb.height) // 2))
    output = io.BytesIO()
    canvas.save(output, "PNG")
    return CharacterImage(data, output.getvalue(), image.width, image.height, accent)
