# 보글 API 서버

FastAPI로 만든 보글 백엔드 서버입니다. 기준 문서는 `aidlc-docs/inception/requirements/requirements.md`입니다.
API 계약의 기준은 서버를 띄우면 열리는 **`/docs`(OpenAPI)** 입니다.

친구 만들기(FR-03~05)의 구현·설정·작업 정책은 [친구 만들기 구현 문서](../docs/friend-creation-implementation.md)를 참고하세요.
원본 업로드, OpenRouter 이미지 생성, 상태·취소, 성격 목록과 친구 저장 API가 추가되었습니다.
`server/.env`에 `OPENROUTER_API_KEY`를 입력합니다. 기존 `openrouter_key`도 인식합니다.
내부 워커와 메모리 횟수 제한을 위해 서버는 **`--workers 1`**로 실행하세요.
`uv sync --locked --extra dev`로 잠금 파일의 의존성을 설치할 수 있습니다.

## AI 연결 기준

- 이미지·대화 생성과 생성 PNG의 얼굴 좌표 분석은 서버에서 **OpenRouter**를 통해 호출합니다(D-25). 소개 문구는 기존 8개 중 하나를 저장합니다.
- 얼굴 분석은 `openai/gpt-6-luna`와 검수한 예시 6장을 사용합니다. `OPENROUTER_API_KEY`가 있어야 활성화되며, 실패해도 친구 생성은 성공합니다. 필요하면 `OPENROUTER_FACE_MODEL`로 교체할 수 있지만 해당 모델의 호출 설정 호환성을 확인해야 합니다.
- 얼굴 분석 규격과 생성 파이프라인 통합 지점은 `docs/face-analysis-design.md`에 있습니다.
- 기존 **OpenAI Moderation** 입력·출력 검사는 별도 직접 호출로 유지하며 OpenRouter 키와 혼용하지 않습니다.

## 실행

Python 3.11 이상이 필요합니다. 모든 명령은 `server/` 폴더에서 실행합니다.

```bash
python -m venv .venv
source .venv/bin/activate          # Windows PowerShell: .venv\Scripts\Activate.ps1
pip install -e ".[dev]"
cp .env.example .env               # 값을 채운다 (Windows PowerShell: Copy-Item .env.example .env)

uvicorn app.main:app --reload --no-access-log
```

- API 문서: http://localhost:8000/docs
- 상태 확인: http://localhost:8000/v1/health

## 검사

```bash
pytest                  # 테스트
ruff check .            # 린트
ruff format .           # 포맷
```

PR을 올리기 전에 세 가지가 모두 통과해야 합니다.

PR을 올리면 GitHub Actions(CI)가 같은 검사를 자동으로 다시 돌립니다(임시 PostgreSQL 포함). PR 화면의 ✅/❌를 확인하세요. CI에서는 `TEST_DATABASE_URL`이 없으면 DB 테스트를 건너뛰지 않고 **실패**합니다.

### DB 테스트
친구·프로필처럼 DB를 쓰는 테스트(`tests/test_*_db.py`)는 **실제 PostgreSQL**에 마이그레이션을 적용해서 돌립니다.
`TEST_DATABASE_URL`이 없으면 이 테스트들은 **건너뜁니다**(`pytest`가 통과해 보여도 소유권 테스트는 실행되지 않은 것입니다). PR 전에는 꼭 켜고 돌려 주세요.

```bash
# 데이터베이스를 만들 수 있는 계정의 연결 문자열. 테스트가 임시 DB를 만들고 끝나면 지웁니다.
export TEST_DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres   # supabase start 의 로컬 DB
pytest
```

Supabase CLI가 없으면 Docker로 PostgreSQL을 띄워도 됩니다:
`docker run --rm -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres:16` 후
`TEST_DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/postgres`

Supabase의 `auth`·`storage` 스키마는 `tests/sql/supabase_stub.sql`이 흉내 냅니다. 실제 Supabase와 완전히 같지는 않습니다.

## 로컬 Supabase로 서버 확인하기

> **실제 Supabase(Supabase CLI 2.117, 로컬 Docker)에서 확인함** (2026-10-05). 로그인 토큰 검증, Storage 서명·업로드·삭제, 친구 목록·삭제, 정리 작업, RLS가 가짜가 아닌 실제 Auth·Storage·PostgREST로 동작했습니다. 확인 내용은 `supabase/README.md`의 "로컬 검증 결과"에 있습니다.

Docker Desktop을 켜 둔 상태에서 저장소 루트에서 실행합니다 (PowerShell).

