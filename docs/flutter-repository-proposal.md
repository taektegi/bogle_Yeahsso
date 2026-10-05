# Flutter 데이터 계층 변경안 (초안)

| 항목 | 내용 |
|---|---|
| 작성일 | 2026-10-05 |
| 상태 | **초안 — 프론트엔드 검토 전** |
| 근거 | API 계약 v1 (`frontend-api-reply.md`), 앱 분석 문서(`aidlc-docs/inception/reverse-engineering/api-documentation.md`, `origin/main-develop` @ `daabf83` 기준) |
| 목적 | 앱의 Repository 경계를 서버 계약에 맞게 바꾸는 방법을 제안하고, 프론트엔드와 백엔드가 작업을 나눌 수 있게 한다 |

> **주의**: 앱 저장소의 실제 코드는 보지 못하고 분석 문서의 요약만 보고 썼습니다. 클래스·메서드 이름과 시그니처는 실제 코드와 다를 수 있으니 프론트엔드가 확인해 주세요. 아래 Dart 코드는 **형태를 보여 주는 스케치**입니다.

## 1. 왜 바꾸는가

현재 `CharacterRepository.saveFriend`와 `ProfileRepository.saveProfile`은 **객체 전체를 덮어쓰는** 구조입니다. 이것을 API로 그대로 옮기면 서버가 모르는 값(레벨·추억·수면 일정·찜)을 클라이언트가 보내게 되고, 서버가 정해야 하는 값(이미지·대표색·생성 시각)을 클라이언트가 만들게 됩니다. API 계약 v1은 이런 값을 모두 서버가 정하므로, **"무엇을 하려는지"가 드러나는 목적별 호출**로 나눕니다.

Repository 인터페이스(`abstract interface class` + 메모리 구현)라는 앱의 기존 경계는 **그대로 둡니다.** 메모리 구현은 테스트와 오프라인 데모용으로 남기고, 서버 구현을 새로 추가해서 `app.dart`에서 주입합니다.

## 2. 한눈에 보는 변경

| 현재 | 변경 | 서버 API |
|---|---|---|
| `CharacterRepository.fetchFriends()` | `listCharacters()` | `GET /v1/characters` |
| `CharacterRepository.saveFriend(friend)` (생성) | `createCharacter(CreateCharacterRequest)` | `POST /v1/characters` |
| `CharacterRepository.deleteFriend(id)` | `deleteCharacter(id)` | `DELETE /v1/characters/{id}` |
| `CharacterRepository.fetchStatus(id)` + `saveStatus` | `fetchSleepStatus(id)` (저장 없음) | `GET /v1/characters/{id}/status` |
| `CharacterRepository.addMemory` | **삭제** (추억 없음) | — |
| `ProfileRepository.fetchProfile()` | 그대로 | `GET /v1/me` |
| `ProfileRepository.saveProfile(profile)` | `updateProfile(ProfilePatch)` | `PATCH /v1/me` |
| `ProfileRepository.fetchOrders()`/`placeOrder()` | **`OrderRepository`로 분리**, 메모리 구현 유지 | — (범위 밖, mock) |
| `CharacterGenerationJob` | 결과 타입·`jobId`·복구 추가 (4절) | `/v1/assets`, `/v1/generations` |
| (없음) | `ChatRepository` 신설 | `/v1/characters/{id}/messages` |
| `MotionService` | 새 경로로 교체 | `GET /v1/characters/{id}/motion` |

## 3. 모델

### 이미지 참조
서버의 모든 이미지는 `assetId` + 만료되는 URL입니다 (계약 3.1절).

```dart
class ImageRef {
  const ImageRef({
    required this.assetId,
    required this.url,
    required this.expiresAt,
    required this.contentType,
    required this.width,
    required this.height,
  });

  final String assetId;
  final String url;
  final DateTime expiresAt; // UTC
  final String contentType;
  final int width;
  final int height;

  /// 만료 1분 전부터는 새 URL을 받아야 한다고 본다.
  bool isExpiredAt(DateTime now) =>
      now.toUtc().isAfter(expiresAt.subtract(const Duration(minutes: 1)));

  factory ImageRef.fromJson(Map<String, dynamic> json) => ImageRef(
        assetId: json['assetId'] as String,
        url: json['url'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        contentType: json['contentType'] as String,
        width: json['width'] as int,
        height: json['height'] as int,
      );
}
```

### 친구 (`CharacterFriend`)
| 필드 | 변경 |
|---|---|
| `id` | 서버가 정한 UUID 문자열 (`friend-<ms>` 폐지) |
| `personality` | `personalityType`(코드) + `personalityLabel`(표시 문구)로 교체 |
| `assetPath`, `accentHex` | `art: ImageRef`, `thumbnail: ImageRef`, `source: ImageRef?`, `accentArgb` |
| `level`, `memories`, `sleep` | **삭제** |
| `introduction`, `favoriteThings`, `speechStyle`, `createdAt` | 그대로 (`createdAt`은 UTC) |

