# 멱등 키 설계

| 항목 | 내용 |
|---|---|
| 작성일 | 2026-10-05 |
| 상태 | **확정** (공통 코드와 `friends` 마이그레이션은 구현됨, 나머지는 각 담당이 이 문서를 따라 구현) |
| 읽는 사람 | 김성현(B, 업로드·생성·친구 저장), 김택수(C, 대화) |
| 근거 | API 계약 v1 2절 (`frontend-api-reply.md`), 요구사항 FR-04.1, FR-05.6, FR-09.1 |
| 공통 코드 | `server/app/idempotency.py` (테스트: `server/tests/test_idempotency.py`) |

## 1. 해결하려는 문제

같은 요청을 두 번 받아도 작업·친구·메시지가 **하나만** 생겨야 합니다. 중복 클릭, 네트워크 재시도, 앱이 백그라운드에 갔다가 돌아오는 경우입니다. 대상은 세 곳입니다.

| 엔드포인트 | 키 | 처음 | 재전송 |
|---|---|---|---|
| `POST /v1/generations` | `Idempotency-Key` 헤더 | `202` | `200` + 같은 작업의 **현재 상태** |
| `POST /v1/characters` | `Idempotency-Key` 헤더 | `201` | `200` + 같은 친구 |
| `POST /v1/characters/{id}/messages` | 본문의 `clientMessageId` | `200` | `200` + 이전 결과 |

같은 키로 **다른 내용**을 보내면 세 곳 모두 `409 idempotency_key_conflict`입니다.

## 2. 설계 (확정)

**별도 키 테이블을 두지 않고, 만들어지는 리소스의 행에 키를 유일 값으로 저장합니다.**

```text
generation_jobs  unique (user_id, idempotency_key)        ← B가 만든다
friends          unique (user_id, idempotency_key)        ← 마이그레이션 20261005000400 (이미 있음)
messages         unique (character_id, client_message_id) ← C가 만든다
```

각 행에는 요청 내용의 지문 `request_fingerprint`(SHA-256)도 저장합니다. 키가 같을 때 지문으로 같은 요청인지 가립니다.

| 키가 | 지문이 | 결과 |
|---|---|---|
| 처음 보는 키 | — | 새로 만든다 (`created = True`) |
| 이미 있음 | 같다 | 재전송. 만들지 않고 이미 있는 것을 돌려준다 (`created = False`) |
| 이미 있음 | 다르다 | 409 `idempotency_key_conflict` |

**이 방식을 고른 이유**
- 키와 리소스가 같은 행이라 **원자적**입니다. 리소스는 만들어졌는데 키 기록이 없는 상태가 생길 수 없습니다.
- 응답 본문을 따로 저장하지 않습니다. 재전송에는 **리소스의 현재 상태**를 다시 읽어 돌려줍니다. 계약이 "같은 작업을 현재 상태와 함께 돌려준다"여서 이쪽이 더 정확합니다.
- 동시에 같은 키가 두 번 오면 DB의 유일 제약이 순서를 정합니다. 두 번째 요청은 첫 요청이 끝날 때까지 기다린 뒤 그 결과를 돌려받습니다.
- 첫 요청이 중간에 실패해 롤백되면 키도 함께 사라집니다. 같은 키로 다시 시도하면 처음부터 다시 처리됩니다.

**계약 문서와 달라진 점 (이미 `frontend-api-reply.md`에 반영):** 키 유지 기간을 "24시간"에서 **"만들어진 작업·친구가 서버에 있는 동안(최소 24시간)"**으로 바꿨습니다. 키가 행에 붙어 있기 때문입니다. 작업은 24시간 뒤 정리되므로 그때 키도 사라지고, 친구는 삭제할 때까지 키가 남습니다.

## 3. 공통 코드 사용법 (`app/idempotency.py`)

| 이름 | 용도 |
|---|---|
| `IdempotencyKeyHeader` | 헤더 검사. 인자 타입으로 쓴다. 없거나 형식이 틀리면 422 (`fieldErrors: {"Idempotency-Key": ...}`). OpenAPI에도 필수 헤더로 나온다 |
| `IdempotencyKey` | 요청 본문 필드(`clientMessageId`)용 같은 형식의 타입 |
| `fingerprint(payload)` | 요청 내용의 지문. dict나 Pydantic 모델을 받는다. **키 자체는 넣지 않는다** |
| `insert_or_replay(conn, ...)` | "새로 만들기 / 재전송이면 돌려주기 / 내용이 다르면 409"를 한 번에 처리 |

키 형식은 **8–64자의 영문·숫자·`-`·`_`** 입니다 (UUID v4 권장).

### `insert_or_replay`