```powershell
supabase start                       # 첫 실행은 이미지를 받느라 몇 분 걸립니다
supabase status -o env               # API_URL, SERVICE_ROLE_KEY 등을 보여 줍니다 (값을 커밋·공유하지 마세요)
```

`server/.env`를 채웁니다. 로컬 Supabase는 **ES256 비대칭 키**로 토큰을 서명하므로 `SUPABASE_JWT_SECRET`은 비워 둬도 됩니다 (서버가 `SUPABASE_URL`의 JWKS로 검증합니다).

```text
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_SERVICE_ROLE_KEY=<supabase status 의 SERVICE_ROLE_KEY>
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres
```

`.env`가 있으면 서버·시드 스크립트가 그 값을 읽습니다. 가입한 계정으로 시드 친구를 만들고 서버를 띄웁니다.

```powershell
cd server
# 로컬 Auth 가입 (이메일 확인 없음). 앱의 Google 로그인 대신 개발용으로만 씁니다.
$anon = (supabase status -o env | Select-String '^ANON_KEY=').ToString().Split('"')[1]
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:54321/auth/v1/signup `
  -Headers @{ apikey = $anon } -ContentType 'application/json' `
  -Body '{"email":"me@example.com","password":"Test-pass-1234!"}' | Out-Null

python -m scripts.seed --email me@example.com
uvicorn app.main:app --no-access-log
```

로그인 토큰은 `POST /auth/v1/token?grant_type=password`로 받을 수 있고, `Authorization: Bearer <access_token>`으로 `GET http://localhost:8000/v1/me`를 불러 확인합니다.

가입하면 `public.profiles` 행이 트리거로 자동 생성되고 닉네임은 `그린고블린`입니다.

### 연결 문자열
- 로컬 DB 직접 연결: `postgresql://postgres:postgres@127.0.0.1:54322/postgres`
- 로컬 pooler(transaction mode)를 쓰려면 `supabase/config.toml`의 `[db.pooler] enabled = true`로 바꾸고 다시 시작한 뒤 `postgresql://postgres.pooler-dev:postgres@127.0.0.1:54329/postgres`를 씁니다. 사용자 이름의 `pooler-dev`는 프로젝트 이름과 무관한 로컬 고정 값입니다. 서버는 prepared statement를 끄고 연결하므로 그대로 동작합니다.

## 폴더 구조

```text
server/
├── pyproject.toml          의존성과 도구 설정
├── .env.example            환경변수 이름 (값은 .env에만 적는다)
├── app/
│   ├── main.py             앱 생성, 미들웨어·오류 처리·라우터 연결
│   ├── config.py           환경변수 설정 (Settings)
│   ├── auth.py             Supabase 토큰 검증 → CurrentUserDep
│   ├── db.py               Postgres 연결 풀 → DatabaseDep
│   ├── storage.py          Storage 서명 URL·업로드·삭제 → StorageDep
│   ├── assets.py           이미지를 앱에 내려 줄 때의 공통 모양 (ImageRef)
│   ├── personality.py      성격 유형 목록
│   ├── sleep.py            수면 시간 판정 (한국 시간 22:00–06:00)
│   ├── clock.py            현재 시각 (테스트에서 고정할 수 있게 의존성으로 분리)
│   ├── rate_limit.py       사용자별 요청 횟수 제한 (429). limit_generations 등을 라우터에 붙인다
│   ├── idempotency.py      멱등 키: 헤더 검사, 요청 지문, insert_or_replay (설계: docs/idempotency-design.md)
│   ├── cleanup.py          미사용 에셋 정리 (서버가 1시간마다 실행). 새 테이블이 에셋을 가리키면 ASSET_REFERENCES에 추가
│   ├── errors.py           공통 오류 형식과 ApiError
│   ├── request_context.py  requestId 부여, 접근 로그
│   ├── schemas.py          CamelModel (JSON은 camelCase)
│   ├── repositories/       SQL은 여기서만 쓴다. 모든 함수가 user_id를 받아 소유자로 거른다
│   └── routers/
│       ├── __init__.py     라우터 등록 (공용 파일)
│       ├── health.py       GET /v1/health
│       ├── characters.py   보관함: 목록·상세·삭제, 수면 상태
│       └── profile.py      GET·PATCH /v1/me
├── scripts/
│   └── seed.py             개발용 시드 친구 만들기·지우기
└── tests/
    ├── conftest.py         fixture (임시 PostgreSQL 포함)
    ├── db_support.py       DB 테스트용 사용자·에셋·친구 생성 도우미, 가짜 Storage
    ├── sql/                supabase_stub.sql (auth·storage 스키마 흉내)
    ├── probe.py            테스트 전용 라우터 (인증·오류·검증 확인용)
    └── test_*.py
```

