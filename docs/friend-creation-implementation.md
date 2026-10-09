# 친구 만들기 구현과 2026-10-09 결정

김성현 담당 FR-03~05의 백엔드 API만 구현한다. Flutter 연결은 다음 작업이다.
이 문서와 요구사항·API 계약의 해당 항목은 2026-10-09 사용자 인터뷰 결정을 반영한다.

## 확정한 동작

- 기존 비공개 `bogle-media` 버킷을 사용한다. 원본은 `{userId}/source/{assetId}.png|jpg`,
  결과는 `{userId}/art/{assetId}.png`, 썸네일은 `{userId}/thumbnail/{assetId}.png`다.
- 원본은 실제 PNG/JPEG 한 장, 최대 10MiB, 각 축 64~4096px만 허용한다. 파일명과 MIME을 신뢰하지 않는다.
- 원본 바이트는 보관하고, AI 입력만 EXIF 방향 보정과 최대 긴 변 1536px 축소를 적용한다.
  투명 부분을 흰색으로 합성하고 JPEG(품질 92)로 보내 확정된 모델 실험과 같은 입력 형식을 사용한다.
- OpenRouter `/api/v1/images`에 `openai/gpt-image-2.5-flare`, `quality: medium`,
  `aspect_ratio: 1:1`, `background: transparent`, OpenAI 제공자 고정으로 한 번 요청한다.
  전처리 AI와 배경 제거 AI는 호출하지 않는다. 프롬프트는 `AI_model`에서 확정한 내용의 복사본이며
  `bogle-flat-v1-20261009` 버전으로 관리한다.
- 결과 실제 크기를 기록한다. PNG 알파 채널의 투명 영역·불투명 캐릭터 영역·네 모서리를 검사하고,
  대표색 ARGB와 투명 256×256 PNG 썸네일을 만든다. Storage 업로드 후 다시 읽은 바이트를 확인해야 성공한다.
- 이름은 공백 제거 후 보이는 글자 1~12자, 좋아하는 것 8개 중 1개 이상, 말투 3개 중 하나다.
- 성격은 현재 프론트엔드의 4개 선택지다. 과거 6개 코드의 조회 표시명은 유지한다.
- 소개 문구는 프론트엔드의 기존 8개 중 저장 트랜잭션에서 한 번 골라 저장한다.
  같은 저장 요청을 다시 보내도 친구 ID와 소개 문구는 유지된다. 소개 AI는 호출하지 않는다.

## 작업 관리

`generation_jobs`를 PostgreSQL 대기열로 사용하고 FastAPI lifespan에서 내부 워커를 실행한다.
상태는 `queued → processing → succeeded | failed | cancelled`다.
DB 임대 잠금으로 워커 하나만 처리하고, 동시 AI 호출은 최대 2개다. Redis·별도 큐 서비스는 추가하지 않는다.
서버는 `uvicorn --workers 1`로 실행한다. 사용자별 요청 횟수 제한은 한 프로세스 메모리에서 관리한다.

처리 시작 후 4분이 한도다. 대기 시간은 이 한도와 별개이며 앱의 5분 UI 한도도 서버 취소가 아니다.
서버 재시작 시 대기 작업은 이어서 처리하고, 처리 중이던 작업은 `generation_interrupted`로 실패 처리한다.
유료 AI를 자동 재호출하지 않는다. 사용자 재시도는 원본 ID를 유지하고 새 멱등 키를 쓴다.
취소 후 도착한 결과와 삭제한 친구의 원본 작업 결과는 저장 성공으로 게시하지 않는다.
외부 AI 요청 취소가 이미 발생한 요금까지 취소하는 것은 아니다.

작업·미사용 원본·결과는 24시간 보관하고 1시간마다 정리한다. 처리 중인 작업과 저장된 친구 파일은 보호한다.
작업을 정리해도 저장된 친구와 친구 저장 멱등 키는 유지한다.
친구를 삭제하면 같은 원본의 생성 작업과 결과 참조도 제거하고, 파일 삭제 실패는 정리 작업이 재시도한다.

## API

| 요청 | 용도 |
|---|---|
| `POST /v1/assets` | multipart `file` 업로드, `201 ImageRef` |
| `POST /v1/generations` | `sourceAssetId`, `sourceType`, 멱등 키로 생성 시작 |
| `GET /v1/generations/{jobId}` | 2초 간격 상태 조회 |
| `POST /v1/generations/{jobId}/cancel` | 취소 또는 이미 결정된 최종 상태 |
| `GET /v1/personality-types` | 성격 코드·표시명 목록 |
| `POST /v1/characters` | 작업 ID·이름·성격·좋아하는 것·말투와 멱등 키로 저장 |

