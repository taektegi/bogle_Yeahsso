# 보글 프론트·백엔드 통합 진단

검증일: 2026-10-31, Asia/Seoul. 기능 수정 없이 원본 release와 팀 main을 함께 실행한 결과다.

## 1. 무엇을 합쳤나

| 대상 | 기준 |
|---|---|
| 저장소 | `taektegi/bogle_Yeahsso` |
| `seonghyun_backend` | 원격 main `a6aca1690b42095d026c14874a3c326cc89ea5a2`와 같은 커밋 |
| `seonghyun_real` | 위 커밋에서 분기한 통합·진단 브랜치 |
| 포함한 프론트 | `quasiaward/Bogle_doll_making_app`, release `5d1b9c7b59441ac0fe7983957af774114fb9c8dd` |
| 프론트 보존 | 원본 추적 파일 430개의 바이트를 그대로 유지. 별도 진단 테스트 1개만 추가 |

계획 중 확인했던 프론트 `5742ba5`보다 새 커밋이 있어서 실행 시작 시 pull한 최신 release를 고정했다.
`main`, 기존 `seonghyun`, 원본 프론트 release에는 작업을 올리지 않는다. 출처는
`integration-provenance.json`에도 기록한다. 기존 백엔드 운영 코드와 마이그레이션은 바꾸지 않았다.

```text
seonghyun_real 저장소 루트
├─ server/              원본 FastAPI + 별도 진단 도구·관찰 테스트
├─ supabase/            원본 마이그레이션
├─ frontend/            원본 Flutter release + 별도 HTTP 관찰 테스트
├─ docs/                기준 문서·이 보고서
└─ output/              비밀값을 제외한 실행 증거
```

현재 release README와 기존 계약 테스트는 별도 개인 백엔드 `quasiaward/bogle_backend_try`를
기준으로 한다. 같은 제품 이름·같은 URL 접두어를 쓰더라도 팀 main과 같은 계약이 아니다.
이번 진단에서는 양쪽 요구를 임의로 합치지 않고, 팀 main의 공개 명세와 실제 release 요청을 비교했다.

## 2. 실제로 실행한 범위

환경: Windows, Python 3.13.12, Flutter 3.47.6 / Dart 3.13.5,
Docker PostgreSQL 16.15. iOS·웹·Windows 앱 runner를 새로 만들지 않았다.
Windows의 Flutter 테스트 엔진에서 위젯과 실제 Dart HTTP 코드는 실행할 수 있지만,
iOS 바이너리·iPad 시뮬레이터·Apple Pencil·네이티브 카메라·마이크 동작을 검증한 것은 아니다.

| 검사 | 결과 | 증거 |
|---|---|---|
| 기존 백엔드 전체 | 336 통과, DB 생략 없음 | 초기 실행 후 아래 338개로 재확인 |
| 백엔드 + 관찰 테스트 | **338 통과**, DB 생략 없음 | `output/diagnosis/backend-tests.txt` |
| Ruff 검사·포맷 | 72개 Python 파일 통과 | 동일 명령으로 재실행 가능 |
| Flutter analyze | **문제 없음** | `output/diagnosis/frontend-analyze.txt` |
| Flutter 전체 단위·위젯 | **583 통과 / 30 실패 / 3 생략** | `frontend-tests.txt`, `frontend-failures.json` |
| 별도 실제 Dart HTTP 관찰 | **1개 시나리오 통과, 20개 관찰, 65개 HTTP 요청 기록** | `dart-http-tests.txt`, `dart-http.json` |
| 삭제·정리/만료 관찰 | **2개 현상 재현** | `concurrency-tests.txt`, 관찰 테스트 코드 |
| Playwright | 실제 Swagger 로딩·health 실행·HTTP 200 | `output/playwright/swagger-health.png`, `swagger-health.yml` |
| 실제 Supabase·AI | 아래 결과 참조 | `output/diagnosis/live-services.json`, `live-budget.json` |

관찰 테스트의 통과는 **문제가 고쳐졌다는 뜻이 아니다**. 예를 들어 저장 422와 교착이 실제로
재현되면 관찰 테스트는 통과한다. 기존 프론트 계약 스냅샷은 덮어쓰지 않았다.
전체 Flutter 검사 당시 외부 연결 설정이 없는 새 관찰 테스트도 생략 3개에 포함됐고,
그 테스트는 이후 실제 진단 서버에 연결해 별도로 통과시켰다.

