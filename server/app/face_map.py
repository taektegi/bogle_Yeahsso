"""캐릭터 그림의 얼굴 지도: 눈·입·볼·머리 위치와 보는 방향.

앱은 이 지도로 PNG 캐릭터의 얼굴을 움직이고(눈 깜빡임·찡긋, 입 벌리기·오물오물, 볼 빵빵),
간식을 **입에** 가져다 대고, 말풍선을 머리 옆에 띄운다. 그래서 좌표가 조금만 어긋나도 간식이
허공이나 눈앞에 떠 있게 된다 (앱 저장소 docs/CHARACTER_RIG.md "PNG 캐릭터: 얼굴 지도").

만드는 순서
1. 그림을 보고 위치를 말해 주는 모델(app/ai.py)에게 JSON으로 묻는다.
2. **그림과 대조해 고친다** (`refine`). 모델은 자주 몇 픽셀~수십 픽셀 어긋나거나, 입을
   투명한 곳에 찍거나, 눈을 하나 빼먹는다.
   - 모든 좌표를 그림 안으로 넣는다.
   - 눈은 그림에서 찾은 어두운 동그라미(눈동자)에 붙인다. 그려진 곳 밖의 눈은 버린다.
   - 입이 없거나 투명한 곳·눈보다 위에 있으면, 눈과 머리 모양으로 다시 정한다.
   - 머리 상자는 그림 안으로 줄이고, 눈과 입을 반드시 감싸게 넓힌다.
3. 모델을 쓸 수 없거나 답이 쓸모없으면, 그림만 보고 추정한다 (`estimate`).

좌표는 앱과 같은 형식이다 (그림의 픽셀, 원점은 왼쪽 위).

    {"version": 1, "size": [W, H], "facing": "left"|"right"|"front",
     "head": [x, y, w, h], "eyes": [[cx, cy, r], ...],
     "mouth": [cx, cy, w, h], "cheeks": [[cx, cy, r], ...]}
"""

import math
from dataclasses import dataclass, field, replace
from typing import Any, Literal

import numpy as np
from PIL import Image

from app.imaging import OPAQUE, alpha, drawn_box

Facing = Literal["left", "right", "front"]

# 분석은 긴 변 이 크기로 줄여서 한다 (속도). 결과는 원래 픽셀로 되돌린다.
_ANALYSIS_SIDE = 320


@dataclass(frozen=True)
class Circle:
    x: float
    y: float
    r: float


@dataclass(frozen=True)
class Box:
    x: float
    y: float
    w: float
    h: float

    @property
    def right(self) -> float:
        return self.x + self.w

    @property
    def bottom(self) -> float:
        return self.y + self.h

    @property
    def cx(self) -> float:
        return self.x + self.w / 2

    @property
    def cy(self) -> float:
        return self.y + self.h / 2


@dataclass(frozen=True)
class FaceMap:
    width: int
    height: int
    facing: Facing = "front"
    head: Box | None = None
    eyes: tuple[Circle, ...] = ()
    # 입은 가운데와 크기 (cx, cy, w, h) — 앱 형식과 같다
    mouth: Box | None = None
    cheeks: tuple[Circle, ...] = ()
    # model: 모델 답을 고쳐 쓴 것 / estimate: 그림만 보고 추정한 것 (앱은 쓰지 않는 참고값)
    source: str = "estimate"
    notes: tuple[str, ...] = field(default=())

    def to_json(self) -> dict[str, Any]:
        def r(v: float) -> float:
            return round(float(v), 1)

        data: dict[str, Any] = {
            "version": 1,
            "size": [self.width, self.height],
            "facing": self.facing,
            "source": self.source,
        }
        if self.head:
            data["head"] = [r(self.head.x), r(self.head.y), r(self.head.w), r(self.head.h)]
        data["eyes"] = [[r(e.x), r(e.y), r(e.r)] for e in self.eyes]
        if self.mouth:
            data["mouth"] = [r(self.mouth.cx), r(self.mouth.cy), r(self.mouth.w), r(self.mouth.h)]
        data["cheeks"] = [[r(c.x), r(c.y), r(c.r)] for c in self.cheeks]
        return data


# ---------------------------------------------------------------------------
# 그림 분석
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class _Page:
    """분석용으로 줄인 그림. scale을 곱하면 원래 픽셀이 된다."""

    opaque: np.ndarray  # bool (h, w)
    luma: np.ndarray  # float (h, w) 0–255
    scale: float
    figure: Box  # 원래 픽셀


