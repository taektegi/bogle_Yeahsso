"""이미지 검사와 후처리 (FR-03.2, FR-04.3).

- 업로드 검사: 파일 내용으로 형식(PNG/JPEG)을 정하고 크기·해상도를 검사한다.
- 캐릭터 그림 후처리: 배경을 투명하게, 캐릭터만 남게 자르고, 썸네일과 대표색을 만든다.

앱은 캐릭터 그림의 **투명한 부분**으로 실루엣·그림자·간식 위치를 계산한다. 그래서 생성 모델이
배경을 남겨도(투명 배경 요청을 지키지 않아도) 여기서 한 번 더 걷어 내고, 캐릭터가 그림을 꽉
채우도록 여백을 일정하게 맞춘다. 얼굴 지도(app/face_map.py)는 이 후처리가 끝난 그림의 픽셀
좌표로 만든다.
"""

import io
from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageFilter, UnidentifiedImageError

from app.errors import ApiError

MAX_UPLOAD_BYTES = 10 * 1024 * 1024  # API 계약 3.2절: 10 MiB
MIN_SIDE = 64
MAX_SIDE = 4096

# 캐릭터 그림: 긴 변 최대 1024px, 캐릭터 둘레에 긴 변의 4%만큼 여백
ART_MAX_SIDE = 1024
ART_MARGIN = 0.04
THUMBNAIL_SIDE = 256

# 알파가 이 값보다 크면 "그려진" 픽셀로 본다.
OPAQUE = 24

Image.MAX_IMAGE_PIXELS = MAX_SIDE * MAX_SIDE  # 해상도 폭탄 방지


@dataclass(frozen=True)
class ImageInfo:
    content_type: str
    width: int
    height: int


def file_too_large() -> ApiError:
    return ApiError(413, "file_too_large", "파일이 너무 커요. 10MB 이하로 올려 주세요.")


def invalid_image(
    message: str = "이미지를 읽을 수 없어요. PNG나 JPEG 사진을 올려 주세요.",
) -> ApiError:
    return ApiError(422, "invalid_image", message)


def sniff_content_type(data: bytes) -> str | None:
    """확장자나 헤더가 아니라 파일 내용(시그니처)으로 형식을 정한다."""
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    return None


def inspect_upload(data: bytes) -> ImageInfo:
    """업로드 파일을 검사한다. 통과하지 못하면 413/422 ApiError."""
    if len(data) > MAX_UPLOAD_BYTES:
        raise file_too_large()
    content_type = sniff_content_type(data)
    if content_type is None:
        raise invalid_image()
    try:
        with Image.open(io.BytesIO(data)) as image:
            width, height = image.size
            image.verify()  # 잘린 파일·깨진 데이터를 거른다
        with Image.open(io.BytesIO(data)) as image:
            image.load()
    except (UnidentifiedImageError, OSError, SyntaxError, Image.DecompressionBombError):
        raise invalid_image() from None
    if not (MIN_SIDE <= width <= MAX_SIDE and MIN_SIDE <= height <= MAX_SIDE):
        raise invalid_image(f"사진의 가로·세로는 {MIN_SIDE}–{MAX_SIDE}px 사이여야 해요.")
    return ImageInfo(content_type=content_type, width=width, height=height)


def open_rgba(data: bytes) -> Image.Image:
    with Image.open(io.BytesIO(data)) as image:
        image.load()
        return image.convert("RGBA")


def png_bytes(image: Image.Image) -> bytes:
    out = io.BytesIO()
    image.save(out, format="PNG", optimize=True)
    return out.getvalue()


def alpha(image: Image.Image) -> np.ndarray:
    return np.asarray(image.getchannel("A"))


def coverage(image: Image.Image) -> float:
    """그려진 픽셀의 비율 (0–1)."""
    return float((alpha(image) > OPAQUE).mean())


def flatten_on_white(image: Image.Image, padding: int = 0) -> Image.Image:
    """투명한 부분을 흰 종이로. 그림 모델(생성·모션)은 흰 종이 위의 그림을 가장 잘 읽는다."""
    image = image.convert("RGBA")
    page = Image.new("RGB", (image.width + 2 * padding, image.height + 2 * padding), "white")
    page.paste(image, (padding, padding), image)
    return page


