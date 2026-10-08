"""친구(캐릭터): 보관함 목록·상세·삭제, 만들기·고치기, 수면 상태, 대화, 모션.

API 계약은 docs/frontend-api-reply.md 4·6·7절. junsang 브랜치에서 앱 기능을 위해 더한 것:
- `POST /characters`의 성격 자유 입력(`personality`)과 수면 시간(`bedtime`, `wakeTime`)
- `PATCH /characters/{id}` (앱의 수정 화면: 이름·성격·소개·말투·수면 시간)
- 응답의 `face` (얼굴 지도: 앱이 얼굴을 움직이고 간식을 입에 댄다), `personality`, 수면 시간
- 수면 상태는 친구마다의 수면 시간으로 판정한다.
"""

import logging
import unicodedata
from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Response
from pydantic import Field, field_validator
from pydantic_core import PydanticCustomError

from app.ai import AiDep, AiError, FriendBrief, Turn
from app.assets import AssetRow, ImageRef, image_refs
from app.auth import CurrentUserDep
from app.chat import compose_reply
from app.clock import NowDep
from app.config import Settings, get_settings
from app.errors import ERROR_RESPONSES, ApiError
from app.idempotency import IdempotencyKey, IdempotencyKeyHeader, fingerprint
from app.personality import PERSONALITY_TYPES, personality_label
from app.rate_limit import limit_messages
from app.repositories.characters import (
    CharacterRecord,
    CharacterRepository,
    CharacterRepositoryDep,
    NewCharacter,
)
from app.repositories.messages import MessageRecord, MessageRepositoryDep
from app.repositories.motions import MotionRepositoryDep
from app.schemas import CamelModel
from app.sleep import sleep_status
from app.storage import StorageClient, StorageDep, StorageError

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/characters", tags=["characters"], responses=ERROR_RESPONSES)

# 앱의 선택지와 글자 그대로 같아야 한다 (API 계약 4절).
FAVORITE_THINGS = ("사과", "친구랑 놀기", "산책", "구름", "낮잠", "그림", "노래", "바다")
SPEECH_STYLES = ("~지요!", "해요체", "반말")
SpeechStyle = Literal["~지요!", "해요체", "반말"]
NAME_MAX = 12
PERSONALITY_MAX = 30
INTRODUCTION_MAX = 70
CUSTOM_PERSONALITY = "custom"
INTRODUCTION_TIMEOUT_SECONDS = 10

Minute = Annotated[int, Field(ge=0, le=1439)]


def graphemes(text: str) -> int:
    """사용자에게 보이는 글자 수 (결합 문자·이모지 이음표는 앞 글자에 붙인다)."""
    count, joined = 0, False
    for char in text:
        if joined:
            joined = False
            continue
        if char == "‍":
            joined = True
            continue
        if unicodedata.combining(char) or "︀" <= char <= "️":
            continue
        if "\U0001f3fb" <= char <= "\U0001f3ff":  # 피부색
            continue
        count += 1
    return count


def _name(value: str) -> str:
    name = value.strip()
    if graphemes(name) < 1:
        raise PydanticCustomError("string_too_short", "이름은 1자 이상이어야 해요")
    if graphemes(name) > NAME_MAX:
        raise PydanticCustomError("string_too_long", "이름은 12자 이하여야 해요")
    return name


def _personality(value: str) -> str:
    text = value.strip()
    if graphemes(text) > PERSONALITY_MAX:
        raise PydanticCustomError("string_too_long", "성격은 30자 이하여야 해요")
    return text


def _personality_type(value: str) -> str:
    if value not in {p.code for p in PERSONALITY_TYPES}:
        raise PydanticCustomError("unknown_personality_type", "없는 성격 유형이에요")
    return value


# ---------------------------------------------------------------------------
# 응답 모양
# ---------------------------------------------------------------------------


class CharacterOut(CamelModel):
    id: UUID
    name: str
    personality_type: str
    personality_label: str
    # 아이가 직접 적은 성격. 성격 유형만 골랐으면 그 문구와 같다.
    personality: str
    introduction: str
    favorite_things: list[str]
    speech_style: str
    # 서버에서 만든 친구는 항상 값이 있다. 원본이 없는 데이터만 null이다.
    source: ImageRef | None
    art: ImageRef
    thumbnail: ImageRef
    accent_argb: int
    # 얼굴 지도 (앱 face.json 형식). 없으면 앱은 몸 전체 모션만 한다.
    face: dict | None
    # 자는 시각·깨는 시각 (자정부터 분, 한국 시간)
    bedtime: int
    wake_time: int
    created_at: datetime


