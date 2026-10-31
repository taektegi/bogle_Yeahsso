# 보글 (Bogle)

**내가 그린 그림이 살아 있는 친구가 되는 경험.**

그림을 그리고 친구의 이름과 성격을 정한 뒤, 함께 놀고 인형 주문까지 경험하는 **iPad 가로 화면용 Flutter 앱**입니다. 현재는 프론트엔드 프로토타입을 개발하고 있습니다.

팀 저장소의 `frontend/`에서 실행합니다. 최신 개인 프론트와 팀 서버 전용 변경을 함께 보존한 병합 범위·서버별 지원 차이는 [통합 기록](docs/TEAM_FRONTEND_MERGE_2026-10-31.md)을 참고하세요.

## 주요 기능

- **상상 스케치북**: 펜·형광펜·지우개, 굵기·색상·불투명도 조절, 확대·이동
- **친구 만들기**: 그림·사진 입력, 생성 대기 애니메이션, 이름·성격·말투 설정
- **친구 보관함과 집**: 캐릭터 관리, 대화, 간식 주기, 친구 초대, 잠자는 시간, 스스로 움직이는 캐릭터 모션 ([리그 규약](docs/CHARACTER_RIG.md))
- **인형 주문·마이페이지**: 인형 옵션 선택, 주문 흐름, 프로필·주문 내역 화면

> 기본 실행은 별도 서버 없이 가능합니다. 앱이 쓰는 데이터는 모두 `lib/src/data/app_services.dart`의 `AppServices`(친구·프로필·주문·캐릭터 생성·대화·모션)를 거치고, 아이패드 안에 저장됩니다. 서버 연동 기준은 개인 백엔드 `quasiaward/bogle_backend_try`의 `main`입니다. 서버 주소를 주면 캐릭터 생성·대화를 하고 변경을 동기화합니다. 이 백엔드는 서버 GIF 대신 앱 자체 모션을 사용하도록 안내합니다. 결제는 아직 실제로 진행되지 않습니다.

스케치북 초안과 도구 설정은 홈으로 나갔다 돌아와도 같은 앱 세션 안에서 유지됩니다. 앱을 완전히 종료하면 초기화됩니다. 기본 친구(뭉글이·뚜치·네모린)로 시작하고, 캐릭터 생성 서비스가 연결되기 전에는 아이가 그린 그림(또는 사진)이 그대로 새 친구가 됩니다.

## 개발 환경 및 실행

- 개발 기준: Flutter **3.41.5** / Dart **3.11.3**
- iOS 개발: macOS, Xcode, iPad 시뮬레이터 또는 실제 iPad
- 대상: iOS **15.0 이상**, iPad 가로 화면

저장소를 클론한 뒤 프로젝트 루트에서 실행합니다.

```sh
flutter pub get
flutter devices
flutter run -d <DEVICE_ID> -t lib/main.dart
```

실제 iPad는 Xcode에서 `ios/Runner.xcworkspace`를 열어 개발 팀과 서명을 설정해야 합니다. 케이블을 분리한 뒤에도 실행하려면 릴리스 모드로 설치합니다.

```sh
flutter run --release -d <IPAD_DEVICE_ID> -t lib/main.dart
```

### 보글 백엔드에 연결하기

데이터는 **아이패드에 저장되는 것이 기준**입니다. 친구 목록·그림·얼굴 지도·썸네일, 돌봄 수치·추억·레벨, 프로필, 주문·배송지는 앱 폴더(Application Support)에 파일로 남아, 서버 없이도 그대로 열립니다. 서버(`quasiaward/bogle_backend_try`)는 서버만 할 수 있는 일을 맡습니다.

- 그림으로 친구 만들기(AI 생성): 결과 그림·썸네일·얼굴 지도를 받아 아이패드에 저장
- 대화(AI 답, 이전 대화), 모션 클립(한 번 받으면 아이패드에 저장)
- 동기화: 수정·삭제는 아이패드에 먼저 저장하고 "보낼 일 목록(outbox)"으로 서버에 전합니다. 연결이 끊겨 있거나 앱이 꺼져도 다음 실행 때 이어서 보냅니다. 앱을 처음 설치했을 때는 서버에 있는 친구를 내려받아 아이패드에 저장합니다.

서버 주소와 시연 계정을 `--dart-define`으로 넣습니다. 앱에는 로그인 화면이 없어서 이 계정으로 자동 로그인합니다.

```sh
flutter run -d <DEVICE_ID> -t lib/main.dart \
  --dart-define=BOGLE_API_URL=https://<api-server> \
  --dart-define=SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key> \
  --dart-define=BOGLE_ACCOUNT_EMAIL=<demo-email> \
  --dart-define=BOGLE_ACCOUNT_PASSWORD=<demo-password>
```

- 생성 실패는 서버가 알려 준 이유를 보여 주고, 같은 그림으로는 안 되는 경우(`retryable: false`)에는 다시 시도 버튼 대신 그림으로 돌아가게 합니다.
- 서버 API가 바뀌면 서버 저장소의 `docs/openapi.json`을 `test/contract/openapi.json`으로 복사합니다. 계약 테스트(`test/contract_test.dart`)가 앱의 가짜 응답이 서버와 맞는지 확인합니다.
- 성격 선택지는 앱의 `friend_profile_choices.dart`에서 관리하고 선택한 문구를 `personality`로 보냅니다.
- 그림판은 `sourceType: drawing`, 촬영·선택 사진은 `photo`로 보냅니다. 입력 PNG/JPEG와 관계없이 서버의 친구 그림·썸네일은 PNG입니다.
- 개별 수면 일정과 기기의 UTC 오프셋을 서버에 보내 앱·대화의 수면 판정을 맞춥니다. 작업 만료와 데이터 시각은 계속 서버 UTC 기준입니다.
- [피드백 반영·검증 기록](docs/BACKEND_FEEDBACK_2026-10-29.md)에 실패 복구와 로컬 HTTP 통합 검증 방법을 정리합니다.

## 검증

```sh
flutter analyze
flutter test
```

## 프로젝트 구조

- `lib/src/screens/`: 화면 및 사용자 흐름
- `lib/src/widgets/`, `lib/src/theme/`: 공통 UI와 디자인 테마
- `lib/src/drawing/`: 스케치북 도구와 색상 선택
- `lib/src/data/`, `lib/src/models/`: 데이터 저장소·서비스 경계 및 모델
- `assets/`: 디자인 에셋과 양진체 폰트
- `test/`, `integration_test/`: 단위·위젯 테스트 및 통합 테스트
- `motion_server/`: 선택적으로 연결하는 그림 모션 생성 서버

## 참고 문서

- [모션 기능 사용법](docs/모션_기능_사용법.md) · [모션 서버 실행](motion_server/README.md)
- [로딩 모션 설계](LOADING_MOTION.md)
- [양진체 라이선스 (SIL OFL 1.1)](assets/fonts/Yangjin-OFL.txt)