```python
row, created = insert_or_replay(
    conn,
    table="public.generation_jobs",
    values={"user_id": user.id, "idempotency_key": key, "source_asset_id": ..., "status": "queued"},
    unique_columns=("user_id", "idempotency_key"),
    request_fingerprint=fingerprint({"sourceAssetId": str(body.source_asset_id), "sourceType": body.source_type}),
)
```

- `values`에 `unique_columns`의 값이 모두 있어야 합니다. 지문 컬럼(`request_fingerprint`)은 함수가 채웁니다.
- 돌려주는 `row`는 `dict`입니다(`returning *`). 연결은 서버 풀의 `dict_row` 연결이어야 합니다.
- 테이블·컬럼 이름은 SQL에 직접 들어가므로 **코드에 적은 상수만** 넘기세요. 소문자·숫자·`_`가 아닌 이름은 `ValueError`로 거절합니다.

## 4. 반드시 지킬 것

1. **`insert_or_replay`와 나머지 쓰기는 같은 트랜잭션에 둔다.** `with db.connection() as conn:` 한 블록 안에서 호출하고, 그 뒤에 이어지는 쓰기(작업 큐 넣기 등)도 같은 `conn`으로 합니다. 뒤따르는 작업이 실패해 롤백돼야 키도 사라져서 재시도할 수 있습니다.
2. **`unique_columns`와 DB의 유일 제약이 정확히 같아야 한다.** `on conflict (user_id, idempotency_key)`는 같은 컬럼 조합의 유일 인덱스가 있어야 동작합니다.
3. **지문에 키를 넣지 않는다.** 키는 유일 컬럼으로 따로 비교합니다. 지문에는 요청 내용(`sourceAssetId`, `name`, `favoriteThings` …)만 넣습니다. 목록은 순서도 내용으로 봅니다.
4. **응답은 저장하지 않고 리소스에서 다시 만든다.** 재전송에는 `row`로 현재 상태를 읽어 응답을 구성합니다.
5. **다른 유일 제약은 직접 처리한다.** 헬퍼가 막는 것은 `unique_columns`뿐입니다. 예를 들어 `friends.generation_job_id`가 이미 쓰였으면 헬퍼가 아니라 `psycopg.errors.UniqueViolation`이 납니다. **제약 이름을 보고** 409로 바꾸세요 (아래 4절 예).
6. **외부 호출(OpenAI)은 가능하면 트랜잭션 밖에서 한다.** 트랜잭션이 열려 있는 동안 같은 키의 재전송이 기다리게 됩니다.
7. **요청 횟수 제한(429)은 재전송에도 적용된다.** 제한 의존성이 핸들러보다 먼저 실행되므로 재전송도 한도를 씁니다. 의도된 동작입니다.

## 5. 엔드포인트별 구현 가이드

### 5.1 `POST /v1/generations` (B)

`generation_jobs` 테이블에 아래 컬럼과 제약이 필요합니다.

```sql
idempotency_key     text not null,
request_fingerprint text not null,
constraint generation_jobs_idempotency_key_format_check
  check (idempotency_key ~ '^[A-Za-z0-9_-]{8,64}$'),
constraint generation_jobs_user_id_idempotency_key_key
  unique (user_id, idempotency_key)
```

```python
@router.post("/generations", status_code=202, dependencies=[Depends(limit_generations)])
def start(body: StartGeneration, key: IdempotencyKeyHeader, user: CurrentUserDep, response: Response, db: DatabaseDep):
    with db.connection() as conn:
        job, created = insert_or_replay(conn, table="public.generation_jobs", values={...},
                                        unique_columns=("user_id", "idempotency_key"),
                                        request_fingerprint=fingerprint(body))
        if created:
            ...   # 작업 큐에 넣기 (같은 conn)
    if not created:
        response.status_code = 200      # 재전송: 현재 상태를 돌려준다
    return to_job_out(job)
```

- 재전송에는 `200`과 **그 시점의 상태**(`queued`/`processing`/`succeeded`/`failed`)를 돌려줍니다.
- 실패한 작업을 같은 키로 다시 보내면 **같은(실패한) 작업**이 돌아옵니다. 재시도는 새 키로 새 작업을 만드는 것이 계약입니다.
- **생성 작업은 만든 지 24시간이 지난 원본을 거부**하세요. 미사용 에셋 정리가 24시간 지난 파일을 지우므로, 정리와 겹치는 틈을 닫기 위해서입니다 (`app/cleanup.py` 참고).
- 새 테이블이 에셋을 가리키므로 `app/cleanup.py`의 `ASSET_REFERENCES`에 조건을 추가하세요.

### 5.2 `POST /v1/characters` (B)

`friends`의 키 컬럼은 이미 있습니다 (`idempotency_key`, `request_fingerprint`, `unique (user_id, idempotency_key)`). 시드 친구처럼 키가 없는 행은 `null`입니다.

