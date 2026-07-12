# 오늘의 필름 Supabase 백엔드

## 데이터 구조

- `profiles`: `auth.users`와 1:1인 서비스 프로필. Auth 사용자 생성 시 트리거로 자동 생성됩니다.
- `films`: 사용자가 사진과 AI 대화로 만드는 하루의 필름 기록입니다. 같은 날짜에 여러 기록을 만들 수 있습니다.
- `film_photos`: film에 속한 사진의 Storage 경로와 표시 순서를 저장합니다. film당 대표 사진은 최대 하나입니다.
- `film_sessions`: film과 1:1인 AI 대화 세션입니다. 대화의 진행 상태와 시작·완료 시각을 저장합니다.
- `film_messages`: 세션에 속한 사용자/assistant 메시지입니다. 세션 안에서 순서가 유일합니다.

관계는 `auth.users -> profiles`, `auth.users -> films -> film_photos`, `films -> film_sessions -> film_messages`이며 자식 레코드는 부모 삭제 시 함께 삭제됩니다.

## Storage

비공개 bucket `film-media`를 사용합니다. 객체 경로는 다음 규칙을 따릅니다.

```text
{user_id}/{film_id}/{category}/{file_name}
```

`category`는 `original`, `thumbnail`, `export` 등을 사용할 수 있습니다. 실제 업로드와 삭제는 Storage API로 수행하며 DB 내부 객체 테이블에 직접 파일 행을 추가하지 않습니다.

## RLS 원칙

모든 public 테이블에 RLS가 활성화되어 있습니다. 인증 사용자는 자신의 프로필, film, AI 대화 세션과 메시지만 접근할 수 있습니다. 사진은 연결된 film의 소유권으로 검사합니다. AI 대화 세션과 메시지는 직접 저장된 `user_id`뿐 아니라 연결된 상위 레코드의 소유권도 함께 검사합니다.

Storage 객체는 `film-media` bucket이면서 경로의 첫 폴더가 `auth.uid()`와 같은 경우에만 읽기와 쓰기가 가능합니다. 클라이언트에는 publishable/anon key만 사용하고 `service_role` key를 노출하지 않습니다.

## 마이그레이션 적용

로컬 Docker 환경과 Supabase CLI가 준비된 경우:

```bash
supabase start
supabase db reset
```

`db reset`은 로컬 개발 DB에만 사용하세요. 연결된 원격 프로젝트에는 실행하지 않습니다.

원격 프로젝트에 적용하려면 먼저 프로젝트 ref를 확인하고 연결한 뒤 실행합니다.

```bash
supabase link --project-ref <project-ref>
supabase db push
```

마이그레이션은 `migrations` 디렉터리에 시간순으로 저장됩니다. 최초 스키마 이후의 보안·성능 보강도 함께 적용해야 합니다.

## 의도적으로 제외한 기능

- Flutter 애플리케이션 코드
- OpenAI API 및 AI 생성 로직
- 기억 포인트와 임베딩
- pgvector 검색
- 그래프뷰와 과거 필름을 꺼내 상기시키는 회고 기능
- 실제 사진 업로드/변환 처리
