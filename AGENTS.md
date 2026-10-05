# AGENTS.md — 보글(Bogle) 백엔드

세 명이 각자 AI 에이전트(Codex, Claude Code)로 개발한다. 이 파일은 **모든 에이전트가 같은 규칙으로 일하게 하는 공통 규칙**이다.
작업을 시작하기 전에 이 파일과 아래 "먼저 읽을 문서"를 읽는다.

> 이 파일은 초안이다. 규칙을 바꾸거나 추가할 때는 팀 채널에 먼저 알리고, 작은 PR로 올린다.

## 프로젝트 한눈에 보기

- 아이가 그린 그림·사진으로 AI 캐릭터 친구를 만들고, 보관함에서 관리하고, 대화하는 앱 **보글**의 백엔드다.
- 시연용 데모다. 2주 일정, 3인 개발, 시연용 계정만 사용하며 실제 아동 데이터는 받지 않는다.
- 스택: **Supabase**(Postgres·Auth·Storage) + **Python FastAPI** API 서버 + **OpenAI**(이미지·대화·모더레이션) + 모션 파이프라인(백엔드에 통합).
- Flutter 앱은 별도 저장소(`quasiaward/Bogle_doll_making_app`, 기준 브랜치 `main-develop`)에 있고, 백엔드 담당 3명이 연동 코드까지 작성한다.

## 먼저 읽을 문서

| 문서 | 내용 |
|---|---|
| `aidlc-docs/inception/requirements/requirements.md` | **기준 문서.** 결정 사항(D-xx), 기능 요구사항(FR-xx), 비기능 요구사항(NFR-xx), 범위 밖 |
| `TEAM_SPLIT.md` | 3인 분업(안 2: 기능별)과 협업 규칙 |
| `aidlc-docs/inception/reverse-engineering/` | 기존 Flutter 앱·모션 서버 분석 (아키텍처, API, 코드 구조) |

요구사항과 코드가 다르면 **요구사항 문서가 기준**이다. 요구사항 자체가 틀렸거나 모호하면 임의로 해석하지 말고 사람에게 묻는다.
작업 중 요구사항 번호(예: FR-06.3)를 PR 설명에 적어서 어떤 요구를 구현했는지 보이게 한다.

## 담당 분업

| 담당 | 이름 | 맡는 기능 (DB → API → Flutter까지) | 요구사항 |
|---|---|---|---|
| A — 계정·보관함 | 권희준 | 로그인·세션, 프로필, 보관함 목록, 영구 삭제, 수면 상태, 공통 뼈대 | FR-01, 02, 06, 08 |
| B — 친구 만들기 | 김성현 | 업로드, 친구 생성 작업(OpenAI 이미지), 초기 설정, 친구 저장, 소개 문구 | FR-03, 04, 05 |
| C — 대화·모션 | 김택수 | 생성형 대화, 대화 기록, 모션 파이프라인 | FR-09, 10 |

- 지금 작업하는 사람의 담당 기능만 구현한다. 다른 사람 담당 영역의 코드는 **고치지 말고** 필요한 변경을 PR 설명이나 팀 채널에 적는다.
- FR-11(Flutter 연동)은 각자 맡은 기능의 앱 쪽 작업을 나눠 맡는다.
- 다른 사람의 기능이 아직 없으면 시드 데이터(테스트용 계정·친구)로 작업한다. 예: 김택수는 친구 저장이 끝나기 전까지 시드 친구로 대화를 개발한다.

## 하지 말 것 (범위 밖)

요구사항 문서의 범위 밖 항목은 **만들지 않는다.** 코드·테이블·API·화면 어디에도 추가하지 않는다.

- 돌봄 수치(기분·배부름·기운·친밀도), 레벨·추억, 쓰다듬기·초대 (D-13, D-14)
- 친구 정보 수정 API, 찜 (D-24). 친구 설정은 한 번 정하면 바뀌지 않는다
- 삭제 취소·"다시 데려오기" (D-21). 삭제는 즉시 영구 삭제다
- 인형 주문·결제·배송 (D-22). 앱의 mock 주문 화면은 그대로 둔다
- 푸시 알림, 동의 기록, 회원 탈퇴, 친구별 수면 일정 편집
- 대화로 캐릭터 설정 바꾸기, 장기 기억 요약·검색 (D-17)
- `supabase/`의 "오늘의 필름" 테이블(`films`, `film_*`)에 새 코드를 기대지 않는다. 다른 제품용이라 삭제 후 보글 스키마로 새로 만든다 (D-06). 이 정리는 담당 A가 맡는다

## 지켜야 할 규약

### 인증과 소유권 (FR-01)
- 모든 API는 Supabase 액세스 토큰을 검증하고, **사용자 ID는 토큰에서만** 얻는다. 요청 body·query의 사용자 ID는 쓰지 않는다.
- 친구·파일·작업·메시지는 모두 소유자를 가진다. 다른 사람의 리소스는 404 또는 403으로 막는다. 새 엔드포인트마다 이 차단 테스트를 쓴다.
- 파일은 비공개 버킷에 두고, 앱에는 **만료되는 서명 URL**로만 준다. 경로는 `{userId}/...`로 시작한다.
- 모든 public 테이블에 RLS를 켠다.