프론트 작성 기준은 Flutter 3.41.5다. 설치된 SDK는 3.47.6이라 `pub get`이 SDK에 묶인
matcher 0.12.19→0.12.20, meta 1.17.0→1.19.0, test_api 0.7.10→0.7.12,
vector_math 2.2.0→2.4.4를 재해석했다. SDK 업그레이드는 하지 않았다.
검증에 사용한 해석 결과는 `output/diagnosis/windows-resolution.lock`에 보존하고,
커밋되는 `frontend/pubspec.lock`과 자동 변경된 analysis 설정은 원본으로 돌려뒀다.
따라서 아래 실패가 iPad에서도 똑같이 발생한다고 단정하지 않는다.

## 3. 실제로 확인된 문제

### D-01 — 친구 저장이 422로 막힌다: 우선순위 높음

- 재현: Dart `SyncedCharacterRepository.createFriend()`를 그대로 호출한다. 그림과 사진 모두 재현됐다.
- 기대: 생성된 작업으로 친구를 저장한다.
- 실제: `validation_error`, `fieldErrors.personalityType = missing`.
- 원인: 앱은 표시 문구를 `personality`로 보내지만 팀 서버는 코드형 `personalityType`을 필수로 받는다.
- 영향: 업로드·생성·PNG/썸네일/얼굴 지도 다운로드가 성공해도 친구 저장에서 멈춘다.
- 권장 수정: 앱의 선택 표시와 서버 코드를 분리하고 서버 목록 응답을 저장 요청에 연결한다.
  변경 후보는 `synced_character_repository.dart`, 설정 선택 데이터다. 이번에는 변경하지 않았다.

앱 요청이 실패한 뒤 별도의 **서버 규격 요청**으로 저장·멱등 재전송을 확인했다.
앱의 실패를 성공으로 바꾸거나 두 검증을 하나로 보고하지 않는다.

### D-02 — 친구 편집이 로컬에만 반영되고 전송 목록에서 사라진다: 우선순위 높음

- 재현: 서버에 저장한 친구를 앱으로 내려받고 `saveFriend()`로 이름을 바꾼다.
- 실제: `PATCH /v1/characters/{id}`는 **405**. 로컬 이름은 변경되지만 서버 이름은 그대로다.
  Outbox는 재시도 불가능한 4xx로 판단해 항목을 버려 `pending=0`이 된다.
- 원인: 앱이 기대하는 수정 API가 팀 main에는 없다. 소개 문구 덮어쓰기와 개별 수면 수정도 같은 경로다.
- 영향: 아이패드에서 보는 설정과 서버 대화에 사용하는 설정이 달라질 수 있다.
- 권장 수정: 팀 main의 수정 불가 정책에 맞춰 앱 동작을 정리하거나 제품 계약을 별도로 재합의한다.
  수정 API를 임의로 추가하지 않는다. 후보는 저장소 구현·Outbox·편집 화면이다.

### D-03 — 서버 모션 API와 일부 계약이 서로 다르다

- 재현: 실제 `ApiMotionService.clipsFor()` 호출 → 모션 경로 **404** → 앱 기본 모션으로 대체된다.
- 팀 서버는 생성 시 `face`만 제공하며 GIF 모션 API를 제공하지 않는다.
- 스냅샷에는 있지만 실제 팀 서버에는 없는 메서드는 ready 검사, 친구 PATCH, 모션 GET,
  asset 개별 GET이다. 이 중 모션 호출은 실제 HTTP로 확인했고 나머지는 명세 비교 결과다.
- 생성 결과·프로필·대화 응답의 속성 집합은 대체로 맞지만 Character에는 프론트 전용
  `personality`, `bedtime`, `wakeTime`이 있다. 필드 집합 비교가 타입·동작 전체 호환을 보장하지는 않는다.
- 증거: `output/diagnosis/contract-diff.json`. 권장 수정은 미지원 호출 제거와 계약 스냅샷 재합의다.

### D-04 — 삭제·수면의 의미가 다르다

- 재현: 앱 `deleteFriend()` 직후 서버를 조회하면 친구가 여전히 존재한다.
- 원인: 앱은 **10초 복구 창** 동안 삭제를 지연한다. 팀 main 계약은 즉시 영구 삭제다.
- 서버 직접 삭제 후 대화 조회 404는 정상 확인했다. 앱의 지연 삭제와 서버 삭제를 구분한다.
- 앱 기본 수면은 21~07시, 팀 서버는 한국 시간 22~06시다. 서버 응답에 개별 일정이 없어
  내려받은 친구에는 앱의 별도 기본값 22~06시가 들어간다. 생성 전후·로컬 친구의 판정이 달라질 수 있다.
- 권장 수정 후보: 삭제 복구 화면·저장소의 지연 처리·수면 모델·서버 상태 조회 연결.

### D-05 — Windows 파일 경로를 앱 에셋으로 오인한다