생성·저장은 `Idempotency-Key`가 필수다. 새 요청은 각각 202·201, 동일 요청 재전송은 200이다.
동일 키로 내용이 달라지면 409다. 재전송은 생성 횟수 제한에 포함하지 않는다.
작업 하나와 원본 하나로 저장할 수 있는 친구는 각각 하나다.
모든 요청은 기존 Supabase 토큰 검증을 사용하며 소유자 ID는 토큰에서만 얻는다.
남의 이미지·작업·친구와 없는 리소스는 모두 404다.

## 설정·실행

`server/.env`는 프로그램만 내부적으로 읽는다. 실행 디렉터리와 무관하게 이 파일을 사용한다.
`OPENROUTER_API_KEY`를 권장하며 기존 `openrouter_key`(`OPENROUTER_KEY`)도 인식한다.
값은 사용자가 직접 입력하고 로그·채팅·커밋에 포함하지 않는다.

```powershell
cd backend/server
uv sync --locked --extra dev
uv run uvicorn app.main:app --workers 1 --no-access-log
```

API 문서는 `http://localhost:8000/docs`다.
`python -m scripts.check_bogle_connection`은 비밀값 없이 연결 결과만 출력한다.
`python -m scripts.check_openrouter_connection`은 생성 비용 없이 AI 인증·모델·계정 잔액 유무를 확인한다.
이 검사만으로 실제 생성 가능 여부를 보장하지 않는다. 계정의 개인정보 정책이 공급자를 차단할 수도 있다.
`python -m scripts.verify_character_creation`은 임시 시연 계정을 만들고 실제 유료 이미지 생성을
PNG·JPEG 입력에 각각 한 번 요청한다. 재시도 없이 결과를 검사하고 테스트 계정·파일을 정리한다.
테스트는 외부 AI·Storage를 가짜로 대체하되 PostgreSQL은 실제 임시 DB를 사용한다.

## 검증 결과 (2026-10-10)

- 실제 임시 PostgreSQL을 사용한 전체 자동 테스트 266개 통과. DB 테스트를 건너뛰지 않았다.
  소유권 차단, 업로드→생성→저장, 중복 요청, 취소·시간 초과·재시작, 이미지 검증,
  Storage 읽기 실패, 원본별 결과 연결, 친구 삭제와 미사용 파일 정리를 검사했다.
- Ruff 검사·포맷 검사와 `git diff --check` 통과. `server/.env`가 Git 제외 대상임을 확인했다.
- 연결된 bogle 프로젝트의 기존 비공개 버킷을 재사용하고
  `20261009150949_friend_generation_jobs.sql`을 원격에 적용했다. 새 테이블의 RLS 활성화도 확인했다.
- 실제 Supabase 인증과 원본 업로드는 확인했다. 검증용 계정·파일은 정리했다.
- OpenRouter 키 인증·모델 조회는 성공했지만 실제 생성 요청은 HTTP 404, 내부 분류
  `data_policy`로 실패했다. 계정 개인정보 정책이 공급자를 차단하는 경우다.
  외부 오류 본문과 비밀값은 기록하지 않는다. 오류는 재시도 불가능한 `generation_unavailable`로 반환한다.
- **사용자 결정: 실제 AI 생성 검증은 나중에 진행한다.** 실제 결과 PNG·썸네일·친구 저장의
  전체 외부 서비스 연결 검증은 미완료다. 현재 자동 테스트의 AI 성공 응답은 대체 응답이다.

다음 검증에서는 사용자가 OpenRouter 개인정보 설정·가드레일을 확인한 뒤
`python -m scripts.verify_character_creation`을 실행한다. 이 명령은 실제 유료 요청을 하며,
PNG와 JPEG 입력 각각의 생성→Storage 읽기→친구 저장→중복 저장→삭제를 검사한다.
설정 원인은 [OpenRouter 공식 오류 안내](https://openrouter.ai/blog/tutorials/image-generation-models/)를 참고한다.

## 현재 작업에서 제외

Flutter API 연결·로그인 화면·iPad 빌드·서버 공개 배포·대화·모션은 구현 범위에 포함하지 않는다.
이 API만으로 실제 앱 화면 연동이 완료되었다고 판단하지 않는다.
