# 보글 Supabase 백엔드

보글의 DB·Auth·Storage를 정의하는 디렉터리입니다. 기준 문서는 `aidlc-docs/inception/requirements/requirements.md`입니다.

> 이전 제품 "오늘의 필름"의 스키마는 삭제했습니다 (D-06, 원격에는 적용된 적 없음). 보글 스키마는 담당 A(권희준)가 공통 뼈대 단계에서 `migrations/`에 새로 작성합니다. 이전 스키마는 git 이력에서 확인할 수 있습니다.

## 데이터 구조

작성 예정입니다. 스키마가 정해지면 이 섹션에 테이블과 관계를 적습니다.

## Storage

- 파일은 **비공개 bucket**에 둡니다. 앱에는 만료되는 서명 URL로만 제공합니다 (FR-01.5).
- 객체 경로는 `{user_id}/...`로 시작합니다 (FR-03.4). 경로의 첫 폴더가 `auth.uid()`와 같은 경우에만 접근할 수 있습니다.
- bucket 이름과 세부 경로 규칙은 스키마를 작성할 때 정하고 이 문서에 적습니다.

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

## 범위 밖

요구사항 문서의 범위 밖 항목(돌봄 수치, 찜, 주문·결제, 푸시 알림 등)은 스키마에 추가하지 않습니다.
