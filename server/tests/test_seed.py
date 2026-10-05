"""시드 스크립트(scripts/seed.py). 실제 PostgreSQL과 가짜 Storage로 확인한다."""

import struct
import zlib

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.db import Database, get_database
from app.storage import get_storage
from scripts import seed
from tests.db_support import FakeStorage, make_character, make_user
from tests.tokens import bearer, hs256_token

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def decode_png(data: bytes) -> tuple[int, int, list[bytes]]:
    """우리가 만든 RGBA PNG를 읽어 (너비, 높이, 줄별 픽셀 바이트)를 돌려준다."""
    assert data.startswith(PNG_SIGNATURE)
    pos, idat, width, height = len(PNG_SIGNATURE), b"", 0, 0
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        kind = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + length]
        (crc,) = struct.unpack(">I", data[pos + 8 + length : pos + 12 + length])
        assert crc == zlib.crc32(kind + body), f"bad CRC in {kind!r}"
        if kind == b"IHDR":
            width, height = struct.unpack(">II", body[:8])
            assert body[8:10] == bytes([8, 6])  # 8비트 RGBA
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    raw = zlib.decompress(idat)
    stride = 1 + width * 4
    assert len(raw) == height * stride
    return width, height, [raw[y * stride + 1 : (y + 1) * stride] for y in range(height)]


def pixel(rows: list[bytes], x: int, y: int) -> tuple[int, int, int, int]:
    return tuple(rows[y][x * 4 : x * 4 + 4])


def test_solid_png_is_a_valid_image() -> None:
    width, height, rows = decode_png(seed.solid_png(8, 5, (10, 20, 30)))

    assert (width, height) == (8, 5)
    assert pixel(rows, 0, 0) == (10, 20, 30, 255)
    assert pixel(rows, 7, 4) == (10, 20, 30, 255)


def test_disc_png_is_transparent_outside_the_circle() -> None:
    width, height, rows = decode_png(seed.disc_png(32, (1, 2, 3)))

    assert (width, height) == (32, 32)
    assert pixel(rows, 0, 0)[3] == 0  # 모서리는 투명
    assert pixel(rows, 16, 16) == (1, 2, 3, 255)  # 가운데는 불투명


@pytest.fixture
def storage() -> FakeStorage:
    return FakeStorage()


@pytest.fixture
def api(app, client: TestClient, database: Database, storage: FakeStorage) -> TestClient:
    app.dependency_overrides[get_database] = lambda: database
    app.dependency_overrides[get_storage] = lambda: storage
    return client


def count_friends(conn, user_id) -> int:
    return conn.execute(
        "select count(*) as n from public.friends where user_id = %s", (user_id,)
    ).fetchone()["n"]


def test_find_user_id_by_email_is_case_insensitive(database, seed_conn) -> None:
    user = make_user(seed_conn)
    email = f"{user}@test"

    assert seed.find_user_id(database, email.upper()) == user
    assert seed.find_user_id(database, "nobody@test") is None


def test_seed_creates_friends_with_valid_assets(database, seed_conn, storage) -> None:
    user = make_user(seed_conn)

    created = seed.create_seed_friends(database, storage, user, seed.SEED_FRIENDS)

    assert len(created) == 3
    assert len(storage.uploaded) == 9  # 친구마다 원본·아트·썸네일
    assets = seed_conn.execute(
        "select storage_path, byte_size, width, height, content_type from public.assets"
        " where user_id = %s",
        (user,),
    ).fetchall()
    assert len(assets) == 9
    for asset in assets:
        assert asset["storage_path"].startswith(f"{user}/seed/")
        data, content_type = storage.uploaded[asset["storage_path"]]
        assert content_type == asset["content_type"] == "image/png"
        assert len(data) == asset["byte_size"]
        width, height, _ = decode_png(data)
        assert (width, height) == (asset["width"], asset["height"])