def _page(image: Image.Image) -> _Page | None:
    box = drawn_box(image)
    if box is None:
        return None
    small = image.convert("RGBA").copy()
    small.thumbnail((_ANALYSIS_SIDE, _ANALYSIS_SIDE), Image.Resampling.BOX)
    scale = image.width / small.width
    rgba = np.asarray(small).astype(np.float64)
    luma = 0.299 * rgba[..., 0] + 0.587 * rgba[..., 1] + 0.114 * rgba[..., 2]
    left, top, right, bottom = box
    return _Page(
        opaque=rgba[..., 3] > OPAQUE,
        luma=luma,
        scale=scale,
        figure=Box(left, top, right - left, bottom - top),
    )


def _components(mask: np.ndarray) -> list[np.ndarray]:
    """True 칸의 연결 성분(8방향)마다 (y, x) 좌표 배열."""
    h, w = mask.shape
    seen = np.zeros_like(mask)
    found: list[np.ndarray] = []
    for y, x in zip(*np.nonzero(mask), strict=True):
        if seen[y, x]:
            continue
        stack = [(y, x)]
        seen[y, x] = True
        cells = []
        while stack:
            cy, cx = stack.pop()
            cells.append((cy, cx))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
        found.append(np.array(cells))
    return found


def find_eyes(image: Image.Image) -> list[Circle]:
    """그려진 곳 안의 어둡고 동그란 점(눈동자) 후보. 큰 것·위쪽 것부터.

    윤곽선도 어둡지만 가늘고 길어서 "동그람"으로 걸러진다. 그림 가장자리에 닿은 덩어리
    (윤곽선·발)는 빼고, 그림 위쪽 75% 안의 것만 본다.
    """
    page = _page(image)
    if page is None:
        return []
    opaque = page.opaque
    inside = opaque.copy()
    # 가장자리(윤곽선 바깥쪽)에서 2칸 안쪽만 본다.
    for shift in ((1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0), (0, 2), (0, -2)):
        inside &= np.roll(opaque, shift, axis=(0, 1))
    if not inside.any():
        return []
    values = page.luma[inside]
    threshold = min(90.0, float(np.percentile(values, 12)))
    dark = inside & (page.luma <= threshold)

    figure_area = float(opaque.sum())
    top_limit = (page.figure.y + page.figure.h * 0.75) / page.scale
    candidates: list[tuple[float, Circle]] = []
    for cells in _components(dark):
        area = len(cells)
        if area < 3 or area > figure_area * 0.04:
            continue
        ys, xs = cells[:, 0], cells[:, 1]
        h = ys.max() - ys.min() + 1
        w = xs.max() - xs.min() + 1
        if max(h, w) > 2.6 * min(h, w):  # 가늘고 긴 것은 선
            continue
        fill = area / float(h * w)
        if fill < 0.45:  # 속이 빈 고리·꺾인 선
            continue
        cy, cx = ys.mean(), xs.mean()
        if cy > top_limit:
            continue
        radius = math.sqrt(area / math.pi)
        score = area * fill
        candidates.append(
            (score, Circle(cx * page.scale, cy * page.scale, radius * page.scale * 1.15))
        )
    candidates.sort(key=lambda c: -c[0])
    return [c for _, c in candidates[:6]]


def _pick_eyes(candidates: list[Circle]) -> list[Circle]:
    """후보 중 크기가 비슷하고 높이가 맞는 한 쌍, 없으면 가장 그럴듯한 하나."""
    best: tuple[float, list[Circle]] | None = None
    for i, a in enumerate(candidates):
        for b in candidates[i + 1 :]:
            size_ratio = min(a.r, b.r) / max(a.r, b.r)
            gap = abs(a.x - b.x)
            level = abs(a.y - b.y)
            mean_r = (a.r + b.r) / 2
            if size_ratio < 0.55 or level > mean_r * 1.6 or gap < mean_r * 1.8:
                continue
            if gap > mean_r * 14:
                continue
            score = size_ratio * (a.r + b.r) - level * 0.3
            if best is None or score > best[0]:
                best = (score, sorted([a, b], key=lambda e: e.x))
    if best:
        return best[1]
    return candidates[:1]


def _opaque_at(image: Image.Image, x: float, y: float) -> bool:
    if not (0 <= x < image.width and 0 <= y < image.height):
        return False
    return int(image.getchannel("A").getpixel((int(x), int(y)))) > OPAQUE