class CharacterListOut(CamelModel):
    items: list[CharacterOut]
    # 데모 규모라 한 번에 모두 내려 준다. 나중에 페이지를 나눌 때를 위한 필드로 항상 null이다.
    next_cursor: str | None = None


def _to_out(record: CharacterRecord, refs: dict[UUID, ImageRef]) -> CharacterOut | None:
    """아트·썸네일 파일을 열 수 없는 친구는 None이다 (원본만 없으면 source가 null)."""
    if record.art.id not in refs or record.thumbnail.id not in refs:
        logger.error("character %s has an unreadable art or thumbnail file", record.id)
        return None
    label = record.personality or personality_label(record.personality_type)
    return CharacterOut(
        id=record.id,
        name=record.name,
        personality_type=record.personality_type,
        personality_label=label,
        personality=label,
        introduction=record.introduction,
        favorite_things=record.favorite_things,
        speech_style=record.speech_style,
        source=refs.get(record.source.id) if record.source else None,
        art=refs[record.art.id],
        thumbnail=refs[record.thumbnail.id],
        accent_argb=record.accent_argb,
        face=record.face,
        bedtime=record.bedtime_minute,
        wake_time=record.wake_minute,
        created_at=record.created_at,
    )


def _assets_of(records: list[CharacterRecord]):
    for record in records:
        if record.source:
            yield record.source
        yield record.art
        yield record.thumbnail


def _signed(record: CharacterRecord, storage: StorageClient) -> CharacterOut:
    out = _to_out(record, image_refs(storage, _assets_of([record])))
    if out is None:
        raise ApiError(404, "not_found", "친구를 찾을 수 없어요.")
    return out


class SleepStatusOut(CamelModel):
    asleep: bool
    next_change_at: datetime
    # 앱이 기기 시계 오차를 보정할 수 있도록 서버 시각을 함께 준다.
    server_time: datetime


class PersonalityTypeOut(CamelModel):
    code: str
    label: str


class PersonalityTypesOut(CamelModel):
    items: list[PersonalityTypeOut]


# ---------------------------------------------------------------------------
# 목록·상세·삭제·수면
# ---------------------------------------------------------------------------


@router.get("", response_model=CharacterListOut, summary="내 친구 목록 (보관함)")
def list_characters(
    user: CurrentUserDep, repo: CharacterRepositoryDep, storage: StorageDep
) -> CharacterListOut:
    """내 친구를 최신순으로 돌려준다. 친구가 없으면 빈 목록이다.

    아트·썸네일 파일이 사라진 친구는 목록에서 빼고(오류 로그), 나머지는 정상으로 돌려준다.
    """
    records = repo.list_for_user(user.id)
    refs = image_refs(storage, _assets_of(records))
    outs = (_to_out(record, refs) for record in records)
    return CharacterListOut(items=[out for out in outs if out is not None])


@router.get("/{character_id}", response_model=CharacterOut, summary="친구 상세")
def get_character(
    character_id: UUID, user: CurrentUserDep, repo: CharacterRepositoryDep, storage: StorageDep
) -> CharacterOut:
    """없는 친구와 남의 친구는 똑같이 404다. 아트·썸네일 파일이 사라진 친구도 목록과 같게 404다."""
    record = repo.get_for_user(user.id, character_id)
    if record is None:
        raise ApiError(404, "not_found", "친구를 찾을 수 없어요.")
    return _signed(record, storage)


@router.get(
    "/{character_id}/status",
    response_model=SleepStatusOut,
    summary="친구의 수면 상태",
)
def get_status(
    character_id: UUID, user: CurrentUserDep, repo: CharacterRepositoryDep, now: NowDep
) -> SleepStatusOut:
    """친구의 수면 시간(기본 한국 시간 22:00–06:00)으로 판정한다. 서버 시각 기준이다 (FR-08)."""
    record = repo.get_for_user(user.id, character_id)
    if record is None:
        raise ApiError(404, "not_found", "친구를 찾을 수 없어요.")
    status = sleep_status(now, record.bedtime_minute, record.wake_minute)
    return SleepStatusOut(
        asleep=status.asleep, next_change_at=status.next_change_at, server_time=now
    )