### API 형식 (NFR-10)
- 경로는 `/v1` 접두어. JSON 필드는 **camelCase**. 시각은 UTC ISO 8601.
- 오류 형식은 항상 `{"error": {"code", "message", "retryable", "fieldErrors", "requestId"}}`.
- 생성 요청은 `Idempotency-Key`, 대화는 `clientMessageId`로 중복을 막는다. 같은 요청을 다시 받으면 이전 결과를 돌려준다.
- API 계약의 기준은 FastAPI가 만드는 OpenAPI 문서(`/docs`)다. 요청·응답 모델은 Pydantic으로 명시하고, 계약을 바꾸면 팀 채널에 바로 알린다.
- 사용자에게 보이는 문구와 오류 메시지는 한국어, 코드·식별자·로그 필드는 영어.

### 비밀 정보와 로그 (NFR-03, NFR-05, NFR-09)
- OpenAI 키·Supabase `service_role` 키는 서버의 `.env`에만 둔다. **절대 커밋하지 않는다.** 앱에는 Supabase publishable(anon) 키와 API 주소만 넣는다.
- 새 환경변수를 추가하면 값 없는 `.env.example`에도 이름을 적는다.
- 그림·사진·대화 본문은 일반 로그에 남기지 않는다. 요청마다 `requestId`, 작업 로그에는 `jobId`를 남긴다.
- OpenAI 오류나 스택 추적을 사용자 응답에 그대로 내보내지 않는다.

### AI 호출
- 친구 생성 작업 상태: `queued → processing → succeeded | failed | cancelled`. 결과 파일을 실제로 읽을 수 있을 때만 `succeeded`.
- 대화: 사용자 입력과 AI 답변을 모두 OpenAI Moderation으로 검사하고, 문제가 있거나 호출이 실패·시간 초과되면 스크립트 대사로 대체한다. 시스템 프롬프트에는 아이 대상 안전 지침을 넣는다.
- 모션은 선택 기능이다. 모션이 실패해도 친구 생성·저장은 성공해야 한다 (FR-10.5).
- 사용자별 생성·대화 횟수 제한을 둔다. 초과하면 429.

### 시간
- 수면 시간(22:00–06:00)은 **Asia/Seoul** 기준이고 판정은 서버 시각으로 한다.

## 공용 파일 규칙

아래 파일은 여러 기능이 함께 쓰므로 **임의로 고치지 않는다.** 고쳐야 하면 먼저 팀 채널에 알리고, 가능하면 담당 A(권희준)가 반영한다.

- 마이그레이션 번호·순서 (`supabase/migrations/`) — 파일명은 타임스탬프 순서를 지키고, 이미 머지된 마이그레이션은 수정하지 않고 새 파일로 추가한다
- FastAPI 라우터 등록, 공통 미들웨어(토큰 검증·오류 형식)
- Flutter의 친구 모델 `CharacterFriend`, `app.dart`, API 클라이언트
- 이 파일(`AGENTS.md`)과 `requirements.md`

공용 뼈대는 담당 A가 1~2일차에 먼저 만든다. 뼈대가 올라오기 전에는 그 부분을 각자 따로 만들지 말고 기다리거나, 인터페이스만 가정해서 작업한다.

## 작업 방식

- 작업은 **기능 브랜치 → 작은 PR → 다른 한 명이 훑어본 뒤 머지**. `main`에 직접 푸시하지 않는다.
- PR은 하루 한 번 이상 `main`에 합친다. 크고 오래 떠 있는 PR은 AI가 만든 큰 diff끼리 충돌한다.
- 브랜치 이름: `feature/<담당영역>-<내용>` (예: `feature/archive-delete`, `feature/friend-generation-job`).
- 커밋 메시지: 한 줄 요약(영어 또는 한국어, 명령형) + 필요하면 본문. 한 커밋은 한 가지 변경만 담는다.
- PR 설명에는 구현한 요구사항 번호, 직접 확인한 방법, 공용 파일을 건드렸는지를 적는다.
- 작업 시작 전 `git pull`로 최신 `main`을 받고, 끝낼 때 충돌이 없는지 확인한다.
- 변경은 **요청받은 범위만** 한다. 관련 없는 파일 정리·포맷 변경·리팩터링을 섞지 않는다.

## 테스트와 검증

테스트 범위는 핵심 경로로 한정한다 (NFR-02).

