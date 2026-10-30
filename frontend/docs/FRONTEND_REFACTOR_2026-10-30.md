# 동작을 유지한 프론트엔드 구조 정리

기준: release `45f6765`. 기능·성능·디자인 변경을 만들지 않기 위해 기존 선언을
그대로 옮기고 같은 Dart 라이브러리의 `part`로 분리했다. 기존 프로젝트의
setup/house/order 화면과 같은 분리 방식을 사용한다.

| 진입 파일 | 정리 후 역할 | 분리된 파일 |
| --- | --- | --- |
| house/figure_motion.dart | 동작 목록·감정·포즈 모델 | controller, frame, reactions, playful_acts, interpolation |
| order/doll_options.dart | 주문 옵션·친구 선택의 화면 구성 | friend_grid, portrait, options_form, option_controls |
| photo_capture.dart | 촬영·편집 흐름과 카메라 수명 관리 | paper_frame, viewfinder_art, camera_controls, review_controls |
| archive_screen.dart | 보관함 조회·탐색·상태 | friend_house_card, friend_dialogs |
| home_screen.dart | 홈의 상태·진입·탐색 | home_card, bloom, decorations |

모두 `lib/src/screens` 아래이며, 새 파일은 각 진입 파일의 하위 역할 폴더에 있다.
주요 파일 5개에서 18개의 역할별 파일로 분리했다. FigureMotion 진입 파일은
2250→319줄, 주문 옵션은 1057→212줄로 줄어들었다.

## 보존한 내용과 검증

- 클래스·함수·상수·private 이름과 공개 import 경로를 유지한다.
- 위젯 트리·key·State 소유권·애니메이션 수식·난수/타이머 호출·캐시·API·저장 형식은 동일하다.
- 새 위젯 래퍼나 별도 런타임 서비스, 패키지 의존성을 추가하지 않았다.
- 추가한 part 지시문만 제거하고 새 파일의 내용을 원래 순서로 결합하면,
  변경 전 5개 파일의 원문과 **바이트 단위로 일치**함을 확인했다.
- 변경 전/후 전체 테스트 모두 **561 passed / 기존 3 skipped**.
- `flutter analyze`: No issues found. 포맷 변경 없이 분리됨(dart format 23 files, 0 changed).
- Xcode iPad Pro 12.9인치(5세대) 시뮬레이터에서 Debug 빌드·업데이트·실행 성공(PID 18601).
  홈 화면 캡처를 확인했다. 기존 저장 데이터 5개 파일의 SHA-256도 업데이트 전후 동일하다.
- 실행 시간·메모리의 별도 벤치마크 수치를 새로 측정한 것은 아니다. 성능 관련 연산과
  위젯 구조를 원문 그대로 보존하는 것으로 변경 범위를 제한했다.
- 사용자 지시에 따라 실제 iPad 설치는 진행하지 않았다.

원문 동일성 재현(리팩토링 직후 버전 기준):

```python
from pathlib import Path
import re, subprocess
roots = [
    'lib/src/screens/house/figure_motion.dart',
    'lib/src/screens/order/doll_options.dart',
    'lib/src/screens/photo_capture.dart',
    'lib/src/screens/archive_screen.dart',
    'lib/src/screens/home_screen.dart',
]
for name in roots:
    path = Path(name)
    source = path.read_text()
    parts = re.findall(r"^part '([^']+)';$", source, re.M)
    restored = re.sub(r"\n(?:part '[^']+';\n)+", '', source, count=1)
    for part in parts:
        body = (path.parent / part).read_text()
        restored += re.sub(r"^part of '[^']+';\n", '', body, count=1)
    baseline = subprocess.check_output(['git', 'show', '45f6765:' + name]).decode()
    assert restored == baseline, name
```