def _remove_files(
    repo: CharacterRepository, storage: StorageClient, user_id: UUID, assets: list[AssetRow]
) -> None:
    """파일을 지우고 에셋 행을 지운다. 실패해도 친구는 이미 삭제됐으므로 예외를 내지 않는다.

    실패하면 에셋 행이 남는다. 행이 남아 있으면 경로를 알 수 있어서 나중에 다시 정리할 수 있다.
    """
    if not assets:
        return
    try:
        storage.remove([asset.storage_path for asset in assets])
        repo.delete_assets(user_id, [asset.id for asset in assets])
    except (StorageError, ApiError) as exc:
        logger.warning(
            "deleted a character but left %d asset row(s) for cleanup: %s", len(assets), exc
        )


@router.delete("/{character_id}", status_code=204, summary="친구 삭제 (영구)")
def delete_character(
    character_id: UUID, user: CurrentUserDep, repo: CharacterRepositoryDep, storage: StorageDep
) -> Response:
    """즉시 영구 삭제한다. 되돌릴 수 없다 (FR-06.3, D-21).

    친구, 대화·모션 기록, 원본·캐릭터 아트·썸네일·모션 클립 파일이 함께 지워지고, 아바타였다면
    기본값으로 돌아간다. 없는 친구와 남의 친구는 똑같이 404다. 이미 지운 친구를 다시 지워도 404다.
    """
    assets = repo.delete_for_user(user.id, character_id)
    if assets is None:
        raise ApiError(404, "not_found", "친구를 찾을 수 없어요.")
    _remove_files(repo, storage, user.id, assets)
    return Response(status_code=204)


# ---------------------------------------------------------------------------
# 만들기·고치기
# ---------------------------------------------------------------------------


class CreateCharacterIn(CamelModel):
    generation_job_id: UUID
    name: str
    # 성격: 목록에서 고른 코드, 또는 아이가 직접 적거나 말한 문장 (둘 중 하나는 있어야 한다)
    personality_type: str | None = None
    personality: str | None = None
    favorite_things: list[str] = Field(min_length=1, max_length=8)
    speech_style: SpeechStyle
    bedtime: Minute | None = None
    wake_time: Minute | None = None

    @field_validator("name")
    @classmethod
    def _check_name(cls, value: str) -> str:
        return _name(value)

    @field_validator("personality")
    @classmethod
    def _check_personality(cls, value: str | None) -> str | None:
        return None if value is None else _personality(value)

    @field_validator("personality_type")
    @classmethod
    def _check_type(cls, value: str | None) -> str | None:
        return None if value is None else _personality_type(value)

    @field_validator("favorite_things")
    @classmethod
    def _favorites(cls, value: list[str]) -> list[str]:
        if len(set(value)) != len(value):
            raise PydanticCustomError("duplicate_item", "같은 항목이 두 번 있어요")
        if any(v not in FAVORITE_THINGS for v in value):
            raise PydanticCustomError("unknown_item", "선택지에 없는 항목이에요")
        return value


class UpdateCharacterIn(CamelModel):
    """보낸 필드만 바꾼다."""

    name: str | None = None
    personality_type: str | None = None
    personality: str | None = None
    introduction: str | None = None
    speech_style: SpeechStyle | None = None
    bedtime: Minute | None = None
    wake_time: Minute | None = None

    @field_validator("name")
    @classmethod
    def _check_name(cls, value: str | None) -> str | None:
        return None if value is None else _name(value)

    @field_validator("personality")
    @classmethod
    def _check_personality(cls, value: str | None) -> str | None:
        return None if value is None else _personality(value)

    @field_validator("personality_type")
    @classmethod
    def _check_type(cls, value: str | None) -> str | None:
        return None if value is None else _personality_type(value)

    @field_validator("introduction")
    @classmethod
    def _introduction(cls, value: str | None) -> str | None:
        if value is None:
            return None
        text = value.strip()
        if len(text) > INTRODUCTION_MAX:
            raise PydanticCustomError("string_too_long", "소개는 70자 이하여야 해요")
        return text


def _brief(record: CharacterRecord) -> FriendBrief:
    return FriendBrief(
        name=record.name,
        personality=record.personality or personality_label(record.personality_type),
        favorite_things=record.favorite_things,
        speech_style=record.speech_style,
        introduction=record.introduction,
    )