def _nearest_opaque(
    image: Image.Image, x: float, y: float, toward: tuple[float, float]
) -> tuple[float, float] | None:
    """(x, y)에서 toward 쪽으로 걸어가며 처음 만나는 그려진 픽셀."""
    tx, ty = toward
    steps = 40
    for i in range(steps + 1):
        px = x + (tx - x) * i / steps
        py = y + (ty - y) * i / steps
        if _opaque_at(image, px, py):
            return px, py
    return None


def _clamp_box(box: Box, bounds: Box) -> Box | None:
    left = max(box.x, bounds.x)
    top = max(box.y, bounds.y)
    right = min(box.right, bounds.right)
    bottom = min(box.bottom, bounds.bottom)
    if right - left < 2 or bottom - top < 2:
        return None
    return Box(left, top, right - left, bottom - top)


def _cover(box: Box, points: list[tuple[float, float, float]]) -> Box:
    """box를 넓혀 점(반지름 포함)들을 모두 감싼다."""
    left, top, right, bottom = box.x, box.y, box.right, box.bottom
    for x, y, r in points:
        left, top = min(left, x - r), min(top, y - r)
        right, bottom = max(right, x + r), max(bottom, y + r)
    return Box(left, top, right - left, bottom - top)


def _facing_from(eyes: list[Circle], figure: Box) -> Facing:
    """보이는 눈이 하나뿐이고 그림 한쪽으로 치우쳐 있으면 옆모습: 눈이 있는 쪽을 본다."""
    if len(eyes) != 1:
        return "front"
    offset = (eyes[0].x - figure.cx) / max(figure.w, 1)
    if offset < -0.12:
        return "left"
    if offset > 0.12:
        return "right"
    return "front"


def _head_around(eyes: list[Circle], figure: Box, facing: Facing) -> Box:
    """눈으로 머리 상자를 정한다. 눈이 없으면 그림 위쪽 55%."""
    if not eyes:
        return Box(figure.x, figure.y, figure.w, figure.h * 0.55)
    xs = [e.x for e in eyes]
    ys = [e.y for e in eyes]
    r = max(e.r for e in eyes)
    span = max(xs) - min(xs)
    width = max(span * 2.4, r * 7, figure.w * 0.35)
    height = width * 0.85
    cx = sum(xs) / len(xs)
    if facing == "left":
        cx -= r * 1.5
    elif facing == "right":
        cx += r * 1.5
    cy = sum(ys) / len(ys) + height * 0.08
    head = Box(cx - width / 2, cy - height / 2, width, height)
    return _clamp_box(head, figure) or Box(figure.x, figure.y, figure.w, figure.h * 0.55)


def _snout_tip(
    image: Image.Image, facing: Facing, head: Box, eye: Circle
) -> tuple[float, float] | None:
    """옆모습의 주둥이 끝: 눈 높이부터 머리 아래까지에서 보는 쪽으로 가장 멀리 그려진 곳."""
    a = alpha(image) > OPAQUE
    top = int(max(0, eye.y - eye.r))
    bottom = int(min(image.height, head.bottom))
    if bottom <= top:
        return None
    band = a[top:bottom]
    cols = np.flatnonzero(band.any(axis=0))
    if cols.size == 0:
        return None
    x = cols[0] if facing == "left" else cols[-1]
    rows = np.flatnonzero(band[:, x])
    return float(x), float(top + rows.mean())


def _run_at(
    image: Image.Image, x: float, y: float, *, top: float, bottom: float
) -> tuple[float, float] | None:
    """x 열에서 y를 지나는 그려진 구간(위, 아래). y가 비어 있으면 가장 가까운 구간."""
    col = alpha(image)[:, int(min(max(x, 0), image.width - 1))] > OPAQUE
    lo, hi = int(max(0, top)), int(min(image.height, bottom))
    rows = np.flatnonzero(col[lo:hi]) + lo
    if rows.size == 0:
        return None
    # 연속 구간으로 나눈다.
    breaks = np.flatnonzero(np.diff(rows) > 1)
    starts = np.concatenate([[rows[0]], rows[breaks + 1]])
    ends = np.concatenate([rows[breaks], [rows[-1]]])
    best = min(
        zip(starts, ends, strict=True),
        key=lambda se: 0 if se[0] <= y <= se[1] else min(abs(se[0] - y), abs(se[1] - y)),
    )
    return float(best[0]), float(best[1])