- 필수 자동 테스트: ① 다른 사용자의 리소스 접근 차단 ② 친구 생성 → 저장 흐름 ③ 대화의 중복 요청·스크립트 대체 ④ 삭제 시 연쇄 삭제
- 새 코드를 쓰면 실제로 실행해서 확인한다. 실행하지 않은 것을 "동작한다"고 보고하지 않는다.
- 외부 서비스(OpenAI, Supabase)를 부르는 테스트는 기본적으로 mock을 쓰고, 실제 호출은 직접 확인할 때만 한다.
- AI가 "완료"라고 해도, 머지 전에 사람이 시연 흐름을 실제 앱에서 눌러 본다.

## 명령어

API 서버 명령은 모두 `server/`에서 실행한다 (Python 3.11+). 자세한 설명은 `server/README.md`.

```bash
cd server
python -m venv .venv && source .venv/bin/activate   # Windows PowerShell: .venv\Scripts\Activate.ps1
pip install -e ".[dev]"                             # 최초 1회
cp .env.example .env                                # 값을 채운다. .env는 커밋하지 않는다

uvicorn app.main:app --reload --no-access-log       # 실행. 문서는 http://localhost:8000/docs
ruff check . && ruff format --check .               # 린트·포맷 검사 (고칠 때는 ruff format .)

# DB 테스트까지 돌리려면 임시 DB를 만들 수 있는 연결 문자열이 필요하다 (supabase start 의 로컬 DB 예시)
export TEST_DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres
pytest                                              # 테스트
```

**PR을 올리기 전에 `TEST_DATABASE_URL`을 켠 채로 `pytest`와 `ruff`가 모두 통과해야 한다.** `TEST_DATABASE_URL`이 없으면 DB 테스트(소유권 차단 포함)가 건너뛰어진다.

**CI**: PR을 올리거나 `main`에 푸시하면 GitHub Actions(`.github/workflows/ci.yml`)가 같은 검사(`ruff`, `pytest` + 실제 PostgreSQL)를 자동으로 돌린다. PR 화면에 ❌가 나오면 **머지하지 않고** 고친다. CI는 로컬에서 미리 돌려 보는 것을 대신하지 않는다 (CI는 실제 Supabase·Storage·OpenAI를 확인하지 못한다).

DB (Supabase CLI):

```bash
supabase start        # 로컬 Supabase 실행 (Docker 필요). 아직 supabase/config.toml이 없다
supabase db reset     # 로컬 DB만 초기화. 원격 프로젝트에는 절대 실행하지 않는다
supabase db push      # 원격에 적용. supabase link로 프로젝트를 확인한 뒤에만 실행
```

## 폴더 구조

```text
aidlc-docs/   요구사항·분석 문서 (문서만 둔다)
.github/     CI 설정 (workflows/ci.yml)
docs/         프론트엔드와 주고받는 API 계약 등 협업 문서 (frontend-api-reply.md, flutter-repository-proposal.md)
supabase/     DB 마이그레이션 (migrations/)과 DB 설명 (README.md)
server/       FastAPI 서버
  app/          main.py, config.py, auth.py, db.py, storage.py, assets.py, cleanup.py, rate_limit.py, errors.py, request_context.py, schemas.py
  app/repositories/  DB 쿼리 (모든 함수가 user_id로 소유자를 거른다)
  app/routers/  기능별 라우터. __init__.py의 api_routers에 한 줄 추가해서 등록한다
  tests/        pytest. probe.py는 테스트 전용 라우터
```

- 애플리케이션 코드는 저장소 루트 아래에 둔다. **`aidlc-docs/`에는 문서만** 둔다.
- 새 API는 `server/README.md`의 "새 API를 만들 때" 순서를 따른다. 로그인이 필요한 API는 `CurrentUserDep`을 받고, 사용자 ID는 `user.id`(토큰)만 쓴다.
- **서버는 DB에 직접 연결해서 RLS가 적용되지 않는다.** repository의 모든 쿼리에 소유자(`user_id`) 조건을 직접 걸고, 남의 리소스를 요청하는 DB 테스트를 함께 쓴다.
- 오류는 `ApiError`로 내고, 요청·응답 모델은 `CamelModel`을 상속한다.
- 다른 테이블이 `assets`를 가리키게 만들면 `server/app/cleanup.py`의 `ASSET_REFERENCES`에 조건을 추가한다. 그렇지 않으면 정리 작업이 그 에셋을 24시간 뒤에 지운다.
- 불필요한 파일(`.DS_Store`, `.env`, 빌드 산출물)은 커밋하지 않는다 (`.gitignore`에 설정돼 있다).

## 사람에게 먼저 물어볼 것

다음은 AI가 혼자 결정하지 말고 물어본다.

- 요구사항 문서와 어긋나거나 범위 밖 기능이 필요해 보일 때
- 다른 사람 담당 영역·공용 파일을 바꿔야 할 때
- 이미 머지된 마이그레이션이나 API 계약을 바꿔야 할 때
- 새 외부 서비스·큰 의존성 추가, 원격 Supabase 프로젝트 변경
- 요구사항의 미결 항목(OI-01~09: 성격 유형 목록, 모델 선택, 횟수 제한값 등)을 확정해야 할 때