## 새 API를 만들 때

1. `app/routers/`에 라우터 파일을 만든다. 요청·응답 모델은 `CamelModel`을 상속한다. DB는 `app/repositories/`에 repository를 만들어 쓴다.
2. `app/routers/__init__.py`의 `api_routers`에 **한 줄만** 추가한다. 경로는 자동으로 `/v1` 아래에 붙는다.
3. 로그인이 필요한 API는 인자로 `user: CurrentUserDep`을 받는다. **사용자 ID는 `user.id`(토큰)만 쓰고**, 요청 본문·쿼리의 사용자 ID는 쓰지 않는다.
4. 오류는 `raise ApiError(status_code, code, message)`로 낸다. 다른 사용자의 리소스는 404를 돌려준다.
   - **서버는 DB에 직접 연결하므로 RLS가 적용되지 않는다.** repository의 모든 쿼리는 `where user_id = %(user_id)s`처럼 **소유자 조건을 직접** 걸어야 하고, 남의 리소스를 요청하는 DB 테스트(`tests/test_characters_db.py` 참고)를 함께 쓴다.
   - 이미지를 돌려줄 때는 경로를 그대로 내보내지 말고 `app/assets.py`의 `image_refs()`로 서명 URL이 든 `ImageRef`로 바꾼다.
   - **`image_refs()`의 결과에는 Storage에 파일이 없는 에셋이 빠져 있다.** 결과에서 `refs[asset.id]`로 바로 꺼내면 `KeyError`가 나므로, 꼭 필요한 이미지(아트·썸네일)가 없을 때의 처리(목록에서 빼기, 상세는 404 등)를 정해서 쓴다. 예: `routers/characters.py`의 `_to_out`.
   - Storage 객체 경로는 **ASCII만** 쓴다. 한글·공백이 든 경로는 Storage가 거부한다. 업로드한 파일 이름을 경로에 넣지 말고 `{user_id}/{uuid}.png`처럼 UUID로 만든다.
5. 라우터의 `responses=ERROR_RESPONSES`로 오류 형식을 문서에 드러낸다.

```python
from fastapi import APIRouter

from app.auth import CurrentUserDep
from app.errors import ERROR_RESPONSES, ApiError
from app.schemas import CamelModel

router = APIRouter(tags=["friends"], responses=ERROR_RESPONSES)


class FriendOut(CamelModel):
    id: str
    name: str


@router.get("/friends/{friend_id}", response_model=FriendOut)
def get_friend(friend_id: str, user: CurrentUserDep) -> FriendOut:
    ...  # user.id 로 소유자를 확인하고, 내 것이 아니면:
    raise ApiError(404, "friend_not_found", "친구를 찾을 수 없어요.")
```

## 시드 데이터 (테스트용 친구)

다른 사람의 기능이 아직 없어도 내 기능을 테스트할 수 있도록, 내 계정에 테스트용 친구를 만듭니다.
예를 들어 대화를 개발하는 사람은 친구 저장이 끝나기 전에 시드 친구로 작업할 수 있습니다.

```bash
cd server
python -m scripts.seed --email you@example.com            # 시드 친구 3명 만들기
python -m scripts.seed --email you@example.com --clean    # 시드 친구만 지우기
```

- 계정은 **앱에서 Google로 한 번 로그인해서 만들어 둔 것**이어야 합니다. 스크립트는 계정을 만들지 않습니다.
- `.env`에 `DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`가 있어야 합니다. **어느 Supabase 프로젝트에 연결돼 있는지 확인하고 실행하세요** (개발용과 시연용이 분리돼 있습니다).
- 이름이 `시드 `로 시작하는 친구 3명(`시드 구름이`, `시드 별이`, `시드 도토리`)과 단색 PNG 이미지가 만들어집니다. 여러 번 실행해도 이미 있는 친구는 다시 만들지 않습니다.
- `--clean`은 시드 친구만 지웁니다 (Storage 경로가 `{user_id}/seed/`로 시작하는 친구). 직접 만든 친구는 건드리지 않습니다.

## 공통 규약