```python
fp = fingerprint({"generationJobId": str(body.generation_job_id), "name": body.name,
                  "personalityType": body.personality_type, "favoriteThings": body.favorite_things,
                  "speechStyle": body.speech_style})
try:
    with db.connection() as conn:
        # 1) 작업이 내 것이고 succeeded인지 확인 (아니면 404 / 409 generation_not_ready)
        # 2) 친구와 에셋 연결을 넣는다 (키는 헬퍼가 처리)
        friend, created = insert_or_replay(conn, table="public.friends", values={..., "generation_job_id": job.id},
                                           unique_columns=("user_id", "idempotency_key"), request_fingerprint=fp)
except psycopg.errors.UniqueViolation as exc:
    if exc.diag.constraint_name == "friends_generation_job_id_key":
        raise ApiError(409, "generation_job_already_used", "이미 친구를 만든 작업이에요.") from None
    raise
if created:
    friend = generate_introduction(friend)   # 커밋 뒤에 소개문 생성(최대 10초). 실패하면 빈 문자열
response.status_code = 201 if created else 200
```

- **소개문 생성은 친구를 저장(커밋)한 뒤에** 합니다. 실패해도 친구는 저장된 채로 `introduction`이 빈 문자열입니다 (FR-05.4).
- **같은 키의 재전송이 소개문 생성 중에 오면** 그 시점의 친구(소개문이 비어 있을 수 있음)를 `200`으로 돌려줍니다. 계약에 이미 이 동작이 적혀 있습니다.
- 같은 키 + 같은 내용은 `generation_job_id` 제약까지 가지 않고 재전송으로 처리됩니다. **다른 키**로 같은 작업을 쓰면 위 `UniqueViolation`이 나서 409 `generation_job_already_used`입니다.

### 5.3 `POST /v1/characters/{id}/messages` (C)

`messages` 테이블에는 `client_message_id`와 `request_fingerprint`가 필요하고, 유일 제약은 `unique (character_id, client_message_id)`입니다. 본문 필드 타입은 `IdempotencyKey`를 씁니다. 지문은 `fingerprint({"text": 본문})`처럼 **메시지 내용**으로 만듭니다.

대화는 응답에 사용자 메시지와 친구의 답이 모두 필요해서 생각할 점이 하나 더 있습니다.

- 사용자 메시지를 넣으면서 키를 선점하고, **AI 호출은 트랜잭션 밖에서** 합니다. 친구의 답은 그 뒤에 저장합니다.
- 재전송이 와서 사용자 메시지는 있는데 **친구의 답이 아직 없는 경우**(첫 요청이 AI를 기다리는 중이거나 도중에 죽음)를 반드시 처리해야 합니다. 권장: 답이 없고 첫 요청이 오래됐다면(예: 15초 초과) 스크립트 대사로 답을 만들어 저장해서 돌려줍니다.
- 이 부분의 세부 설계는 C가 정하되, **같은 `clientMessageId`로 사용자 메시지와 답이 두 번 저장되지 않는다**는 수용 기준(FR-09)은 DB 테스트로 확인하세요.

## 6. 테스트 체크리스트

각 엔드포인트마다 아래를 **실제 PostgreSQL**(`TEST_DATABASE_URL`)로 확인하세요. 공통 코드의 동작은 `tests/test_idempotency.py`에서 이미 확인했으니, 엔드포인트에서는 연결과 응답 코드를 봅니다.

- [ ] 첫 요청은 `202`/`201`, 같은 키 재전송은 `200`이고 **행이 하나뿐**이다
- [ ] 같은 키로 다른 내용을 보내면 409 `idempotency_key_conflict`이고 행이 늘지 않는다
- [ ] 헤더가 없거나 형식이 틀리면 422이다
- [ ] 다른 사용자가 같은 키를 써도 서로 영향이 없다
- [ ] 뒤따르는 작업이 실패하면(예외) 롤백돼서 **같은 키로 다시 시도하면 성공**한다
- [ ] (생성) 다른 키로 같은 작업을 쓰면 409 `generation_job_already_used`이다
- [ ] 남의 리소스(작업·친구)를 쓰려는 요청은 404이다 (기존 소유권 규칙)

## 7. 이 설계에서 하지 않는 것

- 응답 본문을 저장하지 않습니다. 재전송은 리소스의 현재 상태입니다.
- 키 전용 테이블과 만료 정리 작업이 없습니다. 키는 리소스와 같이 살고 같이 사라집니다.
- 서버 프로세스를 여러 개 띄워도 동작이 달라지지 않습니다. 순서는 DB의 유일 제약이 정하므로 메모리 상태에 기대지 않습니다 (요청 횟수 제한과 달리).
