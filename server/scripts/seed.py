"""개발용 시드 데이터: 내 계정에 테스트용 친구를 만든다.

다른 사람의 기능이 아직 없어도 내 기능을 테스트할 수 있게 한다. 예) 대화(C)는 친구 저장(B)이
끝나기 전에 시드 친구로 개발한다.

    cd server
    python -m scripts.seed --email you@example.com            # 시드 친구 3명 만들기
    python -m scripts.seed --email you@example.com --clean    # 시드 친구만 지우기

- 계정은 **앱에서 Google로 한 번 로그인해서 만들어 둔 것**이어야 한다.
  (이 스크립트는 계정을 만들지 않는다.)
- `.env`에 `DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`가 있어야 한다.
- 시드 친구의 이미지는 코드로 만든 단색 PNG다. Storage 경로가 `{user_id}/seed/`로 시작해서
  `--clean`이 다른 친구를 건드리지 않고 시드 친구만 찾아 지운다.
- 이미 시드 친구가 있으면 다시 만들지 않는다 (여러 번 실행해도 안전하다).
"""

import argparse
import struct
import sys
import zlib
from collections.abc import Iterable
from dataclasses import dataclass
from uuid import UUID, uuid4

from app.assets import AssetRow
from app.config import get_settings
from app.db import Database, create_database
from app.errors import ApiError
from app.repositories.characters import CharacterRepository
from app.storage import StorageClient, StorageError, get_storage

SEED_FOLDER = "seed"


@dataclass(frozen=True)
class SeedFriend:
    name: str
    personality_type: str
    favorite_things: list[str]
    speech_style: str
    introduction: str
    rgb: tuple[int, int, int]


SEED_FRIENDS = [
    SeedFriend(
        "시드 구름이", "calm", ["구름", "낮잠"], "해요체", "개발용 시드 친구예요.", (142, 197, 255)
    ),
    SeedFriend(
        "시드 별이",
        "cheerful",
        ["노래", "산책"],
        "~지요!",
        "개발용 시드 친구지요!",
        (255, 209, 102),
    ),
    SeedFriend(
        "시드 도토리",
        "shy",
        ["사과", "친구랑 놀기"],
        "반말",
        "개발용 시드 친구야.",
        (176, 137, 104),
    ),
]


# ---------------------------------------------------------------------------
# 이미지: 외부 라이브러리 없이 PNG를 직접 만든다 (단색 배경, 투명 배경의 원)
# ---------------------------------------------------------------------------


def _png(width: int, height: int, rows: Iterable[bytes]) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    raw = b"".join(b"\x00" + row for row in rows)  # 각 줄 앞의 0은 필터 없음
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)  # 8비트 RGBA
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )


def solid_png(width: int, height: int, rgb: tuple[int, int, int]) -> bytes:
    return _png(width, height, [bytes((*rgb, 255)) * width] * height)


def disc_png(size: int, rgb: tuple[int, int, int]) -> bytes:
    """배경이 투명한 원. 생성된 캐릭터 아트(투명 PNG)를 흉내 낸다."""
    center, radius = (size - 1) / 2, size * 0.45
    opaque, clear = bytes((*rgb, 255)), bytes(4)
    rows = [
        b"".join(
            opaque if (x - center) ** 2 + (y - center) ** 2 <= radius**2 else clear
            for x in range(size)
        )
        for y in range(size)
    ]
    return _png(size, size, rows)


# ---------------------------------------------------------------------------
# 시드 만들기 / 지우기
# ---------------------------------------------------------------------------


def find_user_id(db: Database, email: str) -> UUID | None:
    with db.connection() as conn:
        row = conn.execute(
            "select id from auth.users where lower(email) = lower(%s)", (email,)
        ).fetchone()
    return row["id"] if row else None


def _seed_names(db: Database, user_id: UUID) -> set[str]:
    """이미 만들어 둔 시드 친구의 이름 (아트 이미지가 seed 폴더에 있는 친구)."""
    with db.connection() as conn:
        rows = conn.execute(
            "select f.name from public.friends f"
            " join public.assets a on a.id = f.art_asset_id"
            " where f.user_id = %(user_id)s and a.storage_path like %(pattern)s",
            {"user_id": user_id, "pattern": f"{user_id}/{SEED_FOLDER}/%"},
        ).fetchall()
    return {row["name"] for row in rows}


def _upload(storage: StorageClient, user_id: UUID, kind: str, png: bytes) -> tuple[str, bytes]:
    path = f"{user_id}/{SEED_FOLDER}/{uuid4()}-{kind}.png"
    storage.upload(path, png, "image/png")
    return path, png


