# AI 이미지 생성 오류 해결 검증 — 2026-10-31

## 판정

**1번 ‘실제 AI 이미지 생성 실패’는 해결·종결로 판단한다.**
사용자가 OpenRouter 정책 설정을 수정한 뒤, 기존 운영 이미지 제공자와 생성 워커를 그대로
사용한 실호출에서 `succeeded`와 실제 이미지 다운로드·친구 저장을 확인했다.
모의 이미지나 강제로 성공 처리한 작업으로 대체하지 않았다.

## 원인과 변경

이전 요청은 키 인증과 모델 조회는 성공했지만 실제 이미지 요청이 HTTP 404와 `data_policy`
분류로 거절됐다. 정책 수정 후 같은 모델·제공자·요청 형식으로 실제 생성이 성공했다.
따라서 이번 장애는 OpenRouter의 계정 정책과 제공자 사용 조건의 충돌이 해소된 것으로 본다.
사용자가 바꾼 세부 토글은 직접 열람하지 않았으므로 특정 설정 이름까지 확정하지 않는다.

- 모델: `openai/gpt-image-2.5-flare`, OpenAI 제공자 고정.
- 운영 `app/image_provider.py`, `app/generation_worker.py`, 공개 API, DB 스키마는 변경하지 않았다.
- 진단 도구에 출력 폴더·입력 종류 선택·대화 생략·실제 생성 성공 필수 옵션을 추가했다.
- 기존 실패 증거와 호출 한도 기록을 덮어쓰지 않고, 새 실행 기록을 별도 폴더에 보관했다.

## 이번에 실제 실행한 흐름

실제 Supabase 임시 계정 로그인 → FastAPI의 JWT 검증 → 테스트용 JPEG 업로드 →
생성 요청 → 해당 계정의 해당 작업만 실행 → 실제 OpenRouter 이미지 생성 → 실제 얼굴 분석 →
PNG·썸네일·대표색 생성 → 실제 Supabase Storage 업로드·재다운로드 → DB 성공 상태 조회 →
서명 URL 다운로드 → 친구 저장·동일 멱등 키 재전송 → 타인 접근 차단 → 전용 데이터 삭제.

| 항목 | 결과 |
|---|---|
| 생성 작업 | `succeeded` |
| 이미지 | 1024×1024 투명 PNG, 서버의 실제 투명도 검사 통과 |
| 대표색 | 재계산 결과가 생성 응답과 일치 |
| 썸네일 | 실제 PNG 다운로드 성공 |
| 얼굴 분석 | 유효한 face가 생성 응답에 포함됨 |
| 친구 저장·재전송 | 성공, 같은 친구 ID 반환 |
| 타인 접근 | 404 차단 |
| 합성 성공 작업 대체 | 사용하지 않음 (`syntheticChatFixture: false`) |
| 이번 추가 유료 호출 | 이미지 1회 / 얼굴 분석 1회 / 대화 0회, 자동 재시도 없음 |
| 정리 | 전용 계정·파일 삭제 성공, 별도 원격 조회에서 진단 계정 0개 |
| 관련 자동 검사 | 44개 통과, 생략 없음 |
| Ruff | 검사·포맷 75개 파일 통과 |

FastAPI 요청은 Windows의 TestClient로 실행했다. 인증·DB·Storage·이미지 제공자·얼굴 분석은
실서비스 구현이다. 전역 큐 claim·워커 복구·자동 정리는 실행하지 않고 이 실행의 작업만
소유자 조건으로 처리했다. 운영 워커와 같은 `process`·`pipeline`을 사용했다.

## 증거와 재실행

- `output/diagnosis/ai-resolution/live-services.json`: 이번 실제 서버 경로의 최종 결과.
- `output/diagnosis/ai-resolution/live-budget.json`: 이번 실행의 유료 호출 횟수.
- `output/diagnosis/ai-resolution/photo-art.png`: 실제 생성·Storage 다운로드한 캐릭터.
- `output/diagnosis/ai-resolution/photo-thumbnail.png`: 실제 썸네일.
- `output/diagnosis/ai-resolution-unit-tests.txt`: 이미지 제공자·설정·얼굴 분석 44개 검사 결과.
- `output/diagnosis/image-investigation-02.json`, `.png`: 작업 시작 시 이미 존재한 정책 수정 후
  PNG 직접 호출 성공 기록과 이미지. 이번 새 서버 경로 검증과 구분해 보존했다.

승인된 실제 검증 명령은 `server/`에서 다음과 같다.

```powershell
python -B -m scripts.diagnose_live_services --confirm-paid-budget --sources photo --skip-chat --require-generation --output-dir ../output/diagnosis/ai-resolution
```

기존 출력 폴더에 `live-budget.json`이 있으면 재실행을 거절한다. 기록을 삭제해 다시 호출하지
않는다. 추가 실호출이 필요하면 목적과 횟수를 정하고 새 출력 폴더를 사용한다.
비밀값은 프로그램이 내부에서만 사용했으며 토큰·비밀번호·서명 URL·외부 오류 원문은
로그와 증거에 남기지 않았다. 이번 실행은 별도 임시 스크립트·상주 서버·Docker를 만들지 않았다.

## 이번 판정의 범위

종결 대상은 **정책 오류로 실제 이미지 생성이 실패하던 문제**다. 테스트 원본은 사람이
직접 촬영한 사진이 아닌 코드로 만든 JPEG다. 생성물의 미술 품질·다양한 실제 사진과 그림의
품질, iPhone/iPad 실기기 화면·사진 권한·네이티브 입력은 이번에 검증하지 않았다.
실제 AI 대화도 이번 범위에서 제외했다. 이것을 앱 전체 실기기 검증 완료로 해석하지 않는다.
