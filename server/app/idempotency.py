"""멱등 키 공통 부분 (API 계약 2절). 설계 문서: docs/idempotency-design.md

같은 요청을 다시 보내도(중복 클릭, 네트워크 재시도, 앱이 백그라운드에 갔다 돌아옴)
작업·친구·메시지가 하나만 생기게 한다. 키는 **만들어지는 리소스의 행에 유일 값으로 저장**한다.

    unique (user_id, idempotency_key)        -- generation_jobs, friends
    unique (character_id, client_message_id) -- 대화 메시지

각 행에는 요청 내용의 지문(`request_fingerprint`)도 함께 저장한다. 그러면 키가 같을 때:
- 지문도 같다 → 같은 요청의 재전송이다. 만들지 않고 이미 있는 리소스를 돌려준다.
- 지문이 다르다 → 같은 키로 다른 내용을 보냈다. 409 `idempotency_key_conflict`.

이 모듈이 주는 것:
- `IdempotencyKeyHeader`: `Idempotency-Key` 헤더 검사 (필수, 8–64자 영문·숫자·`-`·`_`)
- `IdempotencyKey`: 요청 본문 필드(`clientMessageId` 등)용 같은 형식의 타입
- `fingerprint()`: 요청 내용의 지문
- `insert_or_replay()`: "새로 만들거나, 이미 있으면 돌려주거나, 내용이 다르면 409"를 한 번에 처리
"""

import hashlib
import json
import re
from collections.abc import Mapping
from typing import Annotated, Any

import psycopg
from fastapi import Header
from pydantic import BaseModel, StringConstraints

from app.errors import ApiError, service_unavailable

KEY_MIN_LENGTH = 8
KEY_MAX_LENGTH = 64
KEY_PATTERN = r"^[A-Za-z0-9_-]+$"

# 헤더가 없거나 형식이 틀리면 422 `validation_error`이고
# `fieldErrors`는 {"Idempotency-Key": "missing" | "string_too_short" | ...}이다.
IdempotencyKeyHeader = Annotated[
    str,
    Header(
        alias="Idempotency-Key",
        min_length=KEY_MIN_LENGTH,
        max_length=KEY_MAX_LENGTH,
        pattern=KEY_PATTERN,
        description="요청마다 새로 만들고, 재전송할 때는 같은 값을 쓴다. UUID v4 권장.",
    ),
]

# 요청 본문의 키 필드(예: `clientMessageId`)용
IdempotencyKey = Annotated[
    str,
    StringConstraints(min_length=KEY_MIN_LENGTH, max_length=KEY_MAX_LENGTH, pattern=KEY_PATTERN),
]


def idempotency_conflict() -> ApiError:
    return ApiError(
        409,
        "idempotency_key_conflict",
        "같은 요청 키로 다른 내용을 보냈어요. 새 요청이라면 새 키로 다시 보내 주세요.",
    )


def fingerprint(payload: BaseModel | Mapping[str, Any]) -> str:
    """요청 내용의 지문. 키 순서와 상관없이 같은 내용이면 같은 값이다.

    **키 자체(`Idempotency-Key`, `clientMessageId`)는 넣지 않는다.** 키는 유일 컬럼으로 따로
    비교하고, 지문은 "키가 같을 때 내용도 같은가"만 보기 때문이다.
    목록은 순서도 내용으로 본다 (`["a", "b"]`와 `["b", "a"]`는 다른 요청).
    """
    data = payload.model_dump(mode="json") if isinstance(payload, BaseModel) else payload
    canonical = json.dumps(
        data, sort_keys=True, ensure_ascii=False, separators=(",", ":"), default=str
    )
    return hashlib.sha256(canonical.encode()).hexdigest()


_IDENTIFIER = re.compile(r"^[a-z_][a-z0-9_]*(\.[a-z_][a-z0-9_]*)?$")
_MAX_ATTEMPTS = 3


def _identifier(name: str) -> str:
    # 테이블·컬럼 이름은 SQL에 직접 들어가므로 코드에 적은 상수만 쓰게 모양을 검사한다.
    if not _IDENTIFIER.match(name):
        raise ValueError(f"not a plain SQL identifier: {name!r}")
    return name


def insert_or_replay(
    conn: psycopg.Connection,
    *,
    table: str,
    values: Mapping[str, Any],
    unique_columns: tuple[str, ...],
    request_fingerprint: str,
    fingerprint_column: str = "request_fingerprint",
) -> tuple[dict[str, Any], bool]:
    """행을 새로 넣거나, 같은 키의 행이 이미 있으면 그것을 돌려준다.

    돌려주는 값은 `(행, 새로 만들었는지)`이다.
    - 새로 만들었다 → `(방금 넣은 행, True)`. 첫 요청이므로 `202`/`201`로 응답한다.
    - 이미 있고 지문이 같다 → `(기존 행, False)`. 재전송이므로 `200`과 **현재 상태**로 응답한다.
    - 이미 있는데 지문이 다르다 → 409 `idempotency_key_conflict`.

    `values`에는 `unique_columns`의 값(예: `user_id`, `idempotency_key`)이 모두 들어 있어야 한다.
    지문 컬럼은 이 함수가 채운다.

    **호출하는 쪽은 이 호출과 나머지 쓰기를 같은 트랜잭션(`with db.connection() as conn`)에 둔다.**
    그러면 첫 요청이 중간에 실패해 롤백될 때 키도 함께 사라져서, 같은 키로 다시 시도할 수 있다.
    같은 키가 동시에 두 번 오면 두 번째 요청은 첫 요청이 끝날 때까지 기다린 뒤 그 결과를 돌려받는다
    (유일 제약이 순서를 정한다).

    `unique_columns` 말고 다른 유일 제약(예: `friends.generation_job_id`)에 걸리면 이 함수가
    아니라 `psycopg.errors.UniqueViolation`이 난다. 호출하는 쪽이 제약 이름을 보고 알맞은
    오류(예: 409 `generation_job_already_used`)로 바꿔야 한다.
    """
    table = _identifier(table)
    unique_columns = tuple(_identifier(c) for c in unique_columns)
    fingerprint_column = _identifier(fingerprint_column)
    missing = [c for c in unique_columns if c not in values]
    if missing:
        raise ValueError(f"values must include the unique columns: {missing}")

    row_values = {**values, fingerprint_column: request_fingerprint}
    columns = [_identifier(c) for c in row_values]
    insert_sql = (
        f"insert into {table} ({', '.join(columns)})"
        f" values ({', '.join(f'%({c})s' for c in columns)})"
        f" on conflict ({', '.join(unique_columns)}) do nothing returning *"
    )
    select_sql = f"select * from {table} where " + " and ".join(
        f"{c} = %({c})s" for c in unique_columns
    )

    # 충돌한 행이 그 사이에 지워졌다면(예: 만료 정리) 다시 넣어 본다.
    for _ in range(_MAX_ATTEMPTS):
        inserted = conn.execute(insert_sql, row_values).fetchone()
        if inserted is not None:
            return inserted, True
        existing = conn.execute(select_sql, row_values).fetchone()
        if existing is not None:
            if existing[fingerprint_column] != request_fingerprint:
                raise idempotency_conflict()
            return existing, False
    raise service_unavailable()