def _mouth_for(image: Image.Image, facing: Facing, head: Box, eyes: list[Circle]) -> Box:
    """눈과 머리로 입 자리를 정한다. 그려진 곳 위에 오도록 맞춘다."""
    if eyes:
        r = sum(e.r for e in eyes) / len(eyes)
        ey = sum(e.y for e in eyes) / len(eyes)
        ex = sum(e.x for e in eyes) / len(eyes)
    else:
        r = head.w * 0.06
        ey = head.y + head.h * 0.42
        ex = head.cx
    width = max(r * 2.2, head.w * 0.16)
    height = max(width * 0.32, 4.0)
    if facing in ("left", "right") and eyes:
        tip = _snout_tip(image, facing, head, eyes[0])
        if tip:
            tx, ty = tip
            inward = width * 0.8 if facing == "left" else -width * 0.8
            cx = tx + inward
            # 입은 주둥이 아래쪽에 있다: 그 자리 세로 두께의 아래 1/3쯤.
            run = _run_at(image, cx, ty, top=eyes[0].y - eyes[0].r, bottom=head.bottom)
            cy = run[0] + (run[1] - run[0]) * 0.68 if run else max(ty, ey + r * 1.2)
        else:
            cx = ex - r * 2.5 if facing == "left" else ex + r * 2.5
            cy = ey + r * 2.2
    else:
        cx = ex
        below = max(r * 2.4, head.h * 0.2)
        cy = min(ey + below, head.bottom - height)
    spot = _nearest_opaque(image, cx, cy, (head.cx, head.cy))
    if spot:
        cx, cy = spot
    return Box(cx - width / 2, cy - height / 2, width, height)


def _cheeks_for(facing: Facing, eyes: list[Circle], mouth: Box) -> list[Circle]:
    if not eyes:
        return []
    r = sum(e.r for e in eyes) / len(eyes)
    cheeks = []
    for eye in eyes:
        if facing == "front" and len(eyes) == 2:
            outward = -1 if eye.x < mouth.cx else 1
            cheeks.append(
                Circle(eye.x + outward * r * 0.6, (eye.y + mouth.cy) / 2 + r * 0.6, r * 1.1)
            )
        else:
            cheeks.append(Circle((eye.x + mouth.cx) / 2, (eye.y + mouth.cy) / 2 + r * 0.8, r * 1.1))
    return cheeks


def estimate(image: Image.Image) -> FaceMap | None:
    """그림만 보고 얼굴 지도를 만든다. 그려진 것이 없으면 None."""
    box = drawn_box(image)
    if box is None:
        return None
    figure = Box(box[0], box[1], box[2] - box[0], box[3] - box[1])
    eyes = _pick_eyes(find_eyes(image))
    facing = _facing_from(eyes, figure)
    head = _head_around(eyes, figure, facing)
    mouth = _mouth_for(image, facing, head, eyes)
    head = (
        _clamp_box(
            _cover(head, [*((e.x, e.y, e.r) for e in eyes), (mouth.cx, mouth.cy, mouth.w / 2)]),
            figure,
        )
        or head
    )
    return FaceMap(
        width=image.width,
        height=image.height,
        facing=facing,
        head=head,
        eyes=tuple(eyes),
        mouth=mouth,
        cheeks=tuple(c for c in _cheeks_for(facing, eyes, mouth) if _opaque_at(image, c.x, c.y)),
        source="estimate",
    )


# ---------------------------------------------------------------------------
# 모델 답 고치기
# ---------------------------------------------------------------------------


def _numbers(value: Any, n: int) -> list[float] | None:
    if not isinstance(value, list | tuple) or len(value) != n:
        return None
    if not all(isinstance(v, int | float) and math.isfinite(v) for v in value):
        return None
    return [float(v) for v in value]


def parse(data: Any, width: int, height: int) -> FaceMap | None:
    """모델(또는 저장된) JSON을 읽는다. 모델이 다른 크기로 답했으면 그림 크기로 비례 변환한다."""
    if not isinstance(data, dict):
        return None
    size = _numbers(data.get("size"), 2)
    sx = width / size[0] if size and size[0] > 0 else 1.0
    sy = height / size[1] if size and size[1] > 0 else 1.0

    def circles(value: Any) -> tuple[Circle, ...]:
        found = []
        for item in value if isinstance(value, list) else []:
            n = _numbers(item, 3)
            if n and n[2] > 0:
                found.append(Circle(n[0] * sx, n[1] * sy, n[2] * (sx + sy) / 2))
        return tuple(found)

    head_n = _numbers(data.get("head"), 4)
    mouth_n = _numbers(data.get("mouth"), 4)
    facing = data.get("facing")
    return FaceMap(
        width=width,
        height=height,
        facing=facing if facing in ("left", "right", "front") else "front",
        head=Box(head_n[0] * sx, head_n[1] * sy, head_n[2] * sx, head_n[3] * sy)
        if head_n and head_n[2] > 0 and head_n[3] > 0
        else None,
        eyes=circles(data.get("eyes")),
        mouth=Box(
            mouth_n[0] * sx - mouth_n[2] * sx / 2,
            mouth_n[1] * sy - mouth_n[3] * sy / 2,
            mouth_n[2] * sx,
            mouth_n[3] * sy,
        )
        if mouth_n and mouth_n[2] > 0 and mouth_n[3] > 0
        else None,
        cheeks=circles(data.get("cheeks")),
        source=str(data.get("source") or "model"),
    )