@router.post(
    "",
    status_code=201,
    response_model=CharacterOut,
    summary="친구 만들기",
    responses={409: ERROR_RESPONSES[404]},
)
def create_character(
    body: CreateCharacterIn,
    idempotency_key: IdempotencyKeyHeader,
    user: CurrentUserDep,
    repo: CharacterRepositoryDep,
    motions: MotionRepositoryDep,
    storage: StorageDep,
    ai: AiDep,
    settings: Annotated[Settings, Depends(get_settings)],
    response: Response,
) -> CharacterOut:
    """성공한 생성 작업 하나로 친구 하나를 만든다. 그림·대표색·얼굴 지도는 작업 결과를 쓴다.

    저장 직후 AI가 소개 문구(70자 이내)를 쓴다 (최대 10초, 실패하면 빈 문자열). 모션 클립 작업도
    이때 시작한다. 같은 키로 다시 보내면 같은 친구를 200으로 돌려준다.
    """
    if body.personality_type is None and not body.personality:
        raise ApiError(
            422,
            "validation_error",
            "입력값을 확인해 주세요.",
            field_errors={"personality": "missing"},
        )
    record, created = repo.create_for_user(
        user.id,
        NewCharacter(
            generation_job_id=body.generation_job_id,
            name=body.name,
            personality_type=body.personality_type or CUSTOM_PERSONALITY,
            personality=body.personality or "",
            favorite_things=body.favorite_things,
            speech_style=body.speech_style,
            bedtime_minute=body.bedtime if body.bedtime is not None else 22 * 60,
            wake_minute=body.wake_time if body.wake_time is not None else 6 * 60,
            idempotency_key=idempotency_key,
            request_fingerprint=fingerprint(body),
        ),
    )
    if not created:
        response.status_code = 200
        return _signed(record, storage)

    if ai.writer is not None:
        try:
            text = ai.writer.introduction(_brief(record), timeout=INTRODUCTION_TIMEOUT_SECONDS)
            text = text.strip().strip('"')[:INTRODUCTION_MAX]
            flagged = ai.moderator is not None and ai.moderator.flagged(text=text, timeout=5)
            if text and not flagged:
                repo.set_introduction(user.id, record.id, text)
        except AiError as exc:
            logger.warning("introduction was not written: %s", type(exc).__name__)
    motions.create(user.id, record.id, enabled=bool(settings.motion_service_url))
    fresh = repo.get_for_user(user.id, record.id) or record
    return _signed(fresh, storage)


@router.patch("/{character_id}", response_model=CharacterOut, summary="친구 고치기")
def update_character(
    character_id: UUID,
    body: UpdateCharacterIn,
    user: CurrentUserDep,
    repo: CharacterRepositoryDep,
    storage: StorageDep,
) -> CharacterOut:
    """앱의 수정 화면: 이름·성격·소개·말투·수면 시간. 보낸 것만 바꾼다."""
    sent = body.model_fields_set
    changes: dict[str, object] = {}
    for field, column in (
        ("name", "name"),
        ("introduction", "introduction"),
        ("speech_style", "speech_style"),
        ("bedtime", "bedtime_minute"),
        ("wake_time", "wake_minute"),
    ):
        if field in sent and getattr(body, field) is not None:
            changes[column] = getattr(body, field)
    if "personality" in sent and body.personality is not None:
        changes["personality"] = body.personality
        if body.personality_type is None:
            changes["personality_type"] = CUSTOM_PERSONALITY
    if body.personality_type is not None:
        changes["personality_type"] = body.personality_type
        if "personality" not in sent:
            changes["personality"] = ""
    record = repo.update_for_user(user.id, character_id, changes)
    if record is None:
        raise ApiError(404, "not_found", "친구를 찾을 수 없어요.")
    return _signed(record, storage)


# ---------------------------------------------------------------------------
# 대화
# ---------------------------------------------------------------------------


class MessageIn(CamelModel):
    client_message_id: IdempotencyKey
    text: str

    @field_validator("text")
    @classmethod
    def _text(cls, value: str) -> str:
        text = value.strip()
        if not text:
            raise PydanticCustomError("string_too_short", "메시지를 입력해 주세요")
        if len(text) > 200:
            raise PydanticCustomError("string_too_long", "메시지는 200자 이하여야 해요")
        return text


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
    next_cursor: str | None


def _message(record: MessageRecord) -> MessageOut:
    return MessageOut(
        id=record.id,
        role=record.role,
        text=record.text,
        source=record.source,
        created_at=record.created_at,
    )


