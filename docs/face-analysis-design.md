# 캐릭터 PNG 얼굴 좌표 분석 설계

## 목적과 범위

Meta Animated Drawings 모션 파이프라인은 사용하지 않는다. Flutter가 담당하는 몸 전체 애니메이션에 더해,
생성된 투명 PNG 위에 눈꺼풀·입·볼 효과를 그릴 수 있도록 얼굴 좌표만 백엔드가 제공한다.

- 캐릭터 PNG 생성 직후 한 번만 OpenRouter의 이미지 입력 모델로 분석한다.
- 친구의 집에 들어갈 때 다시 분석하지 않는다.
- 호출·응답 파싱·좌표 검증이 실패하면 `face`를 `null`로 두고 친구 생성·저장은 계속한다.
- 원본 이미지나 AI 응답 본문은 로그에 남기지 않는다.
- 2026-10-09 사용자 결정으로 얼굴 분석 모델은 `openai/gpt-6-luna`를 사용한다.
- 프롬프트 문구는 유지하고, 사용자가 검수한 예시 6장을 매 요청에 함께 보낸다.

## 파일 배치와 관리

```text
server/
  app/
    face_analysis.py          호출·좌표 검증·알파 필터·실패 처리
    face_examples/
      README.md               예시 관리 안내
      reviewed.json           검수본 6장 좌표
      016.png / 028.png / dduchi.png / 021.png / 023.png / 029.png
  scripts/
    check_face_analysis.py    개발용 실제 PNG 수동 확인
  tests/
    test_face_analysis.py     외부 호출 mock·좌표·알파·예시 검증
    test_check_face_analysis.py
docs/
  face-analysis-design.md     규격·설정·생성 담당 연동 지점
```

기존 import 경로는 유지한다. 팀원이 `app.face_analysis`를 그대로 호출할 수 있도록
운영 코드를 다른 폴더로 옮기거나 인터페이스를 바꾸지 않는다.
검수 화면과 모델 비교 자료는 운영 패키지에 넣지 않는다. 원본 다운로드·검수 저장본,
주요 보고서·비용·좌표 결과는 보존하며 과거 실행 파일·중복 미리보기·빌드 캐시만 별도 보관한다.
생성 파이프라인 연결과 공개 API 계약 변경은 이 파일 정리 작업에 포함하지 않는다.

## 응답 계약

생성 작업의 `succeeded` 응답과 Character 응답에 nullable `face`를 추가한다. 값이 있으면 Flutter의
`docs/CHARACTER_RIG.md`와 같은 version 1 객체다.

```json
{
  "version": 1,
  "size": [1024, 1024],
  "facing": "front",
  "head": [250, 100, 520, 500],
  "eyes": [[410, 300, 42], [610, 300, 42]],
  "mouth": [510, 470, 130, 52],
  "cheeks": [[350, 420, 50], [670, 420, 50]]
}
```

`head`와 `mouth`는 모델이 판단할 수 없을 때 `null`, `eyes`와 `cheeks`는 없으면 빈 배열이다.
분석 전체가 실패하거나 검증을 통과하지 못하면 상위 응답의 `face`가 `null`이다.
`head`는 `[leftX, topY, width, height]`, `mouth`는 `[centerX, centerY, width, height]`다.
입의 이미지 범위 검증은 중심에서 반폭·반높이를 뺀 실제 상자 경계를 사용한다.

## 검증

`server/app/face_analysis.py`가 외부 응답을 신뢰하지 않고 다음을 확인한다.

- version 1, 허용된 키만 사용, 고정 길이 배열, 유한한 숫자
- `size`가 실제 PNG 가로·세로와 정확히 일치
- 상자 크기가 양수이고 상자·원이 이미지 범위 안에 있음
- 눈·볼은 각각 최대 2개이고 반지름이 이미지에 비해 과도하지 않음
- 머리가 있으면 눈·입·볼 중심이 머리 안에 있고, 눈·입 크기가 머리에 비해 과도하지 않음
- 실제 얼굴 효과를 만들 눈 또는 입 중 하나 이상 존재

서버는 응답 검증 뒤 원본 PNG 알파 채널로 눈·입·볼을 필터링한다. 특징 중심과 주변 4점 중
중심이 alpha >= 128이고 총 3점 이상이 alpha >= 128일 때만 유지한다. 주변 간격은 눈·볼의
반지름 / 4, 입의 폭 / 4와 높이 / 4다. 제거된 입은 null, 제거된 눈·볼은 배열에서 뺀다.
눈과 입이 모두 없어지면 face 전체를 null로 두며, 남은 좌표는 다시 검증한다.
알파가 없는 PNG는 불투명하게 취급한다. head는 필터링하지 않는다. 이 검사는 부위 전체가
불투명하다는 보장이 아니며 몸 안의 무늬 오인이나 과도한 입 박스도 해결하지 못한다.
Flutter의 추가 알파 검사도 유지할 수 있다.

## 호출 조건과 예시 자료

- `/chat/completions`로 system 프롬프트 → 예시 6장의 user/assistant 쌍 → 대상 PNG 순서로 보낸다.
- 예시와 대상 이미지 모두 detail=original, reasoning.effort=high, max_tokens=16000이다.
- 추론 모델 요청에 temperature와 max_completion_tokens는 보내지 않는다.
- 엄격한 JSON Schema 출력, provider.require_parameters와 usage 반환을 유지한다.
- `server/app/face_examples/`에 016·028·뚜치·021·023·029 원본 PNG와 `reviewed.json`을 둔다.
  사용자 저장본의 좌표·볼·029의 left를 그대로 포함하며 패키지 설치 시에도 함께 배포한다.
