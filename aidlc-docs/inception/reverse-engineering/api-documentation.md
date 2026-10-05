# API Documentation

> 이 문서는 **현재 존재하는** API와 규칙만 기록한다. PRD 7절의 `/v1/...` 엔드포인트는 제안이며 아직 구현되어 있지 않으므로 여기에 포함하지 않는다.

## REST APIs

### 모션 서버 (구현됨, `motion_server/app.py`) — 인증·`/v1` 접두어 없음

#### 모션 작업 생성
- **Method**: POST
- **Path**: `/motions`
- **Purpose**: 그림 한 장으로 모션 작업 접수
- **Request**: `multipart/form-data`, 필드 `image`. 최대 12 MiB(전체를 메모리에 읽은 뒤 검사)
- **Response**: HTTP 200 `{id, status}`. 빈 입력 400, 크기 초과 413. 같은 입력은 기존 작업 반환, `failed`였다면 디렉터리를 지우고 재실행

#### 모션 작업 조회
- **Method**: GET
- **Path**: `/motions/{id}`
- **Purpose**: 상태와 결과 클립 조회
- **Response**: `{id, status, clips: {jump|wave|dance: {url, box}}, reason}`. `status`: `queued → working → ready | unsupported | failed`. `reason`: `not_humanoid`, `background`, `no_figure`. `box`는 `[left, top, right, bottom]` 0–1 비율. 없는 작업 404

#### 클립 파일
- **Method**: GET
- **Path**: `/motions/{id}/{clip}.gif`
- **Purpose**: GIF 제공 (`Cache-Control: max-age=31536000`)
- **Response**: `image/gif`, 없으면 404

#### 헬스 체크
- **Method**: GET
- **Path**: `/health`
- **Purpose**: 로컬 TorchServe 모델 목록 확인
- **Response**: `{ok, models}` — 장애여도 HTTP는 성공하고 `ok=false`

**클라이언트 동작** (`HttpMotionService`): 2초 간격 조회, 약 3분 후 포기, 연결 timeout 4초, HTTP 200만 성공으로 인정, 친구 ID 단위로 앱 실행 동안 캐시(`unsupported`/`failed`/시간 초과의 `null`도 캐시됨). PRD 기준부터 `main-develop`까지 코드 변경 없음.

### Supabase 자동 API (백엔드 워크스페이스, 다른 도메인)
- PostgREST가 `profiles`, `films`, `film_photos`, `film_sessions`, `film_messages`를 RLS 하에 노출한다. 보글 앱은 이 API를 호출하지 않는다.
- 커스텀 RPC 함수, Edge Function, 웹훅 없음.

## Internal APIs (Flutter 앱, `origin/main-develop` 기준)

### CharacterRepository
- **Methods**: `fetchFriends() → Future<List<CharacterFriend>>`, `saveFriend(friend) → Future<CharacterFriend>`, `addMemory(friendId, memory) → Future<void>`, `deleteFriend(friendId) → Future<void>`, `fetchStatus(friendId) → Future<FriendStatus>`, `saveStatus(friendId, status) → Future<void>`
- **Parameters**: 전체 객체를 받는다 (`saveFriend`, `saveStatus`)
- **Return Types**: 목록은 전체, 페이지네이션 없음. `fetchStatus`는 저장값을 지금 시각까지 `aged()` 처리해 반환하고 그 값을 다시 저장

### ProfileRepository
- **Methods**: `fetchProfile()`, `saveProfile(profile)` (찜 포함 전체 덮어쓰기), `fetchOrders()` (최신순), `placeOrder(order)`

### CharacterGenerationJob
- **Methods**: `completed: Future<void>`, `cancel()` (취소 시 `GenerationCancelled` 예외로 완료)
- **주입 지점**: `LoadingScreen.startGeneration` (없으면 `DemoCharacterGenerationJob`, 18초)

### StudioCamera / PhotoPicker (PRD 이후 추가)
- **Methods**: `open()`(실패 시 `CameraFailure(denied|unavailable|failed)`), `preview()`, `setLight`, `setZoom`, `focusAt`, `capture() → Future<Uint8List>` (세워진 JPEG), `close()`. `PhotoPicker = Future<Uint8List?> Function()`
- **현재 한계**: 캡처한 바이트가 생성 흐름으로 전달되지 않음

## Data Models

### Flutter 앱 모델

#### CharacterFriend
- **Fields**: `id`(`friend-<ms>`), `name`, `personality`, `introduction`(**신규**), `favoriteThings: List<String>`, `speechStyle`, `assetPath`(앱 번들 경로), `accentHex: int`(ARGB 정수, 생성 시 고정 `0xFFB8C9FF`), `level`(1), `memories`(0), `createdAt?`, `sleep: SleepSchedule`(**신규**)
- **Relationships**: `FriendStatus` 1:1(저장소 맵), 추억 텍스트 1:N(저장소 맵), 찜은 `UserProfile.likedFriendIds`
- **Validation**:

| 필드 | 생성 화면 | 수정 화면 |
|---|---|---|
| 이름 | 공백 제거 후 필수, 최대 12자 | 필수, 최대 12자 |
| 성격 | 필수, 최대 30자 | 빈 값 허용, 최대 30자 |
| 소개 | **입력 없음** (기본 문구 표시) | 최대 70자 |
| 좋아하는 것 | 1개 이상 (사과, 친구랑 놀기, 산책, 구름, 낮잠, 그림, 노래, 바다) | 수정 불가 |
| 말투 | `~지요!` / `해요체` / `반말` | 기존 자유 서술형 값 유지 가능 |
| 수면 일정 | 기본 21:00–07:00 | 친구의 집 다이얼로그에서 수정 |

