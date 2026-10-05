# Code Quality Assessment

## Test Coverage
- **Overall**: 백엔드 None / 프론트엔드 Fair(UI·mock 한정) / 모션 서버 None
- **Unit Tests**: 백엔드 없음. 앱은 `test/`에 위젯·로직 테스트가 있음 (메모리 저장소 기준)
- **Integration Tests**: 앱 `integration_test/`는 UI 흐름 검증. 인증·DB 정합성·실제 생성·결제를 검증하지 않음. RLS 정책 테스트 없음

## Code Quality Indicators
- **Linting**: 앱 `flutter_lints ^6.0.0` 구성됨. SQL·Python 린트 없음
- **Code Style**: 일관됨. SQL 마이그레이션은 명명 규칙(`<table>_<action>_own`, `<table>_<cols>_idx`)이 정돈되어 있음
- **Documentation**: 백엔드 README는 Good(구조·RLS·적용 방법). 앱은 README·디자인 문서가 있으나 일부 내용이 코드와 다름(PRD 12절 지적: 모션 출력 360px vs README 720px)

## Technical Debt
보글 백엔드 요구사항·설계에 직접 영향을 주는 항목 위주로 정리한다.

### 범위·기준 관련
- **TD-01 백엔드 스키마 도메인 불일치** — `supabase/migrations` 전체. 테이블·버킷·README가 "오늘의 필름"용이다. 보글 백엔드를 이 저장소에서 만들려면 기존 마이그레이션을 유지할지(되돌리는 마이그레이션 추가) 아니면 초기화할지 결정해야 한다. 원격 Supabase 프로젝트에 이미 적용되었는지는 저장소만으로 알 수 없다.
- **TD-02 PRD와 최신 프론트엔드의 차이** — PRD는 `9c7ba17`(design_develop) 기준이고, `main-develop`(`daabf83`)에 다음이 반영되어 있다.

| # | 변경 | 영향을 받는 PRD 항목 |
|---|---|---|
| D1 | `CharacterFriend.introduction` 추가 (수정 시 최대 70자, 생성 시 입력 없음) | FR-03, 6절 Character 모델 |
| D2 | 친구별 `SleepSchedule`(취침·기상 분, 기본 21:00–07:00)로 **자동 수면**. 수동 재우기/깨우기 없음 | FR-05 상태표·행동표 |
| D3 | 비눗방울 놀이 **삭제**, **초대**(내 다른 친구를 손님으로) 추가 — 집주인 기분 +6, 친밀도 +1 | FR-05 놀이 규칙, `playSessionId` 제안 |
| D4 | 실제 카메라 촬영·사진 보관함 선택·사진 편집 추가 (JPEG 바이트 생성) | FR-02 "사진 모드는 샘플만" 서술 |
| D5 | 마이페이지 "찜한 캐릭터" 섹션 삭제. 찜 데이터와 하트 토글은 보관함·마이페이지 타일에 남음 | FR-04, FR-09 |
| D6 | `camera`, `image_picker`, `xml`, `url_launcher` 의존성 추가, 카메라·사진 권한 문구 추가 | 동의·개인정보 정책 |
| D7 | 대화 주제 `welcome`/`bye` 추가 (손님 맞이·배웅) | FR-06 |

  변경 없음: `character_generation.dart`, `motion_service.dart`, `motion_server/`, `order_catalog.dart`, `order_screen.dart` — PRD 5절(모션 계약)과 FR-07·FR-08 서술은 그대로 유효.
- **TD-03 기준 브랜치 불명확** — 로컬 프론트엔드 체크아웃은 `main`(`2450b6f`, 2026-09-26)이며 PRD 기준과 `main-develop`보다 뒤처져 있다. 백엔드 계약을 맞출 기준 브랜치를 정해야 한다.

