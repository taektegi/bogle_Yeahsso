# 통합 앱 연동 수정 — 2026-10-31

대상은 `seonghyun_real`이다. 사용자 지시로 기존 PRD의 수정 불가·고정 수면·즉시 삭제 정책을
이 브랜치에서 변경했다. 원본 `main`, `seonghyun_backend`, 별도 프론트 release는 변경하지 않았다.
초기 진단은 `integration-diagnosis.md`, 이번 수정의 계약과 결과는 이 문서가 기준이다.

## 요청별 처리

번호는 사용자가 수정 지시에서 사용한 번호다.

| 번호 | 결과 | 구현·검증 |
|---|---|---|
| 1 AI 생성 | **해결·실호출 검증 완료** | 사용자 정책 수정 후 실제 JPEG 생성·얼굴 분석·Storage 저장·다운로드·친구 저장 성공. [검증 기록](ai-generation-resolution.md) |
| 2 친구 저장 | 수정·검증 | 앱의 객관식 성격 문구를 `GET /v1/personality-types`의 코드로 변환해 `personalityType` 전송. PNG/JPEG 각각 실제 Dart 저장·동일 키 재전송 성공 |
| 3 친구 편집 | 수정·검증 | `PATCH /v1/characters/{id}` 추가. 이름·성격·소개·말투·수면 저장, 소유권·입력 검증. 대화도 수정된 설정 사용 |
| 4 DB 교착 | 요청대로 제외 | 삭제·정리의 잠금 순서는 변경하지 않음 |
| 5 수면 | 수정·검증 | 기본 21:00~07:00, 친구별 일정 저장, 앱 UTC 오프셋 사용. 상태 조회와 새 대화 거부가 같은 규칙 사용 |
| 6 Windows 경로 | 요청대로 제외 | iPad 목표. 기존 Windows 파일 판별 결함은 유지 |
| 7 삭제 | 수정·검증 | 기존 앱의 10초 전송 유예 유지. 유예 종료 후 로컬 복원 차단. 실제 9초 시점 서버 보존, 최종 검사에서 약 10.22초 뒤 삭제 확인 |
| 8 만료 processing | 요청대로 제외 | 오래된 작업 정리 코드는 변경하지 않음 |
| 9 모션 | 수정·검증 | 원격 구성도 `NoMotionService`를 사용해 기존 내장 애니메이션으로 연결. `/motion` 요청 0회 |

AI 오류는 `output/diagnosis/image-investigation-01.json`에 원문 없이 분류를 남겼다.
해당 파일의 `endpoints: []`는 당시 진단 도구가 메타데이터의 최상위 `endpoints`를 읽지 못한
관찰 한계이며 모델 부재의 증거가 아니다. 과금 없는 후속 조회에서는 OpenAI 제공자와
투명 배경·참조 이미지 지원을 확인했고, 도구의 응답 파싱을 수정했다.
당시에는 실제 생성 성공이 미검증이었다. 이후 사용자가 정책을 수정했고, 실제 생성과 서버
저장까지 성공했다. 세부 계정 토글은 직접 열람하지 않았고 에이전트가 데이터 공유 설정을 바꾸지 않았다.

## 최신 API 계약

### 만들기

앱은 서버 성격 목록의 `label`로 현재 선택을 찾고 `code`를 보낸다. 없는 선택을 임의의
성격으로 저장하지 않고 다시 선택하도록 오류를 반환한다. 기존 로컬 전용 친구 생성은 유지한다.

```json
{
  "generationJobId": "검증된 성공 작업의 UUID",
  "name": "구름이",
  "personalityType": "imaginative",
  "favoriteThings": ["그림"],
  "speechStyle": "해요체",
  "bedtime": 1260,
  "wakeTime": 420
}
```

`Idempotency-Key`는 같은 작업에서 기존 `friend-{jobId}` 값을 유지한다. 서버의 작업 소유권,
성공 상태, 이미지 연결, 작업 하나당 친구 하나 규칙도 유지한다.

### 편집

`PATCH /v1/characters/{id}`는 수정한 필드만 받는다. 생략한 필드는 유지하고 명시적 null,
알 수 없는 필드, 소유자·아트·생성 작업 등의 변경은 422로 거절한다. 남의 친구는 404다.

```json
{
  "name": "새 이름",
  "personality": "상상을 좋아해요",
  "introduction": "우리 같이 놀자!",
  "speechStyle": "반말",
  "bedtime": 1320,
  "wakeTime": 360
}
```

편집 이름은 앱처럼 앞뒤 공백만 제거하고 보이는 글자 기준 1~12자다. 최초 생성의 기존
이름 정규화 규칙은 유지한다. 편집 성격은 자유 입력 최대 30자, 소개는 최대 70자다.
DB에는 Unicode 조합 문자를 위한 느슨한 길이 상한을 두고 API에서 보이는 글자 수를 검사한다.
기존 객관식 문구로 편집하면 대응 코드를 쓰고 자유 문구면 `personalityType: "custom"`과
별도 `personality`를 저장한다. 응답의 `personality`·`personalityLabel`과 대화 프로필에 반영한다.