- `fromJson`이 새로 필요합니다 (현재는 `toJson`만 있음). `copyWith`로 이미지·ID·색을 바꿀 수 없다는 현재 규칙은 유지합니다.
- `isPhotographedArt()`의 `/archive_` 경로 판정은 없앱니다 (서버 결과는 모두 투명 캐릭터).
- `accentArgb`는 부호 없는 32비트 값(0–4294967295)입니다. Dart `int`(64비트)로 받으면 되고, Flutter `Color(accentArgb)`에 그대로 넣을 수 있습니다.

### 프로필 (`UserProfile`)
`likedFriendIds` 삭제, `avatar`(에셋 경로)를 `avatarCharacterId: String?`로 교체, `characterCount: int` 추가. 알림 플래그 2개와 `nickname`은 그대로.

### 새 모델
```dart
class SleepStatus {
  const SleepStatus({required this.asleep, required this.nextChangeAt, required this.serverTime});
  final bool asleep;
  final DateTime nextChangeAt; // UTC
  final DateTime serverTime;   // 기기 시계 오차 보정용
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role, // 'user' | 'assistant'
    required this.text,
    required this.createdAt,
    this.source, // assistant만: 'ai' | 'script'
  });
  final String id;
  final String role;
  final String text;
  final DateTime createdAt;
  final String? source;
}
```

## 4. Repository 인터페이스 스케치

```dart
abstract interface class CharacterRepository {
  Future<List<CharacterFriend>> listCharacters();

  /// 친구 생성. [idempotencyKey]는 요청 하나당 새로 만들고, 재전송할 때 같은 값을 쓴다.
  Future<CharacterFriend> createCharacter(CreateCharacterRequest request, {required String idempotencyKey});

  Future<void> deleteCharacter(String id);

  Future<SleepStatus> fetchSleepStatus(String id);

  /// 만료됐거나 곧 만료되는 이미지의 새 URL을 받는다 (GET /v1/assets/{assetId}).
  Future<ImageRef> refreshImage(String assetId);
}

class CreateCharacterRequest {
  const CreateCharacterRequest({
    required this.generationJobId,
    required this.name,
    required this.personalityType,
    required this.favoriteThings,
    required this.speechStyle,
  });
  final String generationJobId;
  final String name;
  final String personalityType;
  final List<String> favoriteThings;
  final String speechStyle;
}

abstract interface class ProfileRepository {
  Future<UserProfile> fetchProfile();

  /// 바꿀 필드만 채운다. 아바타를 기본값으로 되돌리려면 [ProfilePatch.resetAvatar]를 쓴다.
  Future<UserProfile> updateProfile(ProfilePatch patch);
}

abstract interface class ChatRepository {
  /// [clientMessageId]는 메시지마다 새로 만들고 재전송할 때 같은 값을 쓴다 (중복 기록 방지).
  Future<({ChatMessage user, ChatMessage assistant})> sendMessage(
    String characterId,
    String text, {
    required String clientMessageId,
  });

  /// 최신순. 더 불러오려면 직전 응답의 nextCursor를 [before]로 넘긴다.
  Future<({List<ChatMessage> items, String? nextCursor})> fetchMessages(
    String characterId, {
    String? before,
    int limit = 30,
  });
}

/// 주문은 서버와 연결하지 않는다 (범위 밖). 기존 메모리 구현을 그대로 쓴다.
abstract interface class OrderRepository {
  Future<List<ProfileOrder>> fetchOrders();
  Future<void> placeOrder(ProfileOrder order);
}
```

### 생성 작업 (`CharacterGenerationJob`)
현재는 `completed: Future<void>`와 `cancel()`만 있어서 결과를 전달할 수 없습니다.

```dart
abstract interface class CharacterGenerationJob {
  /// 앱을 다시 켰을 때 이어서 조회하려고 저장해 두는 서버 작업 ID. 업로드 중에는 null.
  String? get jobId;

  /// 성공하면 결과, 실패·취소는 예외로 끝난다.
  Future<GenerationResult> get result;

  /// 서버 작업을 취소한다. 이미 끝났다면 서버의 최종 상태가 [result]에 반영된다.
  Future<void> cancel();
}

class GenerationResult {
  const GenerationResult({
    required this.jobId,
    required this.art,
    required this.thumbnail,
    required this.accentArgb,
  });
  final String jobId;
  final ImageRef art;
  final ImageRef thumbnail;
  final int accentArgb;
}

abstract interface class CharacterGenerationService {
  /// 원본을 업로드하고(`POST /v1/assets`) 생성 작업을 시작한다(`POST /v1/generations`).
  CharacterGenerationJob start(Uint8List imageBytes, {required SourceType type});

  /// 저장해 둔 [jobId]로 이어서 조회한다 (앱 종료 후 복구, 24시간 이내).
  CharacterGenerationJob resume(String jobId);
}

enum SourceType { drawing, photo }
```