- 예시는 처음 읽을 때 크기·좌표·검수 상태를 확인하고 캐시한다. Downloads나 임시 경로에 의존하지 않는다.
- 유료 호출 전에 실제 입력 PNG를 디코딩하고 크기를 대조한다. 잘못된 PNG는 호출하지 않는다.
- 기본 대기 시간은 120초다. 테스트용 240초보다 낮춘 운영 초기 상한으로, 전체 생성 작업
  제한 시간과의 조정은 담당 B의 생성 파이프라인 연결 때 확인한다.
- 분석이 실패하면 analyze_face_best_effort 경계에서 None을 반환하며 기존 생성 성공을 유지한다.
- 이번 6장/3장 비교에서 효과용 볼은 여전히 반환되지 않았다. 예시 6장을 사용하는 것은 사용자
  선택이며 정확도 향상을 보장하는 것은 아니다. 프롬프트 문구와 확대 분석 방식은 바꾸지 않았다.

## 생성 파이프라인 통합 지점

현재 저장소에는 담당 B의 업로드·생성 작업이 아직 없다. 그 구현이 들어올 때 아래 순서로 연결한다.

1. OpenRouter 이미지 생성 결과를 실제 투명 PNG로 검증한다.
2. 그 PNG 바이트와 실제 크기를 `analyze_face_best_effort()`에 넘긴다.
3. 반환된 `FaceMap | None`을 생성 작업 행의 nullable `face jsonb`에 아트 결과와 함께 저장한다.
4. 생성 작업 `succeeded` 응답에 저장된 `face`를 그대로 반환한다.
5. `POST /v1/characters`가 생성 작업의 `face`를 `friends.face`로 복사한다.
6. 친구 목록·상세 응답은 `friends.face`를 반환한다. DB 값이 현재 검증을 통과하지 못하면 조회 자체는
   살리고 `face: null`로 낮춘다.

분석은 캐릭터 아트 생성 성공을 커밋한 뒤 실행하거나, 작업 처리 중 예외를 반드시 삼키는 경계 안에서
실행해야 한다. 얼굴 분석 때문에 작업을 `failed`로 바꾸면 안 된다.

## 운영 설정

| 환경변수 | 뜻 | 없을 때 |
|---|---|---|
| `OPENROUTER_API_KEY` | 생성용 서버 키 | 얼굴 분석 비활성 |
| `OPENROUTER_FACE_MODEL` | 이미지 입력·구조화 출력·현재 요청 설정을 지원하는 모델 ID. 기본 `openai/gpt-6-luna` | 기본값 사용 |
| `FACE_ANALYSIS_TIMEOUT_SECONDS` | 얼굴 분석 대기 시간, 기본 120초 | 기본값 사용 |

테스트는 외부 호출을 mock으로만 확인한다. 실제 모델별 좌표 정확도와 비용은 승인된 소수의 시연용
이미지로 별도 측정한 뒤 모델을 확정한다.

## 실제 PNG 수동 확인

`/docs`에는 얼굴 분석 전용 API를 추가하지 않는다. 담당 B의 업로드·생성 작업이 아직 없고, 개발용
엔드포인트를 공개 API 계약에 섞지 않기 위해 `server/scripts/check_face_analysis.py`를 사용한다.
이 명령에는 Supabase 설정이 필요하지 않고 `server/.env`의 `OPENROUTER_API_KEY`만 필요하다.

```bash
cd server
python -m scripts.check_face_analysis \
  /Users/taeksookim/Documents/Bogle_doll_making_app/assets/figma/nemorin.png \
  --output /tmp/bogle-face-test/nemorin.ai.face.json
```

- 입력은 투명 배경 캐릭터 PNG 경로다. 파일을 백엔드 폴더로 복사할 필요가 없다.
- `--output`을 생략하면 결과 JSON을 터미널에 출력한다.
- 기존 결과 파일은 기본적으로 덮어쓰지 않는다. 의도적으로 덮어쓸 때만 `--force`를 붙인다.
- 실제 호출은 과금될 수 있으므로 승인한 시연용 이미지에만 실행한다.
- 결과는 같은 폴더의 `nemorin.face.json` 또는 `dduchi.face.json`과 비교하고, 최종적으로 Flutter에서
  눈·입 효과를 겹쳐 위치를 확인한다.

## 초기 모델 검토 기록 (현재 선택은 Luna)

두 후보 모두 이미지 입력과 `response_format` JSON Schema 구조화 출력을 지원한다. OpenRouter의
`provider.require_parameters=true`를 함께 보내 이 기능을 지원하는 제공자만 선택한다.

| 후보 | 공개 단가(입력/출력 100만 토큰) | 판단 |
|---|---:|---|
| `openai/gpt-4.1-mini` | $0.40 / $1.60 | **선택됨.** 이미지 입력·구조화 출력 지원이 명시돼 있고, 중간급 모델이라 형식 준수와 시각 판단의 첫 기준점으로 사용한다 |
| `qwen/qwen3-vl-8b-instruct` | $0.117 / $0.455 | 비용 절감이 필요할 때 비교할 예비 후보. 실제 캐릭터 좌표 정확도 비교 전에는 자동 전환하지 않는다 |

출처: [OpenRouter 구조화 출력](https://openrouter.ai/docs/guides/features/structured-outputs),
[GPT-4.1 Mini](https://openrouter.ai/openai/gpt-4.1-mini),
[Qwen3 VL 8B Instruct](https://openrouter.ai/qwen/qwen3-vl-8b-instruct).

공개 벤치마크는 일반 시각 이해를 비교할 뿐 보글의 캐릭터 얼굴 픽셀 좌표 정확도를 보장하지 않는다.
따라서 모델 확정 뒤에도 대표 PNG 소수로 눈·입 위치를 사람이 겹쳐 보고 통과 기준을 정해야 한다.