- **직렬화**: `toJson()`은 `schemaVersion: 1`, `bedtime`, `wakeTime`을 포함. `fromJson()` 없음. `copyWith`로는 `id`·`assetPath`·`accentHex`·`createdAt`을 바꿀 수 없음

#### SleepSchedule (신규)
- **Fields**: `bedtime`, `wakeTime` — 자정 기준 분. 자정을 넘는 밤 허용. `bedtime == wakeTime`이면 잠들지 않음
- **Methods**: `asleepAt(time)`, `nextChange(time)` — 기기 현지 시각 기준

#### FriendStatus
- **Fields**: `mood`(80), `fullness`(70), `energy`(75), `closeness`(40), `asleep`(false), `updatedAt`
- **Validation**: `copyWith`에서 모두 0–100으로 제한. 자연 감소는 하한 25

#### UserProfile
- **Fields**: `nickname`(기본 `그린고블린`, 최대 12자, 빈 값 불가), `avatar`(에셋 경로), `friendNotifications`, `orderNotifications`(기본 true), `likedFriendIds: Set<String>`

#### ProfileOrder / ShippingInfo
- **Fields**: `id`(기기 시각 기반), `product`, `asset`, `options: List<String>`(표시 문자열), `date`(문자열), `price`, `status`(`preparing`/`making`/`shipping`/`delivered`), `shipping{recipient, address, courier}`
- **누락**: 결제수단, 연락처, 우편번호, 배송 메모, 보호자 동의, 구조화된 옵션 코드·수량

### 프로토타입 게임 규칙 (`friend_screen.dart`, `friend_status.dart` — `main-develop`에서 확인)

**시간 경과 `aged(now)`**: 15분 미만이면 그대로. 그 이상이면 경과 시간(분/60)을 곱해 반올림:
배부름 −4/h, 기분 −2/h(하한 25), 기운은 `asleep`이면 +15/h(상한 100) 아니면 −3/h(하한 25), 친밀도 변화 없음. **판정에 저장된 `asleep` 값 하나만 쓴다.**

| 행동 | 조건 | 변화 | PRD 대비 |
|---|---|---|---|
| 쓰다듬기 | 자는 중이면 대사만 | 기분 +3, 친밀도 +1, wave 클립 | 동일 |
| 간식 (사과·도토리·쿠키·딸기) | 배부름 ≥ 95면 거절 | 배부름 +22, 기분 +5, 친밀도 +2 | 동일 |
| 좋아하는 간식 | `favoriteThings` 중 하나가 간식 이름 포함 | 배부름 +22, 기분 +10, 친밀도 +3, jump 클립 | 동일 |
| **초대** | 깨어 있을 때, 내 다른 친구 1명 | 손님 도착 시 집주인 기분 +6, 친밀도 +1. 손님 상태는 변화 없음. 손님 쓰다듬기는 화면 카운트만 | **신규** |
| ~~비눗방울 놀이~~ | — | — | **삭제됨** (`bubble_play.dart` 제거) |
| **자동 잠들기** | 수면 일정상 취침 시각 | `asleep=true`, 손님 귀가 | 수동 "재우기" **대체** |
| **자동 깨기 (화면에 있는 동안)** | 기상 시각 | `asleep=false`, 기운 `max(현재,90)`, 기분 +5 | 수동 "깨우기" **대체** |
| **자동 깨기 (화면 진입 시 보정)** | 저장값과 일정이 다름 | `asleep` 보정, 깨는 경우 기운 `max(현재,90)` — **기분 +5 없음** | **신규 불일치** |
| 대화 전송 | 깨어 있을 때 | 450ms 뒤 기분 +3, 친밀도 +2. 추억 +1, 추억 수가 5의 배수면 레벨 +1 | 동일 |

### 인형 가격 규칙 (`order_catalog.dart`, PRD 이후 변경 없음)
- 기본가 29,000원. 크기 S +0 / M +9,000 / L +19,000. 소재 극세사 +0 / 퍼 +4,000 / 코튼 +6,000. 부가 선물 포장 +3,000 / 이름 자수 +5,000 / 키링 +2,000(개당)
- 개당 가격 × 수량(1–5) = 상품 합계. 50,000원 이상 무료배송, 미만 3,000원
- 결제수단 enum: `easyPay`, `card`, `transfer`. 도착 예정일 = 주문일 + 12일

### 백엔드 워크스페이스 DB 모델 ("오늘의 필름")

| 테이블 | 주요 필드 | 관계 | 검증 |
|---|---|---|---|
| `profiles` | `id`(= `auth.users.id`), `display_name`, `created_at`, `updated_at` | `auth.users` 1:1, cascade | 정책: 본인 select/update만 |
| `films` | `id`, `user_id`, `recorded_date`, `title`, `one_line`, `memorable_quote`, `status` | `auth.users` 1:N | `status in (draft, completed)` |
| `film_photos` | `id`, `film_id`, `storage_path`, `display_order`, `is_representative` | `films` 1:N | `display_order >= 0`, film당 대표 1장(부분 유니크) |
| `film_sessions` | `id`, `film_id`(unique), `user_id`, `status`, `started_at`, `completed_at` | `films` 1:1 | `status in (active, completed, cancelled)` |
| `film_messages` | `id`, `session_id`, `user_id`, `role`, `content`, `message_order` | `film_sessions` 1:N | `role in (user, assistant)`, `(session_id, message_order)` 유니크 |
