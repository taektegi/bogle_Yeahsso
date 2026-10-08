# junsang 브랜치: 친구 만들기·대화·모션 백엔드

| 항목 | 내용 |
|---|---|
| 작성일 | 2026-10-08 |
| 기준 | `main` @ `76c8a0d` + 이 브랜치의 변경 |
| 앱 | `quasiaward/Bogle_doll_making_app`의 `release` 브랜치 |
| 원칙 | 앱에 이미 있는 기능을 우선한다. 계약(v1)에 없던 값은 **더하기만** 하고 기존 응답은 바꾸지 않는다 |

## 1. 새로 생긴 API

| 메서드 | 경로 | 용도 |
|---|---|---|
| POST | `/v1/assets` | 그림(PNG)·사진(JPEG) 올리기. 형식은 파일 내용으로 검사, 10 MiB, 각 변 64–4096px |
| GET | `/v1/assets/{assetId}` | 만료된 서명 URL 새로 받기 |
| POST | `/v1/generations` | 캐릭터 생성 시작 (`Idempotency-Key` 필수) |
| GET | `/v1/generations/{jobId}` | 생성 상태 (2초마다 조회) |
| POST | `/v1/generations/{jobId}/cancel` | 생성 취소 (최종 상태를 돌려줌) |
| GET | `/v1/personality-types` | 성격 유형 목록 |
| POST | `/v1/characters` | 성공한 작업으로 친구 만들기 (`Idempotency-Key` 필수) |
| PATCH | `/v1/characters/{id}` | 친구 고치기: 이름·성격·소개·말투·수면 시간 (앱의 수정 화면) |
| POST | `/v1/characters/{id}/messages` | 친구에게 말 걸기 (AI 답, 실패하면 스크립트 대사) |
| GET | `/v1/characters/{id}/messages` | 이전 대화 (최신순, 커서) |
| GET | `/v1/characters/{id}/motion` | 모션 클립 (jump·wave·dance GIF) |

모양은 `docs/frontend-api-reply.md`(계약 v1)와 같다. 아래는 계약에 **더한 것**이다.

### 친구 응답에 더한 값
```json
{
  "personality": "엉뚱한 상상을 좋아해요",
  "face": {"version": 1, "size": [812, 1024], "facing": "front",
           "head": [180, 90, 460, 400], "eyes": [[330, 260, 22], [480, 262, 22]],
           "mouth": [405, 360, 70, 22], "cheeks": [[290, 330, 26], [520, 330, 26]],
           "source": "model"},
  "bedtime": 1320,
  "wakeTime": 360
}
```
- `personality`: 아이가 직접 적거나 말한 성격. 목록에서 골랐으면 그 문구. `personalityLabel`도 같은 값이다.
- `face`: **얼굴 지도** (앱 `docs/CHARACTER_RIG.md`의 `face.json`과 같은 형식, 그림 픽셀 좌표).
  앱은 이것으로 눈 깜빡임·찡긋, 입 벌리기·오물오물, 볼 빵빵을 그리고 **간식을 입에 댄다**.
- `bedtime`, `wakeTime`: 자는·깨는 시각 (자정부터 분, 한국 시간). 기본 22:00–06:00.
  `GET /characters/{id}/status`와 대화의 "자는 중" 판정이 이 값을 쓴다.

### 친구 만들기 요청에 더한 값
- `personality`(자유 입력, 30자) 또는 `personalityType`(목록 코드) 중 하나. 자유 입력이면 유형은 `custom`.
- `bedtime`, `wakeTime` (선택).

### 생성 작업 성공 응답에 더한 값
- `face`: 위와 같은 얼굴 지도.

## 2. 캐릭터 생성 (`app/generation.py`, `app/workers.py`)

서버 안의 처리기가 작업을 하나씩 가져가 처리한다 (`for update skip locked`).

1. **입력 검사**: 빈 그림·단색 → `invalid_source_image` (모델을 부르지 않는다).
2. **입력 검열** (OpenAI moderation). 걸리면 `generation_rejected`.
3. **그림 모델** (`gpt-image-1`, 투명 배경 요청). 그림판 그림은 흰 종이 위에 얹어서 보낸다.
4. **후처리** (`app/imaging.py`)
   - 모델이 배경을 남겨도 테두리와 이어진 배경만 걷어 낸다 (캐릭터 안의 흰 눈·배는 남는다).
   - 떨어진 작은 얼룩을 지운다.
   - 캐릭터만 남게 자르고 둘레 여백을 **일정하게**(긴 변의 4%) 맞춘다. 앱은 그림 아래를 바닥에
     세우므로, 여백이 들쭉날쭉하면 캐릭터가 떠 보이거나 그림자가 어긋난다.
   - 캐릭터가 거의 없으면 `generation_rejected`.
5. **얼굴 지도** (`app/face_map.py`): 아래 3절.
6. 썸네일(256×256)과 대표색(파스텔). 결과를 Storage에 올리고 작업을 끝낸다.

### 실패 코드 (작업 응답의 `error`)
| code | 언제 | retryable |
|---|---|---|
| `generation_rejected` | 안전 정책 거절, 입력 검열, 모델이 캐릭터를 그리지 못함 | false |
| `invalid_source_image` | 빈 그림, 깨진 파일, 모델이 이미지를 읽지 못함 | false |
| `generation_timeout` | 4분 초과, 처리기가 멈춘 작업 | true |
| `generation_unavailable` | 요청 과다·OpenAI 장애·연결 실패·키 없음·저장소 오류 | true |