- `GenerationCancelled` 예외는 유지하고, 서버가 `failed`로 끝나면 계약의 `error.code`와 `retryable`을 담은 `GenerationFailed` 예외를 던집니다.
- **취소한 시도의 늦은 결과로 화면을 넘기지 않아야** 합니다 (계약 3.3절). `cancel()`을 부른 뒤 `result`가 성공으로 끝나도 UI는 이동하지 않습니다.
- 앱의 30초·75초 안내와 5분 UI 한도는 지금처럼 UI에서 처리합니다. 서버 한도(4분)와 별개입니다.

### 모션 (`MotionService`)
`HttpMotionService`의 조회 경로를 `GET /v1/characters/{id}/motion`으로 바꿉니다. 응답의 `status`·`reason`·`clips[clip].url/box` 구조는 기존과 같아서 해석 코드는 크게 바뀌지 않습니다. 모션 서버 주소 설정(`MOTION_SERVER` 빌드 값)은 API 주소 하나로 합칩니다. 클립 URL이 60분 뒤 만료되므로 앱 실행 동안의 캐시는 만료 시각을 확인하고, 만료됐으면 같은 `GET`을 다시 호출합니다.

## 5. 오류와 재시도

서버의 오류 본문(`{"error": {"code", "message", "retryable", "fieldErrors", "requestId"}}`)을 하나의 예외로 받습니다.

```dart
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    required this.retryable,
    this.fieldErrors = const {},
    this.requestId,
    this.retryAfter,
  });
  final int statusCode;
  final String code;
  final String message;        // 사용자에게 보여 줄 수 있는 한국어 문구
  final bool retryable;
  final Map<String, String> fieldErrors;
  final String? requestId;     // 문의·디버깅용
  final Duration? retryAfter;  // 429의 Retry-After
}
```

| 상황 | 앱의 동작 |
|---|---|
| 401 `unauthenticated` | Supabase SDK로 토큰을 갱신하고 **한 번만** 다시 요청. 계속 401이면 로그인 화면 |
| 429 `rate_limited` | `retryAfter`만큼 기다리라는 안내 |
| 503 `service_unavailable` (`retryable: true`) | 짧은 간격으로 최대 2–3회 재시도, 그래도 안 되면 재시도 버튼 |
| 409 `character_asleep` | 대화 입력을 막고 수면 상태로 전환 (서버 판정이 기준) |
| 422 `validation_error` | `fieldErrors`의 필드별로 입력 화면에 표시 |
| 이미지 로딩 실패 / URL 만료 | `refreshImage(assetId)`로 새 URL을 받아 한 번 다시 시도 |

모든 요청에 `Authorization: Bearer <Supabase 액세스 토큰>`을 붙이고, 응답 헤더 `X-Request-Id`는 오류 보고에 남겨 두면 서버 로그와 맞춰 볼 수 있습니다.

## 6. 작업 분담과 순서 (제안)

계약 문서 12절의 분담 제안을 다시 적습니다. **프론트엔드의 답이 필요합니다.**

| 맡는 사람 | 범위 |
|---|---|
| **백엔드** | 위 모델·인터페이스·서버 구현(API 클라이언트), 로그인·세션, 업로드·생성·모션 클라이언트 |
| **프론트엔드** | 화면·UI 정리(하트, 수정 화면, 게이지, 수면 다이얼로그, 초대 등 제거), 원격 이미지 렌더링(`Image.network` 계열, 경계 측정·얼굴 위치 계산), 그림판 PNG 내보내기, 실기기 반영 |

1. **합의**: 이 문서의 인터페이스를 확정한다. (둘 다 이 경계에만 의존하므로 이후 병렬 작업이 가능하다.)
2. **병렬**: 백엔드는 서버 구현을 만들고, 프론트엔드는 메모리 구현을 새 인터페이스로 바꾼 채 UI를 정리한다.
3. **연결**: `app.dart`에서 메모리 구현 대신 서버 구현을 주입한다. 공용 파일이라 **한 사람만** 수정한다.

## 7. 프론트엔드에 묻는 것

1. 위 인터페이스 이름·시그니처가 실제 코드와 맞는지, 바꿔야 할 곳이 있는지
2. HTTP 클라이언트로 무엇을 쓰고 있는지 (`http`, `dio` 등). 새로 도입하지 않고 기존 것을 쓰겠습니다.
3. 메모리 구현을 데모·테스트용으로 계속 둘지 (제안: 둔다)
4. 로그인 세션(Supabase 토큰)을 앱의 어디서 들고 있는지, 서버 구현이 토큰을 어떻게 받아야 하는지 (예: 함수로 주입)
5. `CharacterFriend`의 `id`를 문자열 UUID로 바꿀 때 영향을 받는 곳(라우팅, 키 등)