- 재현: `artOriginOf()`에 실제 Windows 파일 경로를 전달하면 `ArtOrigin.asset`이 된다.
  현재 함수는 `/` 또는 `file://`로 시작하는 문자열만 파일로 분류한다.
- 증거: `window_views_test.dart`에서 `FileImage`를 기대했지만 Windows 경로의 `AssetImage`를 받았다.
  `api_test.dart`도 파일은 저장됐지만 아트 crop이 null이라 실패한다.
- 영향: 생성 아트 표시·경계 측정·얼굴 효과가 Windows 테스트에서 실패할 수 있다.
- 전체 실패 파일: api 1, art_source 3, card_figure 10, generated_friend_motion 13,
  house_clip 2, window_views 1. 파일 경로 외 개별 UI·모션 실패도 있으므로 30개 모두를
  동일 원인이나 iOS 결함으로 단정하지 않는다.
- 권장 수정 후보: 플랫폼 독립 경로/URI 판정. 이번 선택 범위는 포팅이 아니므로 원본을 유지했다.

### D-06 — 삭제와 자동 정리가 DB에서 교착된다

- 재현: 실제 친구 삭제 코드가 친구 행을 잠근 시점에 실제 작업 정리 코드를 실행한다.
  PostgreSQL에서 정리가 Lock을 기다리는 것을 확인한 뒤 삭제를 계속한다.
- 실제: PostgreSQL `DeadlockDetected`, 한 경로는 서버의 DB 오류 변환으로 503이 된다.
- 원인: 친구 삭제는 **친구→생성 작업**, 작업 정리는 외래 키 처리로 **생성 작업→친구** 순서다.
- 권장 수정 후보: 두 저장소 함수의 잠금 순서·트랜잭션 경계 통일. 운영 코드는 수정하지 않았다.

### D-07 — 만료된 처리 중 작업이 남아 정리되지 않는다

- 재현: 실제 워커가 claim한 작업을 생성 후 25시간이 지난 상태로 만들고 상태 감시를 실행한다.
  지연 구간만 테스트에서 대체한다.
- 실제: 워커는 조회 404로 실행을 취소하지만 DB에는 `processing`이 남는다.
  정리를 실행해도 작업과 25시간 지난 원본이 보호된다. 서버를 계속 켜두면 잔류할 수 있다.
- 원인: API 만료 조건이 내부 작업 감시에도 적용되고, 취소 시 상태 변경 없이
  `cleanup_jobs()`가 processing을 제외한다.
- 권장 수정 후보: 내부 작업 조회와 외부 조회 만료 분리, 취소·만료의 명시적 최종 상태 처리.

## 4. 정상 확인과 실제 외부 서비스 결과

로컬 HTTP 검증에서 PNG/JPEG 업로드, 생성·폴링·아트/썸네일/face 저장, 서버 규격의
친구 저장·멱등 재전송, 친구 목록의 로컬 복원, 대화·기록·동일 clientMessageId 재전송,
수면 시간 거부, 타인 리소스 404, 앱 생성 취소, 정책 거부·잘못된 PNG·시간 초과의 구분,
서버 삭제 후 대화 404를 확인했다. 저장 응답을 한 번 유실시켜도 같은 키로 복구되고
같은 친구 ID가 반환됐다. 외부 Auth·Storage·AI는 이 단계에서 진단용 구현이다.

개발 Supabase 실서비스에서는 임시 계정 2개만 만들었다. 실제 로그인, 서버 JWT 검증,
원격 DB, PNG/JPEG 업로드와 실제 서명 URL 다운로드, 타인 친구 접근 차단, 테스트 친구
삭제·대화 조회 차단을 확인했다. 기존 원격 스키마·사용자 데이터·다른 작업 큐는 변경하지 않았다.

실제 이미지 호출은 PNG 1회·JPEG 1회 모두 `generation_unavailable`, `retryable:false`로 실패했다.
이 조합은 `data_policy`뿐 아니라 일부 인증·경로 등 비재시도 외부 오류에서도 반환될 수 있다.
외부 응답 본문과 세부 HTTP 상태는 보존하지 않았으므로, 이번 증거만으로 제공자 측 원인을
확정하지 않는다. 승인 한도를 모두 사용했으므로 원인 세분화를 위한 생성 요청은 추가하지 않았다.
이미지 품질을 확인했다고 주장하지 않는다.
성공한 생성이 없어서 실제 얼굴 분석은 0회다.

생성이 실패해도 독립적인 권한·삭제 검증을 위해 **합성 결과의 테스트 친구**를 별도로 만들었다.
이것을 실제 AI 생성 성공으로 보고하지 않는다. 실제 대화는 한국 시간 22~06시 수면 구간이어서
0회로 생략했다. 시간을 바꾸거나 서버의 수면 거부를 우회하지 않았다.

