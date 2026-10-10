"""친구와 대화 전송·기록 조회 API (FR-09)."""

import base64
import json
from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from pydantic import Field, field_validator

from app.ai_chat import ChatAiDep, ChatReply, script_reply
from app.auth import CurrentUserDep
from app.clock import NowDep
from app.errors import ERROR_RESPONSES, ApiError
from app.idempotency import IdempotencyKey
from app.rate_limit import limit_messages
from app.repositories.messages import MessageRecord, MessageRepositoryDep
from app.schemas import CamelModel
from app.sleep import sleep_status

router = APIRouter(prefix="/characters", tags=["chat"], responses=ERROR_RESPONSES)


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
) -> MessagePairOut:
    """AI가 답한다. 검열에 걸리거나 AI가 실패·15초 초과면 스크립트 대사로 답한다 (오류 아님).

    같은 ``clientMessageId``로 다시 보내면 이전 답을 그대로 돌려준다. 자는 시간에는 409.
    """
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

    assistant = repo.get_reply(user.id, character_id, user_message.id)
    if assistant is None:
        if created:
            reply = chat.reply(
                friend=profile,
                history=repo.recent_context(user.id, character_id, user_message),
                user_text=body.text,
            )
        else:
            # 첫 요청이 AI 호출 중 종료됐거나 동시에 재전송된 경우에도 답을 완성한다.
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
    response_model_exclude_none=True,
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
