"""생성·대화 테스트용 가짜 AI와 그림."""

import io
from dataclasses import dataclass, field

from PIL import Image, ImageDraw

from app.ai import AiError, AiServices, FriendBrief, Turn

# 정면 캐릭터: 600×600 투명 바탕에 파란 몸, 두 눈(검정), 입(진한 분홍)
FRONT_EYES = ((240, 250, 16), (360, 250, 16))
FRONT_MOUTH = (300, 330)


def front_character(background: tuple[int, int, int] | None = None) -> Image.Image:
    image = Image.new("RGBA", (600, 600), (*background, 255) if background else (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.ellipse((150, 120, 450, 520), fill=(140, 180, 245, 255))
    for x, y, r in FRONT_EYES:
        draw.ellipse((x - r, y - r, x + r, y + r), fill=(20, 20, 30, 255))
        draw.ellipse((x - 5, y - 9, x + 1, y - 3), fill=(255, 255, 255, 255))
    x, y = FRONT_MOUTH
    draw.chord((x - 24, y - 14, x + 24, y + 14), 0, 180, fill=(210, 90, 120, 255))
    return image


# 옆모습(왼쪽을 봄): 긴 몸과 왼쪽으로 튀어나온 주둥이, 눈 하나
SIDE_EYE = (210, 230, 14)


def side_character() -> Image.Image:
    image = Image.new("RGBA", (900, 500), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.ellipse((250, 150, 820, 430), fill=(240, 170, 80, 255))  # 몸
    draw.ellipse((80, 190, 330, 330), fill=(250, 220, 140, 255))  # 머리와 주둥이
    x, y, r = SIDE_EYE
    draw.ellipse((x - r, y - r, x + r, y + r), fill=(40, 25, 10, 255))
    for i in range(4):
        draw.ellipse((330 + i * 120, 400, 400 + i * 120, 460), fill=(110, 70, 30, 255))  # 발
    return image


def png(image: Image.Image) -> bytes:
    out = io.BytesIO()
    image.save(out, format="PNG")
    return out.getvalue()


def jpeg(image: Image.Image) -> bytes:
    out = io.BytesIO()
    image.convert("RGB").save(out, format="JPEG", quality=90)
    return out.getvalue()


def child_drawing() -> bytes:
    """그림판에서 내보낸 것처럼: 투명 바탕에 선과 색칠."""
    image = Image.new("RGBA", (1200, 800), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.ellipse((450, 250, 750, 600), outline=(40, 40, 40, 255), width=8, fill=(255, 200, 80, 255))
    draw.ellipse((540, 360, 570, 390), fill=(0, 0, 0, 255))
    draw.ellipse((630, 360, 660, 390), fill=(0, 0, 0, 255))
    return png(image)


@dataclass
class FakeArtist:
    """정해진 그림을 돌려주거나, 정해진 오류를 차례로 낸다."""

    result: bytes = field(default_factory=lambda: png(front_character((250, 250, 245))))
    errors: list[AiError] = field(default_factory=list)
    calls: int = 0

    def draw(self, page_png: bytes, *, source_type: str, timeout: float) -> bytes:
        self.calls += 1
        if self.errors:
            raise self.errors.pop(0)
        return self.result


@dataclass
class FakeLocator:
    answer: dict | None = None
    error: AiError | None = None

    def locate(self, art_png: bytes, *, width: int, height: int, timeout: float) -> dict | None:
        if self.error:
            raise self.error
        return self.answer


@dataclass
class FakeWriter:
    intro: str = "구름 위에서 놀다 왔어요!"
    answer: str = "구름 구경했지요!"
    error: AiError | None = None
    seen: list[list[Turn]] = field(default_factory=list)

    def introduction(self, friend: FriendBrief, *, timeout: float) -> str:
        if self.error:
            raise self.error
        return self.intro

    def reply(self, friend: FriendBrief, history, text: str, *, timeout: float) -> str:
        if self.error:
            raise self.error
        self.seen.append(list(history))
        return self.answer


@dataclass
class FakeModerator:
    banned: tuple[str, ...] = ()
    flag_images: bool = False

    def flagged(self, *, text=None, image_png=None, timeout: float) -> bool:
        if image_png is not None and self.flag_images:
            return True
        return bool(text) and any(word in text for word in self.banned)


def fake_ai(
    artist: FakeArtist | None = None,
    locator: FakeLocator | None = None,
    writer: FakeWriter | None = None,
    moderator: FakeModerator | None = None,
) -> AiServices:
    return AiServices(
        artist=artist or FakeArtist(),
        locator=locator,
        writer=writer,
        moderator=moderator,
    )
