"""대화 메시지 저장과 조회 (FR-09).

모든 쿼리는 ``user_id``와 ``character_id``를 함께 조건으로 사용한다. 사용자 메시지의
``client_message_id``는 같은 요청을 한 번만 저장하고, 답변의 ``reply_to_id``는 한 사용자
메시지에 답변 하나만 저장하게 한다.
"""

from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import Depends

from app.ai_chat import CharacterChatProfile, ConversationMessage, ReplySource
from app.db import Database, DatabaseDep
from app.idempotency import fingerprint, idempotency_conflict, insert_or_replay

MessageRole = Literal["user", "assistant"]


@dataclass(frozen=True)
class MessageRecord:
    id: UUID
    role: MessageRole
    text: str
    source: ReplySource | None
    created_at: datetime


@dataclass(frozen=True)
class MessagePage:
    items: list[MessageRecord]
    has_more: bool


def _record(row: dict) -> MessageRecord:
    return MessageRecord(
        id=row["id"],
        role=row["role"],
        text=row["text"],
        source=row["source"],
        created_at=row["created_at"].astimezone(UTC),
    )


def _profile(row: dict) -> CharacterChatProfile:
    return CharacterChatProfile(
        name=row["name"],
        personality_type=row["personality_type"],
        favorite_things=tuple(row["favorite_things"]),
        speech_style=row["speech_style"],
        introduction=row["introduction"],
    )


class MessageRepository:
    def __init__(self, db: Database) -> None:
        self._db = db

    def get_friend_profile(self, user_id: UUID, character_id: UUID) -> CharacterChatProfile | None:
        with self._db.connection() as conn:
            row = conn.execute(
                "select name, personality_type, favorite_things, speech_style, introduction"
                " from public.friends where id = %(character_id)s and user_id = %(user_id)s",
                {"user_id": user_id, "character_id": character_id},
            ).fetchone()
        return _profile(row) if row else None

    def start_user_message(
        self,
        user_id: UUID,
        character_id: UUID,
        client_message_id: str,
        text: str,
    ) -> tuple[MessageRecord, bool] | None:
        """사용자 메시지를 원자적으로 만들거나 같은 요청의 기존 행을 돌려준다."""
        with self._db.connection() as conn:
            owned = conn.execute(
                "select 1 from public.friends"
                " where id = %(character_id)s and user_id = %(user_id)s",
                {"user_id": user_id, "character_id": character_id},
            ).fetchone()
            if owned is None:
                return None
            row, created = insert_or_replay(
                conn,
                table="public.messages",
                values={
                    "user_id": user_id,
                    "character_id": character_id,
                    "role": "user",
                    "text": text,
                    "client_message_id": client_message_id,
                },
                unique_columns=("character_id", "client_message_id"),
                request_fingerprint=fingerprint({"text": text}),
            )
        return _record(row), created

    def get_user_message_by_client_id(
        self,
        user_id: UUID,
        character_id: UUID,
        client_message_id: str,
        text: str,
    ) -> MessageRecord | None:
        """기존 요청을 찾고, 같은 키의 내용이 달라졌으면 409를 낸다."""
        with self._db.connection() as conn:
            row = conn.execute(
                "select id, role, text, source, created_at, request_fingerprint"
                " from public.messages"
                " where user_id = %(user_id)s and character_id = %(character_id)s"
                " and role = 'user' and client_message_id = %(client_message_id)s",
                {
                    "user_id": user_id,
                    "character_id": character_id,
                    "client_message_id": client_message_id,
                },
            ).fetchone()
        if row is None:
            return None
        if row["request_fingerprint"] != fingerprint({"text": text}):
            raise idempotency_conflict()
        return _record(row)

    def get_reply(
        self, user_id: UUID, character_id: UUID, user_message_id: UUID
    ) -> MessageRecord | None:
        with self._db.connection() as conn:
            row = conn.execute(
                "select id, role, text, source, created_at from public.messages"
                " where user_id = %(user_id)s and character_id = %(character_id)s"
                " and role = 'assistant' and reply_to_id = %(user_message_id)s",
                {
                    "user_id": user_id,
                    "character_id": character_id,
                    "user_message_id": user_message_id,
                },
            ).fetchone()
        return _record(row) if row else None

    def save_reply(
        self,
        user_id: UUID,
        character_id: UUID,
        user_message_id: UUID,
        text: str,
        source: ReplySource,
    ) -> MessageRecord | None:
        """답변을 한 번만 저장한다. 동시에 저장되면 먼저 저장된 답변을 돌려준다."""
        params = {
            "user_id": user_id,
            "character_id": character_id,
            "user_message_id": user_message_id,
            "text": text,
            "source": source,
        }
        with self._db.connection() as conn:
            row = conn.execute(
                "insert into public.messages"
                " (user_id, character_id, role, text, source, reply_to_id)"
                " select %(user_id)s, %(character_id)s, 'assistant', %(text)s, %(source)s, m.id"
                " from public.messages m"
                " where m.id = %(user_message_id)s and m.user_id = %(user_id)s"
                " and m.character_id = %(character_id)s and m.role = 'user'"
                " on conflict (reply_to_id) do nothing"
                " returning id, role, text, source, created_at",
                params,
            ).fetchone()
            if row is None:
                row = conn.execute(
                    "select id, role, text, source, created_at from public.messages"
                    " where user_id = %(user_id)s and character_id = %(character_id)s"
                    " and role = 'assistant' and reply_to_id = %(user_message_id)s",
                    params,
                ).fetchone()
        return _record(row) if row else None

    def recent_context(
        self, user_id: UUID, character_id: UUID, before: MessageRecord, limit: int = 20
    ) -> list[ConversationMessage]:
        params = {
            "user_id": user_id,
            "character_id": character_id,
            "created_at": before.created_at,
            "message_id": before.id,
            "limit": limit,
        }
        with self._db.connection() as conn:
            rows = conn.execute(
                "select role, text from public.messages"
                " where user_id = %(user_id)s and character_id = %(character_id)s"
                " and (created_at, id) < (%(created_at)s, %(message_id)s)"
                " order by created_at desc, id desc limit %(limit)s",
                params,
            ).fetchall()
        return [ConversationMessage(role=row["role"], text=row["text"]) for row in reversed(rows)]

    def list_messages(
        self,
        user_id: UUID,
        character_id: UUID,
        *,
        limit: int,
        before_created_at: datetime | None = None,
        before_id: UUID | None = None,
    ) -> MessagePage | None:
        params = {
            "user_id": user_id,
            "character_id": character_id,
            "limit": limit + 1,
            "before_created_at": before_created_at,
            "before_id": before_id,
        }
        before_sql = ""
        if before_created_at is not None and before_id is not None:
            before_sql = " and (m.created_at, m.id) < (%(before_created_at)s, %(before_id)s)"
        with self._db.connection() as conn:
            owned = conn.execute(
                "select 1 from public.friends"
                " where id = %(character_id)s and user_id = %(user_id)s",
                params,
            ).fetchone()
            if owned is None:
                return None
            rows = conn.execute(
                "select m.id, m.role, m.text, m.source, m.created_at"
                " from public.messages m"
                " where m.user_id = %(user_id)s and m.character_id = %(character_id)s"
                + before_sql
                + " order by m.created_at desc, m.id desc limit %(limit)s",
                params,
            ).fetchall()
        return MessagePage(items=[_record(row) for row in rows[:limit]], has_more=len(rows) > limit)


def get_message_repository(db: DatabaseDep) -> MessageRepository:
    return MessageRepository(db)


MessageRepositoryDep = Annotated[MessageRepository, Depends(get_message_repository)]
