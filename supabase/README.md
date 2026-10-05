# 보글 Supabase 백엔드

보글의 DB·Auth·Storage를 정의하는 디렉터리입니다. 기준 문서는 `aidlc-docs/inception/requirements/requirements.md`입니다.

> 이전 제품 "오늘의 필름"의 스키마는 삭제했습니다 (D-06, 원격에는 적용된 적 없음). 보글 스키마는 담당 A(권희준)가 공통 뼈대 단계에서 `migrations/`에 새로 작성합니다. 이전 스키마는 git 이력에서 확인할 수 있습니다.

## 데이터 구조

공통 뼈대(`20261005000100_core_schema.sql`, `20261005000200_assets.sql`)가 만드는 테이블입니다. 생성 작업(담당 B), 대화·모션(담당 C) 테이블은 각 담당이 새 마이그레이션으로 추가합니다.

- `profiles`: `auth.users`와 1:1인 아이 프로필 (FR-02). 처음 로그인하면 트리거(`handle_new_user`)가 자동으로 만들고 닉네임은 `그린고블린`입니다.
  - `nickname`: 공백을 제거한 1–12자
  - `avatar_friend_id`: 내 친구 중 하나. `null`이면 기본 아바타이고, 지정한 친구가 삭제되면 `null`로 돌아갑니다.
  - `friend_notifications`, `order_notifications`: 알림 설정값만 저장합니다.
- `friends`: 사용자가 만든 캐릭터 친구 (FR-05, FR-06).
  - 설정값: `name`, `personality_type`, `favorite_things`(1개 이상), `speech_style`(`~지요!` / `해요체` / `반말`)
  - `introduction`: 소개 문구(최대 70자). 생성에 실패하면 빈 문자열입니다.
  - `source_asset_id`(선택), `art_asset_id`, `thumbnail_asset_id`: `assets`의 행을 가리킵니다. 내 에셋만 가리킬 수 있고, 에셋 하나는 친구 한 명에게만 속합니다. 에셋의 `kind`가 맞는지는 API가 검사합니다.
  - `accent_argb`: 대표색 ARGB. 부호 없는 32비트라서 `bigint`입니다.
  - `generation_job_id`: 친구 생성 작업 ID. 유일하므로 작업 하나로는 친구 하나만 만들 수 있습니다. 작업 테이블이 생기면 담당 B가 외래 키를 추가합니다.
  - 친구 설정은 저장 후 바뀌지 않습니다 (D-24). 갱신되는 것은 `introduction`뿐입니다.

- `assets`: 이미지 파일 한 건당 한 행. 업로드 원본, 생성된 캐릭터 아트·썸네일, 모션 GIF를 모두 여기서 관리합니다.
  - `kind`: `source`(업로드 원본), `art`(생성된 투명 PNG), `thumbnail`, `motion`(담당 C)
  - `storage_path`: 비공개 bucket 안의 객체 경로. 항상 `{user_id}/`로 시작해야 하고 유일합니다.
  - `content_type`(`image/png`·`image/jpeg`·`image/gif`), `byte_size`, `width`, `height`: 업로드할 때 서버가 검사한 값을 기록합니다.
  - 앱에는 `assetId`와 만료되는 서명 URL로만 제공합니다.
  - `delete_requested_at`: 친구를 삭제하면 그 친구의 에셋에 채워집니다. 파일 삭제가 실패해 행이 남더라도, 정리 작업이 이 표시가 있는 에셋을 나이와 상관없이 바로 다시 지웁니다.

관계는 `auth.users -> profiles`, `auth.users -> assets`, `auth.users -> friends -> assets`입니다. 사용자를 삭제하면 프로필·에셋·친구가 함께 삭제됩니다. 친구를 삭제할 때 대화·모션 기록은 각 테이블이 `friends`를 `on delete cascade`로 참조해서 함께 지웁니다.

### 파일 삭제 순서
**Storage 파일은 DB가 지우지 못하므로 서버가 Storage API로 직접 삭제합니다** (FR-06.3). 행을 지우면 경로를 잃으므로 순서를 지켜야 합니다.

1. 지울 친구의 `assets`(원본·아트·썸네일·모션) 경로를 먼저 조회합니다.
2. 친구를 삭제합니다. 친구가 참조 중인 에셋은 먼저 지울 수 없습니다.
3. Storage에서 파일을 삭제합니다.
4. `assets` 행을 삭제합니다.

계정 삭제(운영자가 시연 후 정리)도 같습니다: `auth.users`를 지우기 **전에** 그 사용자의 `assets.storage_path`를 조회해서 Storage 파일부터 지웁니다. 미사용 업로드 정리(FR-04.8)는 서버가 1시간마다 자동으로 합니다(`server/app/cleanup.py`): 아무 친구도 쓰지 않는 에셋 중 **만든 지 24시간이 지난 것**과 **삭제 요청 표시가 있는 것**을 Storage 파일 → 행 순서로 지웁니다.

> 다른 테이블이 에셋을 가리키게 되면(생성 작업, 모션 결과 등) `server/app/cleanup.py`의 `ASSET_REFERENCES`에 조건을 추가해야 합니다. 그렇지 않으면 그 에셋이 24시간 뒤에 지워집니다.