- 일시 오류(`unavailable`·`timeout`)는 작업 시간 안에서 2번 더 시도한다 (2초, 5초 뒤).
- **취소**: 처리 중에 취소되면 결과를 저장하지 않고 올린 파일도 지운다. 늦은 결과로 넘어가지 않는다.
- **복구**: 서버가 재시작되면 처리 중이던 작업을 다시 처리한다 (3번 시도한 작업은 실패로 끝냄).
- `retryable: true`면 앱은 같은 `sourceAssetId`로 **새 키**를 붙여 다시 시작한다.

## 3. 얼굴 지도: 간식 위치와 얼굴 모션

앱의 집에서 간식은 `face.mouth` 위치에 놓인다. 좌표가 조금만 어긋나도 간식이 허공이나 눈앞에 뜬다.
그래서 모델의 답을 **그대로 쓰지 않고 그림과 대조해 고친다**.

1. 비전 모델(`gpt-4.1-mini`, 구조화 출력)에게 눈·입·볼·머리·방향을 묻는다.
2. 그림에서 직접 **눈동자**(그려진 곳 안의 어둡고 동그란 점)를 찾는다.
3. 고치기
   - 모델의 눈을 가까운 눈동자에 붙인다. 그림 밖(투명한 곳)의 눈은 버리고, 빠졌으면 찾은 눈으로 채운다.
   - 입이 투명한 곳·눈보다 위에 있으면 그려진 곳으로 옮기거나 다시 정한다.
     - 정면: 두 눈 사이 아래.
     - 옆모습: **주둥이 끝 쪽, 주둥이 아래 1/3**.
   - 머리 상자는 그림 안으로 줄이고 눈과 입을 감싸게 넓힌다.
   - 모델이 다른 크기로 답했으면 그림 크기로 비례 변환한다.
4. 모델을 못 쓰거나(키 없음·장애) 답이 쓸모없으면 그림만 보고 추정한다 (`"source": "estimate"`).
   앱의 뚜치·네모린(사람이 직접 잰 얼굴 지도)과 비교해 눈은 4px, 입은 그림 크기의 3% 안쪽으로 맞았다.

## 4. 대화 (`app/chat.py`)

- 입력 검열 → AI 답(친구 설정 + 최근 20개 대화, 15초) → 답 검열.
- 걸리거나 실패하면 **오류가 아니라** 스크립트 대사(친구의 말투)로 답한다 (`source: "script"`).
- 같은 `clientMessageId` 재전송은 같은 답을 돌려주고, 내용이 다르면 409. 자는 시간에는 409 `character_asleep`.

## 5. 모션 클립 (`app/motion.py`)

- 친구를 만들면 모션 작업이 생긴다. `MOTION_SERVICE_URL`(앱 저장소의 `motion_server`)이 있으면
  처리기가 친구 그림을 흰 종이에 얹어 보내고, 만들어진 GIF를 우리 Storage로 옮겨 서명 URL로 준다.
- 모션 서버가 사람 모양을 찾지 못하면 `unsupported`(이유: `not_humanoid`, `background`, `no_figure`).
  서버가 없으면 `unsupported`(`disabled`). 이때 앱은 자기 모션 + 얼굴 지도로 움직인다.
- 일시 오류는 2번까지 다시 시도하고, 5분이 넘으면 `failed`.
- 친구를 지우면 GIF도 함께 지운다.

## 6. DB (`supabase/migrations/20261008000100_generation_chat_motion.sql`)

- `generation_jobs`, `chat_messages`, `motion_jobs` (RLS: 내 것만 읽기, 쓰기는 서버만)
- `friends`: `personality`, `bedtime_minute`, `wake_minute`, `face` 추가. `generation_job_id` 외래 키.
- 정리 작업: 처리 중인 작업의 원본·모션 GIF는 지우지 않고, 24시간 지난 작업 기록은 지운다.

## 7. 설정 (`server/.env.example`)

| 변수 | 기본값 | 뜻 |
|---|---|---|
| `OPENAI_API_KEY` | — | 없으면 생성은 `generation_unavailable`, 대화는 스크립트, 얼굴은 추정 |
| `GENERATION_PROVIDER` | `openai` | `passthrough`: OpenAI 없이 아이 그림을 다듬어 그대로 쓴다 (개발·시연) |
| `OPENAI_IMAGE_MODEL` / `OPENAI_VISION_MODEL` / `OPENAI_CHAT_MODEL` | `gpt-image-1` / `gpt-4.1-mini` / `gpt-4.1-mini` | |
| `GENERATION_TIMEOUT_SECONDS` | 240 | 생성 작업 최대 시간 |
| `GENERATION_WORKERS` | 2 | 동시에 처리할 생성 작업 수 |
| `WORKER_POLL_SECONDS` | 1 | 0이면 처리기를 끈다 |
| `MOTION_SERVICE_URL` | — | 그림 모션 서버 주소 |

## 8. 검증

- `ruff check`, `ruff format --check` 통과.
- `pytest`: 315개 통과 (기존 234 + 새 81). 새 테스트는 아래 5개 파일이다.

| 파일 | 확인하는 것 |
|---|---|
| `test_face_map.py` | 얼굴 지도: 정면·옆모습 추정, 허공·이마의 입 고치기, 눈 붙이기·버리기, 크기 변환 |
| `test_generation.py` | 후처리, 실패 코드, 재시도, 시간 초과, 빈 그림, 검열, OpenAI 오류 분류 |
| `test_generations_db.py` | 업로드 검사, 생성 시작·재전송·충돌, 처리, 거절, 취소, 재시도, 멈춘 작업·복구 |
| `test_friends_db.py` | 만들기·재전송·중복·미완성·남의 작업, 입력 검증, 소개, 고치기, 친구별 수면 |
| `test_friends_db.py` (이어서) | 대화·재전송·검열·AI 실패·자는 중·페이지, 모션 ready·unsupported·삭제 |