def refine(proposed: FaceMap | None, image: Image.Image) -> FaceMap | None:
    """모델이 말한 얼굴 지도를 그림과 대조해 고친다. 쓸 것이 없으면 그림만 보고 추정한다."""
    guess = estimate(image)
    if guess is None:
        return None
    if proposed is None:
        return guess
    figure_box = drawn_box(image)
    assert figure_box is not None
    figure = Box(
        figure_box[0], figure_box[1], figure_box[2] - figure_box[0], figure_box[3] - figure_box[1]
    )
    notes: list[str] = []
    found = find_eyes(image)

    # 눈: 그려진 곳 위의 것만, 근처의 눈동자에 붙인다.
    eyes: list[Circle] = []
    for eye in proposed.eyes:
        near = [c for c in found if math.hypot(c.x - eye.x, c.y - eye.y) <= max(eye.r, c.r) * 2.2]
        if near:
            snap = min(near, key=lambda c: math.hypot(c.x - eye.x, c.y - eye.y))
            eyes.append(Circle(snap.x, snap.y, max(snap.r, min(eye.r, snap.r * 1.8))))
            notes.append("eye_snapped")
        elif _opaque_at(image, eye.x, eye.y):
            eyes.append(Circle(eye.x, eye.y, min(eye.r, figure.w * 0.12)))
        else:
            notes.append("eye_dropped")
    eyes = sorted({(round(e.x), round(e.y)): e for e in eyes}.values(), key=lambda e: e.x)
    if not eyes and guess.eyes:
        eyes = list(guess.eyes)
        notes.append("eyes_estimated")

    facing: Facing = proposed.facing
    if facing == "front" and len(eyes) == 1 and guess.facing != "front":
        facing = guess.facing
        notes.append("facing_from_eye")

    head = _clamp_box(proposed.head, figure) if proposed.head else None
    if head is None:
        head = _head_around(eyes, figure, facing)
        notes.append("head_estimated")

    mouth = proposed.mouth
    eye_y = sum(e.y for e in eyes) / len(eyes) if eyes else None
    if mouth is not None:
        bad = not _opaque_at(image, mouth.cx, mouth.cy)
        if eye_y is not None and mouth.cy < eye_y - (eyes[0].r if eyes else 0):
            bad = True  # 입이 눈보다 위
        if mouth.w > head.w * 0.8:
            mouth = Box(mouth.cx - head.w * 0.2, mouth.y, head.w * 0.4, mouth.h)
        if bad:
            spot = _nearest_opaque(image, mouth.cx, mouth.cy, (head.cx, head.cy))
            if spot and (eye_y is None or spot[1] >= eye_y):
                mouth = Box(spot[0] - mouth.w / 2, spot[1] - mouth.h / 2, mouth.w, mouth.h)
                notes.append("mouth_moved")
            else:
                mouth = None
    if mouth is None:
        mouth = _mouth_for(image, facing, head, eyes)
        notes.append("mouth_estimated")

    cheeks = [c for c in proposed.cheeks if _opaque_at(image, c.x, c.y)]
    if not cheeks:
        cheeks = [c for c in _cheeks_for(facing, eyes, mouth) if _opaque_at(image, c.x, c.y)]

    head = (
        _clamp_box(
            _cover(head, [*((e.x, e.y, e.r) for e in eyes), (mouth.cx, mouth.cy, mouth.w / 2)]),
            figure,
        )
        or head
    )
    return replace(
        proposed,
        width=image.width,
        height=image.height,
        facing=facing,
        head=head,
        eyes=tuple(eyes),
        mouth=mouth,
        cheeks=tuple(cheeks),
        source="model",
        notes=tuple(notes),
    )