임시 계정과 파일은 정리했고, 별도 원격 조회로 해당 진단 계정이 0개임을 확인했다.
전역 워커 복구·자동 정리는 시작하지 않고 이번 실행이 만든 작업만 직접 처리했다.

## 5. 재실행 방법과 남은 검증

아래 명령은 저장소 루트에서 시작하는 PowerShell 예시다. Python 가상환경은 기존
`server/.venv`, Flutter는 설치된 실행 파일을 사용한다. `flutter`가 PATH에 없으면 설치된
`flutter.bat` 경로로 바꾼다. Docker 이름이 이미 존재하면 재사용하거나 삭제하지 말고 소유부터 확인한다.

```powershell
docker desktop start
docker run --detach --name bogle-integration-20261031 --label bogle.diagnostic=20261031 --env POSTGRES_PASSWORD=bogle-local-diagnostic --publish 127.0.0.1:55439:5432 postgres:16
cd server
. ./.venv/Scripts/Activate.ps1
python -m scripts.diagnostic_server
```

다른 터미널에서:

```powershell
cd frontend
flutter pub get
$env:BOGLE_DIAGNOSTIC_URL = 'http://127.0.0.1:8765'
$env:BOGLE_DIAGNOSTIC_REPORT = (Join-Path (Resolve-Path ../output/diagnosis) 'dart-http.json')
flutter test --no-pub test/e2e/team_backend_diagnosis_test.dart --reporter expanded
```

진단은 새 서버·새 DB로 한 번씩 실행한다. 동일 서버에서 반복하면 사용자별 횟수 제한이
누적돼 다른 결과가 날 수 있다. 종료는 아래처럼 하면 서버가 임시 DB까지 정리한다.

```powershell
Invoke-RestMethod -Method Post http://127.0.0.1:8765/diagnostic/stop
# 이 이름과 라벨이 이번에 만든 컨테이너임을 먼저 확인한 뒤 제거
docker inspect bogle-integration-20261031
docker rm --force bogle-integration-20261031
```

백엔드 테스트는 로컬 테스트 DB 연결로만 실행한다. 테스트 자체가 임시 DB를 만들고 삭제한다.
실행 프로세스가 개발 `.env`의 외부 설정을 사용하지 않게 아래처럼 별도 설정한다.

```powershell
cd server
$env:TEST_DATABASE_URL = 'postgresql://postgres:bogle-local-diagnostic@127.0.0.1:55439/postgres'
python -B -c 'from pathlib import Path; from app.config import Settings; Settings.model_config["env_file"]=Path("C:/bogle-diagnostic-do-not-load-env"); import pytest; raise SystemExit(pytest.main(["-q","-rs","-p","no:cacheprovider"]))'
python -m ruff check .
python -m ruff format --check .
python -m scripts.compare_api_contract
```

Playwright는 CLI wrapper의 지정 세션으로 `/docs`를 열고 snapshot→health 펼치기→Try it out→
새 snapshot→Execute→HTTP 200 확인 순서로 수행했다. 인증 토큰은 브라우저에 넣지 않았다.
화면·네트워크 관찰은 API 문서 검증이며 실제 앱 화면 E2E가 아니다.

실서비스 진단 도구는 `python -m scripts.diagnose_live_services --confirm-paid-budget`다.
기존 서버 설정은 프로그램이 내부적으로 사용한다. 이번 실행의 `live-budget.json`이 있으면
재과금을 막기 위해 실행을 거부한다. **새 승인 없이 이 기록을 지우고 재실행하지 않는다.**

남은 검증: 수정 후 iPad 실제 화면 흐름, iOS 서명·권한·Pencil·카메라·마이크,
실제 생성 성공 후 그림 품질·얼굴 좌표, 깨어 있는 시간의 실제 AI 대화,
실제 60분 경과 후 서명 URL 만료, 프론트 실패 30개의 iOS 동일 재현 여부다.
이 단계의 결과만으로 전체 연동 완료나 발표 준비 완료라고 판단하면 안 된다.

정리 완료: 전용 Supabase 계정·파일, 로컬 임시 DB, 진단 서버·브라우저 세션,
이번에 만든 Docker 컨테이너·PostgreSQL 이미지와 통합본의 빌드 캐시를 제거했다.
기존 사용자 파일·원본 저장소·최종 증거는 보존했다. 원본 프론트 라이선스 파일 2개에
이미 있던 줄 끝 공백은 원문 보존을 위해 유지했고, 그 두 파일을 제외한 staged 공백 검사를 통과했다.