### 쓰기는 서버만 한다
앱(`authenticated`)에는 `select` 권한과 "내 것만" 읽는 정책만 있습니다. 삽입·수정·삭제는 FastAPI 서버가 `service_role` 키로 합니다. 앱이 PostgREST로 직접 쓰려고 하면 권한 오류가 납니다.

## Storage

- bucket `bogle-media`는 **비공개**입니다. 앱에는 서버가 만든 만료되는 서명 URL로만 제공합니다 (FR-01.5).
- 객체 경로는 `{user_id}/...`로 시작합니다 (FR-03.4). 경로의 첫 폴더가 `auth.uid()`와 같은 경우에만 읽을 수 있습니다.
- 업로드와 삭제는 서버가 Storage API로 합니다. 앱에는 쓰기 정책이 없습니다.
- 객체 경로는 **ASCII만** 씁니다. 한글·공백이 든 경로는 Storage가 거부합니다(실제 Supabase에서 확인). 업로드한 파일 이름을 경로에 넣지 말고 UUID로 만듭니다.
- 경로의 나머지 규칙(예: `{user_id}/{friend_id}/...`)은 업로드를 만드는 담당 B가 정하고 이 문서에 적습니다.

## RLS 원칙

- 모든 public 테이블에 RLS를 켭니다.
- 인증 사용자는 자신의 데이터만 접근합니다. 정책은 `(select auth.uid()) = user_id` 형태를 씁니다.
- 자식 테이블은 상위 레코드의 소유권도 함께 검사합니다.
- 클라이언트에는 publishable(anon) 키만 쓰고 `service_role` 키는 서버의 `.env`에만 둡니다. 커밋하지 않습니다.

## 마이그레이션

- 파일은 `migrations/`에 타임스탬프 순서로 저장합니다.
- 이미 머지된 마이그레이션은 수정하지 않고 새 파일로 추가합니다.
- 마이그레이션 번호·순서는 공용 파일입니다. 추가하기 전에 팀 채널에 알립니다 (`AGENTS.md` 참고).

로컬 Docker 환경과 Supabase CLI가 준비된 경우:

```bash
supabase start
supabase db reset
```

`db reset`은 로컬 개발 DB에만 사용하세요. 연결된 원격 프로젝트에는 실행하지 않습니다.

원격 프로젝트에 적용하려면 먼저 프로젝트 ref를 확인하고 연결한 뒤 실행합니다. 개발용과 시연용 프로젝트는 분리합니다 (NFR-11).

```bash
supabase link --project-ref <project-ref>
supabase db push
```

### 로컬 설정 (`config.toml`)

`config.toml`은 `supabase init`의 기본값에서 `project_id = "bogle"`만 바꿨습니다. 로컬 검증에 영향을 주는 기본값은 다음과 같습니다.

- `[auth] enable_signup = true`, `[auth.email] enable_confirmations = false`: 이메일 가입이 바로 되고 확인 메일을 기다리지 않습니다 (로컬 전용 설정).
- `[auth] jwt_expiry = 3600`: 액세스 토큰은 1시간입니다.
- `[db.pooler] enabled = false`: pooler는 꺼져 있습니다. 필요하면 `true`로 바꾸고 `supabase stop` → `supabase start` 합니다.
- Google OAuth(`[auth.external.google]`)는 켜지 않았습니다. 앱의 Google 로그인은 로컬에서 확인하지 못했습니다.

### 로컬 검증 결과

**실제 Supabase(CLI 2.117, Postgres 17, 로컬 Docker)에서 확인함** (2026-10-05).

- `supabase db reset`으로 마이그레이션 4개가 오류 없이 적용됩니다.
- `profiles`·`friends`·`assets` 모두 RLS가 켜져 있고, `authenticated`는 SELECT 정책만 있습니다. `anon`에는 권한이 없습니다. 사용자 토큰으로 PostgREST에 `POST`·`PATCH`·`DELETE`를 하면 403입니다.
- `storage.buckets`에 `bogle-media`가 `public = false`로 있고, `bogle_media_select_own` 정책으로 내 폴더(`{userId}/...`)만 읽을 수 있습니다. 사용자 토큰으로는 업로드도 거부됩니다 (쓰기는 서버만).
- `auth.users`에 `on_auth_user_created` 트리거가 붙어 있어 가입 직후 `profiles`가 생깁니다.
- 로컬 Auth는 **ES256** 토큰을 발급하고 `iss`는 `http://127.0.0.1:54321/auth/v1`, `aud`는 `authenticated`입니다. 서버가 JWKS로 검증합니다.
- Storage 실제 응답은 서버 가정과 같습니다: 서명은 `[{error, path, signedURL}]`(없는 객체는 HTTP 200에 `signedURL: null`), 업로드·삭제는 HTTP 200이고 이미 없는 객체 삭제는 `[]`입니다. 서명·업로드는 `Authorization`·`apikey` 중 하나만 있어도 되지만 둘 다 보냅니다. 객체 키는 한글·공백이 있으면 거부됩니다 (서버 경로는 ASCII UUID라 해당 없음).
- Storage 파일 이름에 `x-upsert` 없이 같은 경로를 올리면 409(`Duplicate`)이고, 서버는 항상 `x-upsert: true`로 올립니다.

## 범위 밖

요구사항 문서의 범위 밖 항목(돌봄 수치, 찜, 주문·결제, 푸시 알림 등)은 스키마에 추가하지 않습니다.
