"""친구와 대화 전송·기록 조회 API (FR-09)."""

import base64
import json
import time
from datetime import UTC, datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from pydantic import Field, field_validator

from app.ai_chat import ChatAiDep, ChatReply, script_reply
from app.auth import CurrentUserDep
from app.clock import NowDep
from app.config import Settings, get_settings
from app.errors import ERROR_RESPONSES, ApiError
from app.idempotency import IdempotencyKey
from app.rate_limit import limit_messages
from app.repositories.messages import MessageRecord, MessageRepository, MessageRepositoryDep
from app.schemas import CamelModel
from app.sleep import sleep_status

router = APIRouter(prefix="/characters", tags=["chat"], responses=ERROR_RESPONSES)
_REPLY_POLL_INTERVAL_SECONDS = 0.2
# AI 처리 한도는 늘리지 않고, 완료한 답을 DB에 저장할 짧은 여유만 둔다.
_REPLY_SAVE_GRACE_SECONDS = 1.0


class MessageIn(CamelModel):
    client_message_id: IdempotencyKey
    text: str = Field(min_length=1, max_length=200)

    @field_validator("text", mode="before")
    @classmethod
    def normalize_text(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value


class MessageOut(CamelModel):
    id: UUID
    role: str
    text: str
    source: str | None = None
    created_at: datetime


class MessagePairOut(CamelModel):
    user_message: MessageOut
    assistant_message: MessageOut


class MessagePageOut(CamelModel):
    items: list[MessageOut]
    next_cursor: str | None = None


def _out(message: MessageRecord) -> MessageOut:
    return MessageOut(
        id=message.id,
        role=message.role,
        text=message.text,
        source=message.source,
        created_at=message.created_at,
    )


def _encode_cursor(message: MessageRecord) -> str:
    raw = json.dumps(
        {"createdAt": message.created_at.isoformat(), "id": str(message.id)},
        separators=(",", ":"),
    ).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def _decode_cursor(cursor: str) -> tuple[datetime, UUID]:
    try:
        padding = "=" * (-len(cursor) % 4)
        data = json.loads(base64.urlsafe_b64decode(cursor + padding))
        created_at = datetime.fromisoformat(data["createdAt"])
        if created_at.tzinfo is None:
            raise ValueError
        return created_at.astimezone(UTC), UUID(data["id"])
    except (KeyError, TypeError, ValueError, json.JSONDecodeError):
        raise ApiError(
            422,
            "validation_error",
            "입력값을 확인해 주세요.",
            field_errors={"before": "invalid_cursor"},
        ) from None


def _not_found() -> ApiError:
    return ApiError(404, "not_found", "친구를 찾을 수 없어요.")


def _wait_for_reply(
    repo: MessageRepository,
    user_id: UUID,
    character_id: UUID,
    user_message: MessageRecord,
    deadline: float,
) -> MessageRecord | None:
    """이미 진행 중인 요청의 답을 기다리고, 제한 시간이 지나면 None을 반환한다."""
    while True:
        reply = repo.get_reply(user_id, character_id, user_message.id)
        if reply is not None:
            return reply
        remaining_seconds = deadline - time.monotonic()
        if remaining_seconds <= 0:
            return None
        time.sleep(min(_REPLY_POLL_INTERVAL_SECONDS, remaining_seconds))


@router.post(
    "/{character_id}/messages",
    response_model=MessagePairOut,
    response_model_exclude_none=True,
    dependencies=[Depends(limit_messages)],
    summary="대화 보내기",
)
def send_message(
    character_id: UUID,
    body: MessageIn,
    user: CurrentUserDep,
    repo: MessageRepositoryDep,
    chat: ChatAiDep,
    now: NowDep,
    settings: Annotated[Settings, Depends(get_settings)],
) -> MessagePairOut:
    """AI가 답한다. 검열에 걸리거나 AI가 실패·15초 초과면 스크립트 대사로 답한다 (오류 아님).

    같은 ``clientMessageId``로 다시 보내면 이전 답을 그대로 돌려준다. 자는 시간에는 409.
    """
    started_at = time.monotonic()
    profile = repo.get_friend_profile(user.id, character_id)
    if profile is None:
        raise _not_found()
    user_message = repo.get_user_message_by_client_id(
        user.id, character_id, body.client_message_id, body.text
    )
    created = False
    if user_message is None:
        if sleep_status(now).asleep:
            raise ApiError(409, "character_asleep", "친구가 지금 자고 있어요. 깨어나면 이야기해요.")
        started = repo.start_user_message(user.id, character_id, body.client_message_id, body.text)
        if started is None:
            raise _not_found()
        user_message, created = started

    # 기록 조회 시간도 포함한 동일한 한도를 원래 요청과 재전송에서 사용한다.
    age_seconds = max(0.0, (now - user_message.created_at).total_seconds())
    deadline = started_at + settings.chat_ai_timeout_seconds - age_seconds
    assistant = repo.get_reply(user.id, character_id, user_message.id)
    if assistant is None:
        if created:
            reply = chat.reply(
                friend=profile,
                history=repo.recent_context(user.id, character_id, user_message),
                user_text=body.text,
                deadline=deadline,
            )
        else:
            # AI 호출 중인 첫 요청이 답을 저장할 때까지 기다린다.
            assistant = _wait_for_reply(
                repo, user.id, character_id, user_message, deadline + _REPLY_SAVE_GRACE_SECONDS
            )
            reply = None
        if assistant is None:
            # 첫 요청이 중단됐거나 답변 제한 시간을 넘긴 경우에만 스크립트로 복구한다.
            if reply is None:
                reply = ChatReply(text=script_reply(profile, body.text), source="script")
            assistant = repo.save_reply(
                user.id,
                character_id,
                user_message.id,
                reply.text,
                reply.source,
            )
    if assistant is None:
        raise _not_found()
    return MessagePairOut(user_message=_out(user_message), assistant_message=_out(assistant))


@router.get(
    "/{character_id}/messages",
    response_model=MessagePageOut,
    summary="이전 대화",
)
def list_messages(
    character_id: UUID,
    user: CurrentUserDep,
    repo: MessageRepositoryDep,
    limit: int = Query(30, ge=1, le=100),
    before: str | None = Query(None),
) -> MessagePageOut:
    """최신순. 다음 페이지는 ``before=<nextCursor>``."""
    before_at, before_id = _decode_cursor(before) if before else (None, None)
    page = repo.list_messages(
        user.id,
        character_id,
        limit=limit,
        before_created_at=before_at,
        before_id=before_id,
    )
    if page is None:
        raise _not_found()
    next_cursor = _encode_cursor(page.items[-1]) if page.has_more and page.items else None
    return MessagePageOut(items=[_out(item) for item in page.items], next_cursor=next_cursor)