def has_clear_ground(image: Image.Image) -> bool:
    """네 모서리 중 셋 이상이 투명하면 배경이 이미 걷힌 그림이다 (앱과 같은 기준)."""
    a = alpha(image)
    h, w = a.shape
    patch = max(2, min(w, h) // 40)
    corners = [
        a[:patch, :patch],
        a[:patch, w - patch :],
        a[h - patch :, :patch],
        a[h - patch :, w - patch :],
    ]
    return sum(int(c.mean() < OPAQUE) for c in corners) >= 3


def remove_background(image: Image.Image, tolerance: float = 38.0) -> Image.Image:
    """테두리에 닿은 배경을 투명하게 한다.

    생성 모델이 투명 배경을 지키지 않고 단색(대개 흰색·연한 색) 배경을 그렸을 때 쓴다. 테두리
    픽셀의 대표색과 비슷하면서 **테두리와 이어진** 영역만 지우므로, 캐릭터 안쪽의 흰 눈·배는
    남는다. 경계는 살짝 부드럽게 한다.
    """
    image = image.convert("RGBA")
    if has_clear_ground(image):
        return image
    rgb = np.asarray(image.convert("RGB")).astype(np.int16)
    h, w, _ = rgb.shape
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    ground = np.median(border, axis=0)
    close = np.sqrt(((rgb - ground) ** 2).sum(axis=2)) < tolerance

    # 테두리에서 시작하는 연결 영역 (4방향). 작게 줄인 격자에서 넓힌 뒤 원래 크기로 되돌리고,
    # 원래 해상도의 "배경색과 비슷함"으로 다시 다듬는다.
    step = max(1, max(w, h) // 256)
    small_close = (
        np.asarray(
            Image.fromarray((close * 255).astype(np.uint8), "L").resize(
                (max(1, w // step), max(1, h // step)), Image.Resampling.BOX
            )
        )
        > 127
    )
    reached_small = np.zeros_like(small_close)
    reached_small[0, :] = small_close[0, :]
    reached_small[-1, :] = small_close[-1, :]
    reached_small[:, 0] |= small_close[:, 0]
    reached_small[:, -1] |= small_close[:, -1]
    while True:
        grown = reached_small.copy()
        grown[1:, :] |= reached_small[:-1, :]
        grown[:-1, :] |= reached_small[1:, :]
        grown[:, 1:] |= reached_small[:, :-1]
        grown[:, :-1] |= reached_small[:, 1:]
        grown &= small_close
        if (grown == reached_small).all():
            break
        reached_small = grown
    spread = (
        Image.fromarray((reached_small * 255).astype(np.uint8), "L")
        .resize((w, h), Image.Resampling.NEAREST)
        .filter(ImageFilter.MaxFilter(2 * step + 1))
    )
    reached = (np.asarray(spread) > 0) & close

    a = np.where(reached, 0, 255).astype(np.uint8)
    mask = Image.fromarray(a, "L").filter(ImageFilter.GaussianBlur(1.2))
    original = alpha(image)
    out = image.copy()
    out.putalpha(Image.fromarray(np.minimum(np.asarray(mask), original), "L"))
    return out


def drawn_box(image: Image.Image) -> tuple[int, int, int, int] | None:
    """그려진 부분의 상자 (left, top, right, bottom; right·bottom은 포함하지 않음)."""
    a = alpha(image) > OPAQUE
    rows = np.flatnonzero(a.any(axis=1))
    cols = np.flatnonzero(a.any(axis=0))
    if rows.size == 0:
        return None
    return int(cols[0]), int(rows[0]), int(cols[-1]) + 1, int(rows[-1]) + 1


def keep_largest_figure(image: Image.Image) -> Image.Image:
    """캐릭터와 떨어진 작은 얼룩(모델이 남긴 점·글자 조각)을 지운다.

    가장 큰 덩어리의 2% 미만인 덩어리만 지운다. 떨어져 그린 팔·꼬리처럼 큰 부분은 남는다.
    """
    a = alpha(image) > OPAQUE
    small = Image.fromarray((a * 255).astype(np.uint8), "L").resize(
        (max(1, image.width // 4), max(1, image.height // 4)), Image.Resampling.BOX
    )
    grid = np.asarray(small) > 0
    labels = _label(grid)
    if labels.max() <= 1:
        return image
    sizes = np.bincount(labels.ravel())
    sizes[0] = 0
    keep = sizes >= sizes.max() * 0.02
    keep[0] = False
    keep_grid = keep[labels]
    keep_mask = Image.fromarray((keep_grid * 255).astype(np.uint8), "L").resize(
        image.size, Image.Resampling.NEAREST
    )
    keep_full = np.asarray(keep_mask.filter(ImageFilter.MaxFilter(9))) > 0
    out = image.copy()
    out.putalpha(Image.fromarray(np.where(keep_full, alpha(image), 0).astype(np.uint8), "L"))
    return out


def _label(grid: np.ndarray) -> np.ndarray:
    """True 칸의 연결 성분 번호 (8방향, 0은 배경). 작은 격자에서만 쓴다."""
    h, w = grid.shape
    labels = np.zeros((h, w), dtype=np.int32)
    current = 0
    for y, x in zip(*np.nonzero(grid), strict=True):
        if labels[y, x]:
            continue
        current += 1
        stack = [(y, x)]
        labels[y, x] = current
        while stack:
            cy, cx = stack.pop()
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h and 0 <= nx < w and grid[ny, nx] and not labels[ny, nx]:
                        labels[ny, nx] = current
                        stack.append((ny, nx))
    return labels


def frame_figure(image: Image.Image) -> Image.Image:
    """캐릭터만 남게 자르고 둘레에 일정한 여백을 둔 뒤, 긴 변이 ART_MAX_SIDE를 넘지 않게 줄인다.

    앱은 캐릭터를 그림 상자 아래쪽에 세우므로, 여백이 들쭉날쭉하면 캐릭터가 바닥에서 떠 보이거나
    그림자가 어긋난다. 여백을 일정하게 맞추면 어떤 캐릭터든 같은 자리에 선다.
    """
    box = drawn_box(image)
    if box is None:
        return image
    left, top, right, bottom = box
    figure = image.crop(box)
    margin = round(max(figure.width, figure.height) * ART_MARGIN) + 2
    framed = Image.new("RGBA", (figure.width + 2 * margin, figure.height + 2 * margin))
    framed.paste(figure, (margin, margin))
    longest = max(framed.size)
    if longest > ART_MAX_SIDE:
        scale = ART_MAX_SIDE / longest
        framed = framed.resize(
            (max(1, round(framed.width * scale)), max(1, round(framed.height * scale))),
            Image.Resampling.LANCZOS,
        )
    return framed


def thumbnail(image: Image.Image, side: int = THUMBNAIL_SIDE) -> Image.Image:
    """정사각형 썸네일. 캐릭터를 가운데에 두고 나머지는 투명하게 둔다."""
    image = image.copy()
    image.thumbnail((side, side), Image.Resampling.LANCZOS)
    square = Image.new("RGBA", (side, side))
    square.paste(image, ((side - image.width) // 2, (side - image.height) // 2), image)
    return square


def accent_argb(image: Image.Image) -> int:
    """캐릭터의 대표색으로 만든 파스텔색 (ARGB, 불투명).

    보관함 카드 배경과 집 전환 색으로 쓰이므로 진한 색 그대로가 아니라 흰색과 섞은 밝은 색을
    준다. 채도가 거의 없는 캐릭터(흑백 그림)는 보글 기본 파란색을 쓴다.
    """
    small = image.convert("RGBA").copy()
    small.thumbnail((96, 96))
    data = np.asarray(small).reshape(-1, 4).astype(np.float64)
    pixels = data[data[:, 3] > 200][:, :3]
    if len(pixels) == 0:
        return 0xFFBDCFFF
    mx = pixels.max(axis=1)
    mn = pixels.min(axis=1)
    saturation = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1), 0)
    lightness = (mx + mn) / 2
    # 윤곽선(어두운 색)과 하이라이트(흰색)는 빼고, 채도가 있는 색만 본다.
    vivid = pixels[(saturation > 0.18) & (lightness > 40) & (lightness < 245)]
    if len(vivid) < len(pixels) * 0.05:
        return 0xFFBDCFFF
    # 색을 6단계로 묶어 가장 많은 묶음의 평균을 대표색으로 한다.
    bins = (vivid // 43).astype(np.int64)
    keys = bins[:, 0] * 36 + bins[:, 1] * 6 + bins[:, 2]
    top = np.bincount(keys).argmax()
    color = vivid[keys == top].mean(axis=0)
    pastel = color * 0.45 + 255 * 0.55
    r, g, b = (int(round(c)) for c in pastel)
    return (0xFF << 24) | (r << 16) | (g << 8) | b


def is_blank_drawing(image: Image.Image) -> bool:
    """아무것도 그려지지 않았거나 거의 단색인 입력. 생성 모델에 보내도 캐릭터가 나오지 않는다."""
    if image.mode == "RGBA" and coverage(image) < 0.0005:
        return True
    gray = np.asarray(flatten_on_white(image).convert("L")).astype(np.float64)
    return float(gray.std()) < 2.0
