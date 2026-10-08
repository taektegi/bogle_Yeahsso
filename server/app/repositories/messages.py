"""친구의 집 대화 기록(`public.chat_messages`).

아이의 메시지 하나와 친구의 답 하나가 같은 `client_message_id`로 한 쌍이 된다. 같은 ID로 다시
보내면(재전송) 새로 쓰지 않고 이전 쌍을 돌려준다. 내용이 다르면 409.
"""

import base64
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Annotated, Any
from uuid import UUID

from fastapi import Depends

from app.db import Database, DatabaseDep
from app.errors import ApiError
from app.idempotency import idempotency_conflict


@dataclass(frozen=True)
class MessageRecord:
    id: UUID
    role: str
    text: str
    source: str | None
    created_at: datetime


@dataclass(frozen=True)
class Pair:
    user: MessageRecord
    assistant: MessageRecord


def _record(row: dict[str, Any]) -> MessageRecord:
    return MessageRecord(
        id=row["id"],
        role=row["role"],
        text=row["text"],
        source=row["source"],
        created_at=row["created_at"].astimezone(UTC),
    )


def _cursor(record: MessageRecord) -> str:
    raw = f"{record.created_at.isoformat()}|{record.id}"
    return base64.urlsafe_b64encode(raw.encode()).decode().rstrip("=")


def _parse_cursor(cursor: str) -> tuple[datetime, UUID]:
    try:
        padded = cursor + "=" * (-len(cursor) % 4)
        when, ident = base64.urlsafe_b64decode(padded).decode().split("|")
        return datetime.fromisoformat(when), UUID(ident)
    except (ValueError, UnicodeDecodeError):
        raise ApiError(
            422,
            "validation_error",
            "입력값을 확인해 주세요.",
            field_errors={"before": "invalid_cursor"},
        ) from None


class MessageRepository:
    def __init__(self, db: Database) -> None:
        self._db = db

    def find_pair(
        self, user_id: UUID, character_id: UUID, client_message_id: str, fingerprint: str
    ) -> Pair | None:
        """같은 ID로 이미 주고받은 쌍. 내용이 다르면 409 `idempotency_key_conflict`."""
        with self._db.connection() as conn:
            rows = conn.execute(
                "select * from public.chat_messages where user_id = %(user_id)s"
                " and character_id = %(character_id)s and client_message_id = %(cid)s",
                {"user_id": user_id, "character_id": character_id, "cid": client_message_id},
            ).fetchall()
        return self._pair(rows, fingerprint)

    @staticmethod
    def _pair(rows: list[dict[str, Any]], fingerprint: str) -> Pair | None:
        by_role = {row["role"]: row for row in rows}
        if "user" not in by_role:
            return None
        if by_role["user"]["request_fingerprint"] != fingerprint:
            raise idempotency_conflict()
        if "assistant" not in by_role:
            return None
        return Pair(_record(by_role["user"]), _record(by_role["assistant"]))

    def save_pair(
        self,
        user_id: UUID,
        character_id: UUID,
        *,
        client_message_id: str,
        fingerprint: str,
        text: str,
        reply: str,
        source: str,
    ) -> Pair:
        """한 쌍을 저장한다. 같은 ID가 동시에 저장되면 먼저 저장된 쌍을 돌려준다."""
        values = {
            "user_id": user_id,
            "character_id": character_id,
            "cid": client_message_id,
            "fp": fingerprint,
        }
        with self._db.connection() as conn:
            inserted = conn.execute(
                "insert into public.chat_messages"
                " (user_id, character_id, client_message_id, role, text, request_fingerprint)"
                " values (%(user_id)s, %(character_id)s, %(cid)s, 'user', %(text)s, %(fp)s)"
                " on conflict (character_id, client_message_id, role) do nothing returning id",
                {**values, "text": text},
            ).fetchone()
            if inserted is not None:
                # 친구의 답은 아이의 말보다 늦은 시각으로 남겨 순서가 뒤바뀌지 않게 한다.
                conn.execute(
                    "insert into public.chat_messages"
                    " (user_id, character_id, client_message_id, role, text, source,"
                    "  request_fingerprint, created_at)"
                    " values (%(user_id)s, %(character_id)s, %(cid)s, 'assistant', %(reply)s,"
                    "  %(source)s, %(fp)s, clock_timestamp() + interval '1 millisecond')",
                    {**values, "reply": reply, "source": source},
                )
            rows = conn.execute(
                "select * from public.chat_messages where user_id = %(user_id)s"
                " and character_id = %(character_id)s and client_message_id = %(cid)s",
                values,
            ).fetchall()
        pair = self._pair(rows, fingerprint)
        assert pair is not None
        return pair

    def recent(self, user_id: UUID, character_id: UUID, limit: int = 20) -> list[MessageRecord]:
        """AI 문맥용 최근 메시지 (오래된 것부터)."""
        with self._db.connection() as conn:
            rows = conn.execute(
                "select * from public.chat_messages where user_id = %(user_id)s"
                " and character_id = %(character_id)s"
                " order by created_at desc, id desc limit %(limit)s",
                {"user_id": user_id, "character_id": character_id, "limit": limit},
            ).fetchall()
        return [_record(row) for row in reversed(rows)]

    def page(
        self, user_id: UUID, character_id: UUID, *, before: str | None, limit: int
    ) -> tuple[list[MessageRecord], str | None]:
        """최신순 한 페이지와 다음 페이지 커서 (더 없으면 None)."""
        params: dict[str, Any] = {
            "user_id": user_id,
            "character_id": character_id,
            "limit": limit + 1,
        }
        condition = ""
        if before:
            when, ident = _parse_cursor(before)
            condition = " and (created_at, id) < (%(when)s, %(ident)s)"
            params.update(when=when, ident=ident)
        with self._db.connection() as conn:
            rows = conn.execute(
                "select * from public.chat_messages where user_id = %(user_id)s"
                " and character_id = %(character_id)s"
                + condition
                + " order by created_at desc, id desc limit %(limit)s",
                params,
            ).fetchall()
        records = [_record(row) for row in rows[:limit]]
        more = len(rows) > limit
        return records, _cursor(records[-1]) if more and records else None


def get_message_repository(db: DatabaseDep) -> MessageRepository:
    return MessageRepository(db)


MessageRepositoryDep = Annotated[MessageRepository, Depends(get_message_repository)]