새 필드 `personality`, `bedtime`, `wakeTime`은 생성·목록·상세·수정 응답에 포함된다.

### 앱 말투 확장 — 2026-10-31 추가 승인

실제 iPad의 말투 선택 후 저장에서 422가 발생했다. 앱은 느낌·높임 조합을 보내지만 서버와
DB는 기존 세 말투만 허용한 것이 원인이었다. 사용자 승인으로 FR-05.1·FR-09.4·FR-11의
이 브랜치 계약을 확장했다. `POST /v1/characters`와 `PATCH /v1/characters/{id}`의
`speechStyle`은 기존 `반말`, `해요체`, `~지요!`를 유지하고 다음 여덟 값을 추가로 받는다.

| 앱 표시 | 편한 말 | 공손한 말 |
|---|---|---|
| 짧고 또렷하게 | `plain_casual` | `plain_polite` |
| 통통 튀게 | `bouncy_casual` | `bouncy_polite` |
| 동화 이야기처럼 | `story_casual` | `story_polite` |
| 로봇 친구처럼 | `robot_casual` | `robot_polite` |

이외의 값과 명시적 null은 계속 422로 거절한다. 새 값은 코드 그대로 저장·조회하며 대화
프로필에도 전달한다. AI에는 앱과 같은 느낌·높임의 한국어 지침을 전달하고, 호출 실패·안전
검사 차단 시에도 앱 카탈로그의 해당 말투 대사를 사용한다. 기존 세 말투의 대체 대사는 유지한다.
서버 배포 패키지에 포함되는 `server/app/speech_catalog.json`은 앱 카탈로그의 대화 주제만
담으며, 자동 테스트에서 앱 원본과 일치하는지 확인한다.

새 마이그레이션 `20261031051000_friend_speech_styles.sql`만 `bogle-dev`에 적용했다.
기존 마이그레이션·친구 데이터·RLS는 유지했으며 마이그레이션 기록도 같은 트랜잭션으로 남겼다.
다른 환경은 이 마이그레이션을 적용한 뒤 서버를 재시작한다. 현재 앱은 이미 새 값을 보내므로
이번 서버 말투 확장만으로 앱을 다시 설치할 필요는 없다.

로컬 PostgreSQL 전체 백엔드 검사 **468개 통과, 생략 없음**, Ruff 린트·포맷을 확인했다.
새 값의 저장·조회·수정, 중복 요청 재전송과 타인 접근 차단, AI 지침·대체 대사를 검사했다.
앱의 계약·API·말투 검사도 **47개 통과**했다. 실행 중인 서버에서 11개 말투 입력 검증을
완료했다. 존재하지 않는 작업 ID로 검증하여 친구를 추가 저장하지 않았고 실제 AI 호출도
없었다. 배포 패키지에 말투 카탈로그가 포함되는 것도 확인했다. 실제 AI의 자유 대화 품질과
iPad의 마지막 저장 버튼은 사용자 확인 범위다.

### 수면·삭제·모션

- `bedtime`·`wakeTime`은 자정부터의 정수 분(0~1439). 시작 시각 포함, 종료 시각 제외다.
  낮잠처럼 같은 날 끝나는 일정도 지원한다. 둘이 같으면 앱과 같이 항상 깨어 있고,
  상태 응답의 `nextChangeAt`은 null이다.
- 서버 현재 시각을 `X-Bogle-Utc-Offset-Minutes`로 변환한다. 앱이 기존에 보내던 헤더를 사용하며
  범위는 -840~840, 생략 시 540(한국 시간)이다. 기기의 벽시계 자체를 서버 시각으로 쓰지 않는다.
  새로운 대화는 수면 중 409. 이미 완료한 대화의 동일 키 재조회는 그대로 가능하다.
- 삭제는 앱에서 즉시 숨김 → 10초 동안 되돌리기 → Outbox가 DELETE 전송 → 서버 영구 삭제다.
  서버가 추가로 10초 기다리지 않는다. 유예가 끝나면 앱에서만 복원하는 동작도 거절한다.
  삭제를 되돌릴 때 이미지 정리 타이머도 취소한다. 빠르게 되돌린 뒤 재삭제해도 이전 타이머가
  새 유예 도중 이미지를 지우지 않도록 회귀 검사했다.
  **앱이 실행 중이고 온라인인 경우** 약 10초 뒤 삭제된다. 오프라인·종료 상태에서는 기존 앱처럼
  대기함에 보관하고 연결·재실행 시 전송하므로 정확한 10초 서버 삭제를 보장하지 않는다.