### 서버로 옮길 때 바로잡아야 할 규칙
- **TD-04 수면 경과 계산 결함** — `FriendStatus.aged()`는 저장된 `asleep` 값 하나로 전체 경과 시간을 계산한다. 예: 20:00(깨어 있음)에 앱을 닫고 다음 날 08:00에 열면 12시간 전부를 "깨어 있음"으로 계산해 기운이 −36이 된다. 밤사이 수면 회복(+15/h)이 반영되지 않는다. 그 뒤 `_load()`가 일정에 맞춰 `asleep`만 보정한다. 서버에서는 **수면 일정 구간별로 나눠 계산**해야 한다.
- **TD-05 깨기 보상 불일치** — 화면에 있는 동안 기상하면 기운 `max(현재,90)`·기분 +5, 화면 진입 시 보정으로 깨면 기분 +5가 없다. 같은 사건의 결과가 경로에 따라 다르다.
- **TD-06 초대 보상 무제한** — 초대할 때마다 기분 +6·친밀도 +1이며 횟수·쿨다운 제한이 없다. 손님 친구의 상태는 바뀌지 않는다. 서버 검증 시 반복 보상 정책이 필요하다.
- **TD-07 대화 저장의 경합과 비원자성** — `_send()`는 전송 전 상태(`s`)를 잡아 두었다가 450ms 뒤 그 값 기준으로 저장한다. 그사이의 돌봄 결과를 덮어쓸 수 있다. 추억 추가(`addMemory`)와 성장(`saveFriend`)도 별도 호출이다.
- **TD-08 전체 객체 덮어쓰기** — `saveFriend()`가 생성·수정·성장·수면 일정을 모두 처리하고, `saveProfile()`이 찜을 포함한 프로필 전체를 덮어쓴다. 클라이언트가 `level`·`memories`를 임의로 바꿀 수 있는 구조다.
- **TD-09 입력 데이터 단절** — 그림(`_create()`)과 사진(`_createFromPhoto(photo) => _create()`) 모두 생성 흐름에 바이트를 넘기지 않는다. 설정 화면은 고정 아트 `_art`와 고정 색 `0xFFB8C9FF`를 쓴다.
- **TD-10 삭제 복구 불완전** — "다시 데려오기"는 `saveFriend(friend)`로 친구 객체와 찜만 되살린다. 상태·추억 원문은 사라지지만 친구 객체의 `memories` 카운트는 돌아온다.
- **TD-11 주문 정보 누락** — 결제수단·연락처·우편번호·배송 메모·보호자 동의가 주문에 저장되지 않는다. 금액은 앱에서 계산하고, 주문번호는 기기 시각으로 만든다.
- **TD-12 사진형 아트 판정이 경로 문자열 의존** — `isPhotographedArt()`가 `/archive_` 포함 여부로 판정한다. 서버 이미지 URL로 바뀌면 동작하지 않는다.
- **TD-13 아바타가 에셋 경로** — `UserProfile.avatar`가 친구 ID가 아니라 에셋 경로라 친구 삭제와 연결되지 않는다.

### 모션 서버
- **TD-14 사용자 격리 없음** — 콘텐츠 해시 작업 ID와 공개 URL, 1년 캐시. 인증·소유권·삭제 정책과 충돌한다 (PRD 5절 서비스화 제안과 동일).
- **TD-15 지속성 없는 큐** — 단일 프로세스 메모리 큐, 단일 워커. 수평 확장 불가.

### 백엔드 워크스페이스 위생
- **TD-16** `.DS_Store` 파일이 커밋되어 있고 `.gitignore`가 없다.
- **TD-17** `supabase/config.toml`이 없어 `supabase start`를 바로 실행할 수 없다(먼저 `supabase init` 필요 여부 확인).

## Patterns and Anti-patterns
- **Good Patterns**:
  - RLS 조건을 `(select auth.uid())`로 감싸 행마다 재평가하지 않게 함 (initplan 캐싱)
  - 자식 테이블 정책이 직접 `user_id`와 상위 레코드 소유권을 함께 검사
  - `security definer` 함수에 `set search_path = ''`, API 역할의 실행 권한 회수
  - Storage 경로 첫 폴더를 사용자 ID로 강제하는 정책
  - 이름 변경을 별도 마이그레이션으로 처리해 데이터 보존
  - 앱: 저장소 인터페이스, 생성 작업 추상화, 모션 실패 시 기본 애니메이션, 카메라 실패 유형 구분
- **Anti-patterns**:
  - 게임 규칙이 화면 코드(`friend_screen.dart`)에 흩어져 있음 — 서버로 옮길 때 단일 규칙 모듈이 필요
  - 저장 결과를 기다리지 않는 `saveStatus()` 호출 (`friend_screen.dart` `_care`, `_ate`, `_arrived`)
  - `saveFriend()` 반환값 미사용 (`setup_friend_screen.dart` `_befriend`)
  - 시각 기반 ID (`friend-<ms>`, 주문번호)