@router.post(
    "/{character_id}/messages",
    response_model=MessagePairOut,
    response_model_exclude_none=True,
    summary="친구에게 말 걸기",
    dependencies=[Depends(limit_messages)],
)
def send_message(
    character_id: UUID,
    body: MessageIn,
    user: CurrentUserDep,
    repo: CharacterRepositoryDep,
    messages: MessageRepositoryDep,
    ai: AiDep,
    now: NowDep,
) -> MessagePairOut:
    """AI가 답한다. 검열에 걸리거나 AI가 실패·15초 초과면 스크립트 대사로 답한다 (오류 아님).

    같은 `clientMessageId`로 다시 보내면 이전 답을 그대로 돌려준다. 자는 시간에는 409.
    """
    record = repo.get_for_user(user.id, character_id)
    if record is None:
        raise ApiError(404, "not_found", "친구를 찾을 수 없어요.")
    request_print = fingerprint({"text": body.text})
    pair = messages.find_pair(user.id, character_id, body.client_message_id, request_print)
    if pair is None:
        if sleep_status(now, record.bedtime_minute, record.wake_minute).asleep:
            raise ApiError(409, "character_asleep", f"{record.name}는 지금 자고 있어요.")
        history = [Turn(m.role, m.text) for m in messages.recent(user.id, character_id, limit=20)]
        reply = compose_reply(ai, _brief(record), history, body.text)
        pair = messages.save_pair(
            user.id,
            character_id,
            client_message_id=body.client_message_id,
            fingerprint=request_print,
            text=body.text,
            reply=reply.text,
            source=reply.source,
        )
    return MessagePairOut(
        user_message=_message(pair.user), assistant_message=_message(pair.assistant)
    )


@router.get("/{character_id}/messages", response_model=MessagePageOut, summary="이전 대화")
def list_messages(
    character_id: UUID,
    user: CurrentUserDep,
    repo: CharacterRepositoryDep,
    messages: MessageRepositoryDep,
    limit: Annotated[int, Query(ge=1, le=100)] = 30,
    before: str | None = None,
) -> MessagePageOut:
    """최신순. 다음 페이지는 `before=<nextCursor>`."""
    if not repo.exists_for_user(user.id, character_id):
        raise ApiError(404, "not_found", "친구를 찾을 수 없어요.")
    items, cursor = messages.page(user.id, character_id, before=before, limit=limit)
    return MessagePageOut(items=[_message(m) for m in items], next_cursor=cursor)


# ---------------------------------------------------------------------------
# 모션
# ---------------------------------------------------------------------------


class ClipOut(CamelModel):
    url: str
    box: list[float]
    expires_at: datetime


class MotionOut(CamelModel):
    status: str
    reason: str | None
    clips: dict[str, ClipOut]


@router.get("/{character_id}/motion", response_model=MotionOut, summary="친구의 모션 클립")
def get_motion(
    character_id: UUID,
    user: CurrentUserDep,
    repo: CharacterRepositoryDep,
    motions: MotionRepositoryDep,
    storage: StorageDep,
) -> MotionOut:
    """`ready`일 때만 클립이 있다. 그 밖에는 앱 기본 모션을 쓴다. GIF URL은 60분 뒤 만료된다."""
    if not repo.exists_for_user(user.id, character_id):
        raise ApiError(404, "not_found", "친구를 찾을 수 없어요.")
    job = motions.get_for_user(user.id, character_id)
    if job is None:
        return MotionOut(status="unsupported", reason="disabled", clips={})
    clips: dict[str, ClipOut] = {}
    if job.status == "ready":
        refs = image_refs(storage, job.assets.values())
        for kind, info in job.clips.items():
            ref = refs.get(UUID(info["assetId"]))
            if ref is not None:
                clips[kind] = ClipOut(url=ref.url, box=info["box"], expires_at=ref.expires_at)
    return MotionOut(status=job.status, reason=job.reason, clips=clips)


# ---------------------------------------------------------------------------
# 성격 유형 목록
# ---------------------------------------------------------------------------

types_router = APIRouter(prefix="/personality-types", tags=["characters"])


@types_router.get("", response_model=PersonalityTypesOut, summary="성격 유형 목록")
def personality_types() -> PersonalityTypesOut:
    return PersonalityTypesOut(
        items=[PersonalityTypeOut(code=p.code, label=p.label) for p in PERSONALITY_TYPES]
    )


__all__ = ["router", "types_router", "FAVORITE_THINGS", "SPEECH_STYLES"]