- 내장 애니메이션은 이미 `FriendScreen`의 클립 없는 경로에 구현되어 있다. 원격 GIF를 조회하지
  않도록 서비스 구성을 연결했다. 별도의 모션 서버나 GIF API는 추가하지 않았다.

## 검증 결과와 한계

| 검사 | 결과 | 증거 |
|---|---|---|
| 백엔드 전체 + 새 DB 통합 검사 | **358 통과, 생략 없음** | `output/diagnosis/fix-backend-tests.txt` |
| Ruff 검사·포맷 | **75개 파일 통과** | `ruff check --no-cache .`, `ruff format --check --no-cache .` |
| Flutter analyze | **문제 없음** | `output/diagnosis/fix-frontend-analyze.txt` |
| 기존 API 테스트 + 삭제 회귀 검사 | **27 통과 / 기존 Windows 이미지 crop 실패 1** | `output/diagnosis/fix-frontend-api-tests.txt` |
| 내장 동작·모션 서비스 테스트 | **85 통과** | `output/diagnosis/fix-motion-tests.txt` |
| 실제 Dart→HTTP→FastAPI→격리 PostgreSQL | **통합 시나리오 통과, 71개 HTTP 요청** | `output/diagnosis/fix-dart-http.json`, `fix-dart-http-tests.txt` |
| 실제 개발 Supabase Auth·Storage·DB | **저장·편집·권한·수면·삭제 통과, AI 0회** | `output/diagnosis/fix-live-friend-sync.json` |
| Playwright Swagger | 수정 API 표시·공개 health 200 | `output/playwright/friend-edit-swagger.png`, `friend-sync-health.yml` |

로컬 Dart 시험의 외부 인증·Storage·AI는 진단 구현이며 HTTP·Dart 클라이언트·FastAPI·PostgreSQL은
실제 구현이다. 그림·사진의 앱 저장, 저장 응답 유실 후 같은 ID 복구, 편집 왕복, 수면 거부,
타인 조회 차단, 10초 유예·되돌리기·삭제 후 대화 차단을 실행했다. 서버 모션 요청은 0회였다.

실제 Supabase 검증은 서버 API와 실제 Auth·Storage·DB를 사용했다. 합성 PNG와 이 실행 전용
성공 작업으로 저장·편집을 검증했으므로 **실제 AI 생성 성공이 아니다**. 수면 경계 시계는
검증 프로세스에만 주입했고, 실제 AI 대화를 호출하지 않았다. 전역 워커·복구·정리도 실행하지 않았다.
전용 계정 2개와 파일을 정리한 뒤, 원격에서 진단 계정 수 0을 별도로 확인했다.

이전 전체 Flutter 검사(583 통과 / 30 실패 / 3 생략)를 전부 다시 통과시켰다는 뜻은 아니다.
Windows 경로 문제는 요청대로 유지했다. iPad 실기기·iOS 빌드·카메라·Pencil 검증도 남아 있다.

## DB와 재실행

새 마이그레이션은 `supabase/migrations/20261030172223_friend_edit_sleep.sql`이다.
기존 마이그레이션을 수정하지 않고 `bogle-dev`(`nylnbctmhdfxswsgxmid`)에 적용했다.
적용 전후 친구 테이블 RLS는 활성 상태이며 기존 소유권 정책을 유지한다.
다른 환경에서는 이 마이그레이션을 먼저 적용한 뒤 서버 코드를 배포해야 한다.

기존 Supabase advisory 2건은 전후 동일했다. 서버 전용 worker lease의 정책 없는 RLS는
클라이언트 접근 차단을 위한 기존 설정이다. [설명](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).
Auth의 유출 비밀번호 검사 비활성화도 기존 설정이며 이번 범위에서 바꾸지 않았다.
[설명](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

로컬 서버·Dart 실행은 `integration-diagnosis.md`의 명령을 사용하되 출력 파일은
`fix-dart-http.json`처럼 새 이름으로 지정한다. 실제 Supabase 확인은 `server/`에서:

```powershell
python -B -m scripts.verify_friend_sync_live
```

이 스크립트는 기존 `fix-live-friend-sync.json`이 있으면 증거를 덮어쓰지 않고 중단한다.
키·토큰·암호·서명 URL은 프로그램 내부에서만 사용하고 출력하지 않는다.
`investigate_image_generation`의 `--generate`는 유료 실호출이다. 1번은 재개 승인 후 실제 서버
경로로 검증 완료했으며, 추가 재호출 전에 목적·횟수와 기존 호출 기록을 확인한다.

정리: 이번 검증의 전용 계정·파일, 임시 PostgreSQL DB·컨테이너·다운로드한 이미지,
진단 서버·브라우저, 앱 빌드 캐시와 중간 실패 로그를 제거했다. 최종 증거와 기존 파일은 보존했다.
설치된 SDK가 자동 변경한 원본 lock·analysis 설정도 복원했다. 사용한 Supabase CLI는 2.122.0이다.
