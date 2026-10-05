# 보글 API 서버

FastAPI로 만든 보글 백엔드 서버입니다. 기준 문서는 `aidlc-docs/inception/requirements/requirements.md`입니다.
API 계약의 기준은 서버를 띄우면 열리는 **`/docs`(OpenAPI)** 입니다.

## 실행

Python 3.11 이상이 필요합니다. 모든 명령은 `server/` 폴더에서 실행합니다.

```bash
python -m venv .venv
source .venv/bin/activate          # Windows PowerShell: .venv\Scripts\Activate.ps1
pip install -e ".[dev]"
cp .env.example .env               # 값을 채운다 (Windows PowerShell: Copy-Item .env.example .env)

uvicorn app.main:app --reload --no-access-log
```

- API 문서: http://localhost:8000/docs
- 상태 확인: http://localhost:8000/v1/health

## 검사

```bash
pytest                  # 테스트
ruff check .            # 린트
ruff format .           # 포맷
```

PR을 올리기 전에 세 가지가 모두 통과해야 합니다.

## 폴더 구조

```text
server/
├── pyproject.toml          의존성과 도구 설정
├── .env.example            환경변수 이름 (값은 .env에만 적는다)
├── app/
│   ├── main.py             앱 생성, 미들웨어·오류 처리·라우터 연결
│   ├── config.py           환경변수 설정 (Settings)
│   ├── auth.py             Supabase 토큰 검증 → CurrentUserDep
│   ├── errors.py           공통 오류 형식과 ApiError
│   ├── request_context.py  requestId 부여, 접근 로그
│   ├── schemas.py          CamelModel (JSON은 camelCase)
│   └── routers/
│       ├── __init__.py     라우터 등록 (공용 파일)
│       └── health.py       GET /v1/health
└── tests/
    ├── probe.py            테스트 전용 라우터 (인증·오류·검증 확인용)
    └── test_*.py
```

## 새 API를 만들 때

1. `app/routers/`에 라우터 파일을 만든다. 요청·응답 모델은 `CamelModel`을 상속한다.
2. `app/routers/__init__.py`의 `api_routers`에 **한 줄만** 추가한다. 경로는 자동으로 `/v1` 아래에 붙는다.
3. 로그인이 필요한 API는 인자로 `user: CurrentUserDep`을 받는다. **사용자 ID는 `user.id`(토큰)만 쓰고**, 요청 본문·쿼리의 사용자 ID는 쓰지 않는다.
4. 오류는 `raise ApiError(status_code, code, message)`로 낸다. 다른 사용자의 리소스는 404를 돌려준다.
5. 라우터의 `responses=ERROR_RESPONSES`로 오류 형식을 문서에 드러낸다.

```python
from fastapi import APIRouter

from app.auth import CurrentUserDep
from app.errors import ERROR_RESPONSES, ApiError
from app.schemas import CamelModel

router = APIRouter(tags=["friends"], responses=ERROR_RESPONSES)


class FriendOut(CamelModel):
    id: str
    name: str


@router.get("/friends/{friend_id}", response_model=FriendOut)
def get_friend(friend_id: str, user: CurrentUserDep) -> FriendOut:
    ...  # user.id 로 소유자를 확인하고, 내 것이 아니면:
    raise ApiError(404, "friend_not_found", "친구를 찾을 수 없어요.")
```

## 공통 규약

| 항목 | 규칙 |
|---|---|
| 경로 | `/v1` 접두어 |
| JSON 필드 | camelCase (`CamelModel`이 처리) |
| 시각 | UTC ISO 8601 |
| 오류 형식 | `{"error": {"code", "message", "retryable", "fieldErrors", "requestId"}}` — 자세한 설명은 `app/errors.py` |
| 입력 검증 실패 | 422, `code: validation_error`, `fieldErrors`는 `{필드: 오류 종류}` (예: `{"name": "string_too_short"}`) |
| requestId | 응답 헤더 `X-Request-Id`와 오류 본문의 `requestId`가 같다. 앱이 같은 헤더를 보내면 그 값을 쓴다 |
| 로그 | 메서드·경로·상태·시간만 남긴다. 요청 본문과 쿼리는 남기지 않는다 |

## 인증

앱은 Supabase 로그인으로 받은 액세스 토큰을 `Authorization: Bearer <토큰>`으로 보냅니다.
서버는 토큰의 서명·만료·audience·issuer를 검증하고 `sub`를 사용자 ID로 씁니다.

- Supabase 프로젝트가 **비대칭 서명 키**(ES256/RS256)를 쓰면 `SUPABASE_URL`만 설정합니다. 서버가 JWKS에서 공개 키를 받습니다.
- **레거시 공유 비밀**(HS256)을 쓰면 `SUPABASE_JWT_SECRET`도 설정합니다.
- 어느 쪽인지 모르겠으면 둘 다 채워도 됩니다. 토큰 헤더의 알고리즘에 맞는 키만 사용합니다.

## 아직 없는 것

- DB·Storage 접근 계층 (`service_role` 키로 쓰기). 첫 기능 API(보관함 목록)를 만들 때 함께 정합니다.
- 멱등 키(`Idempotency-Key`) 처리, 사용자별 횟수 제한(429)