def create_seed_friends(
    db: Database, storage: StorageClient, user_id: UUID, friends: list[SeedFriend]
) -> list[UUID]:
    """아직 없는 시드 친구만 만든다. 만든 친구의 ID를 돌려준다."""
    existing = _seed_names(db, user_id)
    created: list[UUID] = []
    for friend in friends:
        if friend.name in existing:
            continue
        images = {
            "source": (320, 240, solid_png(320, 240, (245, 245, 240))),
            "art": (256, 256, disc_png(256, friend.rgb)),
            "thumbnail": (64, 64, disc_png(64, friend.rgb)),
        }
        # 파일을 먼저 올린 뒤 한 트랜잭션으로 에셋과 친구를 넣는다.
        uploaded = {
            kind: (*_upload(storage, user_id, kind, png), width, height)
            for kind, (width, height, png) in images.items()
        }
        asset_ids: dict[str, UUID] = {}
        with db.connection() as conn:
            for kind, (path, png, width, height) in uploaded.items():
                asset_ids[kind] = conn.execute(
                    "insert into public.assets"
                    " (user_id, kind, storage_path, content_type, byte_size, width, height)"
                    " values (%s, %s, %s, 'image/png', %s, %s, %s) returning id",
                    (user_id, kind, path, len(png), width, height),
                ).fetchone()["id"]
            row = conn.execute(
                "insert into public.friends"
                " (user_id, name, personality_type, favorite_things, speech_style, introduction,"
                "  source_asset_id, art_asset_id, thumbnail_asset_id, accent_argb)"
                " values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s) returning id",
                (
                    user_id,
                    friend.name,
                    friend.personality_type,
                    friend.favorite_things,
                    friend.speech_style,
                    friend.introduction,
                    asset_ids["source"],
                    asset_ids["art"],
                    asset_ids["thumbnail"],
                    0xFF000000 | (friend.rgb[0] << 16) | (friend.rgb[1] << 8) | friend.rgb[2],
                ),
            ).fetchone()
        created.append(row["id"])
    return created


def clean_seed_friends(db: Database, storage: StorageClient, user_id: UUID) -> int:
    """시드 친구만 지운다. 지운 친구 수를 돌려준다. 삭제 순서는 DELETE API와 같다."""
    repo = CharacterRepository(db)
    with db.connection() as conn:
        rows = conn.execute(
            "select f.id from public.friends f"
            " join public.assets a on a.id = f.art_asset_id"
            " where f.user_id = %(user_id)s and a.storage_path like %(pattern)s",
            {"user_id": user_id, "pattern": f"{user_id}/{SEED_FOLDER}/%"},
        ).fetchall()
    for row in rows:
        assets: list[AssetRow] | None = repo.delete_for_user(user_id, row["id"])
        if assets:
            storage.remove([asset.storage_path for asset in assets])
            repo.delete_assets(user_id, [asset.id for asset in assets])
    return len(rows)


# ---------------------------------------------------------------------------
# 명령줄
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="개발용 시드 친구를 만들거나 지웁니다.")
    parser.add_argument("--email", required=True, help="앱에서 Google로 로그인해 둔 계정의 이메일")
    parser.add_argument("--clean", action="store_true", help="시드 친구만 지웁니다")
    parser.add_argument(
        "--count",
        type=int,
        default=len(SEED_FRIENDS),
        choices=range(1, len(SEED_FRIENDS) + 1),
        help="만들 시드 친구 수 (기본 3)",
    )
    args = parser.parse_args(argv)

    settings = get_settings()
    db = create_database(settings)
    if db is None:
        print("DATABASE_URL이 없습니다. server/.env를 확인하세요.", file=sys.stderr)
        return 1
    try:
        storage = get_storage(settings)
    except ApiError:  # SUPABASE_URL 또는 SUPABASE_SERVICE_ROLE_KEY가 없다 (503)
        print(
            "SUPABASE_URL 또는 SUPABASE_SERVICE_ROLE_KEY가 없습니다. server/.env를 확인하세요.",
            file=sys.stderr,
        )
        db.close()
        return 1

    try:
        user_id = find_user_id(db, args.email)
        if user_id is None:
            print(
                f"{args.email} 계정을 찾지 못했습니다. "
                "앱에서 Google로 한 번 로그인한 뒤 다시 실행하세요.",
                file=sys.stderr,
            )
            return 1
        if args.clean:
            print(f"시드 친구 {clean_seed_friends(db, storage, user_id)}명을 지웠습니다.")
        else:
            created = create_seed_friends(db, storage, user_id, SEED_FRIENDS[: args.count])
            print(f"시드 친구 {len(created)}명을 만들었습니다 (이미 있으면 건너뜁니다).")
            for character_id in created:
                print(f"  {character_id}")
        return 0
    except StorageError as exc:
        print(f"Storage 작업에 실패했습니다: {exc}", file=sys.stderr)
        return 1
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
