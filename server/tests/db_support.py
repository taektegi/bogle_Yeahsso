"""DB 테스트에서 사용자·에셋·친구를 만드는 도우미."""

from collections.abc import Callable, Sequence
from datetime import datetime
from uuid import UUID, uuid4

import psycopg

from app.storage import SignedUrl, StorageError

SIGNED_UNTIL = datetime.fromisoformat("2026-10-05T06:00:00+00:00")


class FakeStorage:
    """Storage 서명을 흉내 낸다. 어떤 경로들로 호출됐는지 기록한다."""

    def __init__(self, fail: bool = False, fail_remove: bool = False) -> None:
        self.fail = fail
        self.fail_remove = fail_remove
        self.calls: list[list[str]] = []
        self.removed: list[list[str]] = []
        # remove()가 호출되는 순간에 실행할 검사 (호출 순서를 확인할 때 쓴다)
        self.on_remove: Callable[[], None] | None = None

    def sign(self, paths: Sequence[str]) -> dict[str, SignedUrl]:
        self.calls.append(list(paths))
        if self.fail:
            raise StorageError("storage is down")
        return {
            p: SignedUrl(f"https://storage.test/signed/{p}?token=t", SIGNED_UNTIL) for p in paths
        }

    def remove(self, paths: Sequence[str]) -> None:
        if self.on_remove:
            self.on_remove()
        if self.fail_remove:
            raise StorageError("storage is down")
        self.removed.append(list(paths))


def make_user(conn: psycopg.Connection) -> UUID:
    user_id = uuid4()
    conn.execute("insert into auth.users (id, email) values (%s, %s)", (user_id, f"{user_id}@test"))
    return user_id


def make_asset(conn: psycopg.Connection, user_id: UUID, kind: str) -> tuple[UUID, str]:
    asset_id = uuid4()
    extension = "jpg" if kind == "source" else "png"
    path = f"{user_id}/{asset_id}.{extension}"
    content_type = "image/jpeg" if kind == "source" else "image/png"
    conn.execute(
        "insert into public.assets "
        "(id, user_id, kind, storage_path, content_type, byte_size, width, height) "
        "values (%s, %s, %s, %s, %s, 1000, 640, 480)",
        (asset_id, user_id, kind, path, content_type),
    )
    return asset_id, path


def make_character(
    conn: psycopg.Connection,
    user_id: UUID,
    name: str,
    *,
    created_at: str | None = None,
    with_source: bool = True,
    personality_type: str = "calm",
    character_id: UUID | None = None,
) -> UUID:
    """친구 한 명과 그에 딸린 에셋(원본·아트·썸네일)을 만든다."""
    character_id = character_id or uuid4()
    source_id = make_asset(conn, user_id, "source")[0] if with_source else None
    art_id = make_asset(conn, user_id, "art")[0]
    thumbnail_id = make_asset(conn, user_id, "thumbnail")[0]
    conn.execute(
        "insert into public.friends "
        "(id, user_id, name, personality_type, favorite_things, speech_style, introduction, "
        " source_asset_id, art_asset_id, thumbnail_asset_id, accent_argb, created_at) "
        "values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, coalesce(%s::timestamptz, now()))",
        (
            character_id,
            user_id,
            name,
            personality_type,
            ["사과", "산책"],
            "해요체",
            f"{name}의 소개",
            source_id,
            art_id,
            thumbnail_id,
            4289974783,
            created_at,
        ),
    )
    return character_id