def test_seed_friends_show_up_in_the_api(api, seed_conn, storage) -> None:
    user = make_user(seed_conn)
    seed.create_seed_friends(
        api.app.dependency_overrides[get_database](), storage, user, seed.SEED_FRIENDS
    )

    response = api.get("/v1/characters", headers=bearer(hs256_token(sub=str(user))))

    assert response.status_code == 200
    items = response.json()["items"]
    assert sorted(c["name"] for c in items) == sorted(f.name for f in seed.SEED_FRIENDS)
    for character in items:
        assert character["art"]["width"] == 256
        assert 0 <= character["accentArgb"] <= 4294967295
        assert character["personalityLabel"] != character["personalityType"]  # 목록에 있는 유형


def test_seeding_twice_creates_nothing_new(database, seed_conn, storage) -> None:
    user = make_user(seed_conn)
    seed.create_seed_friends(database, storage, user, seed.SEED_FRIENDS)

    again = seed.create_seed_friends(database, storage, user, seed.SEED_FRIENDS)

    assert again == []
    assert count_friends(seed_conn, user) == 3
    assert len(storage.uploaded) == 9


def test_seeding_fewer_friends_then_more_adds_only_the_missing_ones(
    database, seed_conn, storage
) -> None:
    user = make_user(seed_conn)
    seed.create_seed_friends(database, storage, user, seed.SEED_FRIENDS[:1])

    created = seed.create_seed_friends(database, storage, user, seed.SEED_FRIENDS)

    assert len(created) == 2
    assert count_friends(seed_conn, user) == 3


def test_clean_removes_only_seed_friends(database, seed_conn, storage) -> None:
    user = make_user(seed_conn)
    real = make_character(seed_conn, user, "진짜 친구")
    seed.create_seed_friends(database, storage, user, seed.SEED_FRIENDS)

    removed = seed.clean_seed_friends(database, storage, user)

    assert removed == 3
    remaining = seed_conn.execute(
        "select id from public.friends where user_id = %s", (user,)
    ).fetchall()
    assert [r["id"] for r in remaining] == [real]
    # 시드 에셋은 파일과 행이 모두 사라지고, 진짜 친구의 에셋 3개만 남는다.
    assets = seed_conn.execute(
        "select storage_path from public.assets where user_id = %s", (user,)
    ).fetchall()
    assert len(assets) == 3
    assert not any("/seed/" in a["storage_path"] for a in assets)
    assert sum(len(paths) for paths in storage.removed) == 9


def test_clean_does_not_touch_other_users(database, seed_conn, storage) -> None:
    me, other = make_user(seed_conn), make_user(seed_conn)
    seed.create_seed_friends(database, storage, me, seed.SEED_FRIENDS)
    seed.create_seed_friends(database, storage, other, seed.SEED_FRIENDS)

    seed.clean_seed_friends(database, storage, me)

    assert count_friends(seed_conn, me) == 0
    assert count_friends(seed_conn, other) == 3


def test_clean_then_seed_again_works(database, seed_conn, storage) -> None:
    user = make_user(seed_conn)
    seed.create_seed_friends(database, storage, user, seed.SEED_FRIENDS)
    seed.clean_seed_friends(database, storage, user)

    created = seed.create_seed_friends(database, storage, user, seed.SEED_FRIENDS)

    assert len(created) == 3


def test_cli_explains_missing_configuration(capsys, monkeypatch) -> None:
    # 개발자의 server/.env(로컬 Supabase 값)가 있어도 "설정 없음" 상황을 그대로 재현한다.
    monkeypatch.setattr("scripts.seed.get_settings", lambda: Settings(_env_file=None))
    monkeypatch.delenv("DATABASE_URL", raising=False)
    assert seed.main(["--email", "someone@example.com"]) == 1
    assert "DATABASE_URL" in capsys.readouterr().err


def test_cli_rejects_a_bad_count() -> None:
    with pytest.raises(SystemExit):
        seed.main(["--email", "someone@example.com", "--count", "9"])