| 항목 | 규칙 |
|---|---|
| 경로 | `/v1` 접두어 |
| JSON 필드 | camelCase (`CamelModel`이 처리) |
| 시각 | UTC ISO 8601 |
| 오류 형식 | `{"error": {"code", "message", "retryable", "fieldErrors", "requestId"}}` — 자세한 설명은 `app/errors.py` |
| 입력 검증 실패 | 422, `code: validation_error`, `fieldErrors`는 `{필드: 오류 종류}` (예: `{"name": "string_too_short"}`) |
| requestId | 응답 헤더 `X-Request-Id`와 오류 본문의 `requestId`가 같다. 앱이 같은 헤더를 보내면 그 값을 쓴다 |
| 로그 | 메서드·경로·상태·시간만 남긴다. 요청 본문과 쿼리는 남기지 않는다 |

## 인증

앱은 Supabase 로그인으로 받은 액세스 토큰을 `Authorization: Bearer <토큰>`으로 보냅니다.
서버는 토큰의 서명·만료·audience·issuer를 검증하고 `sub`를 사용자 ID로 씁니다.

- Supabase 프로젝트가 **비대칭 서명 키**(ES256/RS256)를 쓰면 `SUPABASE_URL`만 설정합니다. 서버가 JWKS에서 공개 키를 받습니다.
- **레거시 공유 비밀**(HS256)을 쓰면 `SUPABASE_JWT_SECRET`도 설정합니다.
- 어느 쪽인지 모르겠으면 둘 다 채워도 됩니다. 토큰 헤더의 알고리즘에 맞는 키만 사용합니다.

## 환경변수

`.env.example`을 복사해서 채웁니다. 서버만 쓰는 값이며 `service_role` 키와 DB 연결 문자열은 **절대 커밋하지 않습니다.**

| 이름 | 용도 | 없으면 |
|---|---|---|
| `SUPABASE_URL` | 토큰 검증(JWKS), Storage 호출 | 비대칭 키 토큰 검증 불가, 이미지 API 503 |
| `SUPABASE_JWT_SECRET` | 레거시 HS256 토큰 검증 | HS256 토큰 거부 |
| `SUPABASE_SERVICE_ROLE_KEY` | Storage 서명 URL 생성 | 이미지를 돌려주는 API가 503 |
| `DATABASE_URL` | Postgres 직접 연결 | DB를 쓰는 API가 503 (서버는 뜸) |
| `OPENROUTER_API_KEY` | 이미지·대화 생성과 얼굴 분석. 소개는 기존 문구 선택 | 새 친구 생성 요청 거부, 얼굴 분석 비활성 |
| `OPENROUTER_FACE_MODEL` | 얼굴 분석용 이미지 입력 모델 ID. 기본 `openai/gpt-6-luna` | 기본값 사용 |
| `FACE_ANALYSIS_TIMEOUT_SECONDS` | 얼굴 분석 제한 시간. 기본 120초 | 기본값 사용 |
| `CLEANUP_INTERVAL_SECONDS` | 미사용 에셋 정리 주기(초). 기본 3600, 0이면 끔 | 기본값 사용. DB·Storage 설정이 없으면 정리는 자동으로 꺼짐 |
| `ASSET_RETENTION_HOURS` | 미사용 에셋 보관 시간. 기본 24 | 기본값 사용 |

## 아직 없는 것

- 멱등 키의 **엔드포인트 연결**: 공통 코드(`app/idempotency.py`)와 `friends` 컬럼은 준비됐고, 생성 작업·친구 저장·대화 API를 만들 때 `docs/idempotency-design.md`를 따라 붙입니다.
- 요청 횟수 제한은 만들어 두었지만(`app/rate_limit.py`) 아직 어떤 라우터에도 붙어 있지 않습니다. 업로드·생성·대화 API를 만들 때 `Depends(limit_uploads)`, `Depends(limit_generations)`, `Depends(limit_messages)`를 붙이세요. 기록을 서버 메모리에 두므로 서버 1개 기준입니다.
- 실제 Supabase로의 **나머지 확인**: 로컬 Supabase와 클라우드 개발 프로젝트(Supavisor transaction mode, Storage, ES256 토큰, 레거시 `service_role` 키)에서는 확인했습니다. 결과는 `docs/supabase-cloud-setup.md`의 "클라우드 검증 결과"를 보세요. Google 로그인(Web 클라이언트, 브라우저 방식)도 클라우드 프로젝트에서 확인했습니다. 아직 못 본 것은 아이패드 앱의 iOS 네이티브 로그인, 레거시 HS256 토큰(실제 토큰), 새 `sb_secret_...` 키, 정리 작업의 클라우드 동작입니다.
