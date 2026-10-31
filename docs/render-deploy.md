# Render로 API 서버 배포하기

| 항목 | 내용 |
|---|---|
| 작성일 | 2026-11-01 |
| 대상 | API 서버(`server/`)를 시연용으로 배포하는 사람. 앱(Flutter)은 배포하지 않는다 |
| 목적 | 저장소 루트의 `render.yaml`(Render Blueprint)로 서버를 Render 싱가포르 리전에 띄우고, 앱이 그 주소를 쓰게 한다 |
| 근거 | `server/README.md`의 실행 조건(`--workers 1`), `docs/supabase-cloud-setup.md` |

> **주의**: Render의 화면 이름과 요금은 2026-11 기준 공식 문서와 검색 결과로 확인했습니다. **이 문서대로 실제 Render에 배포해 보지는 않았습니다.** 해 본 뒤 달랐던 부분은 이 문서를 고쳐 주세요.

## 0. 먼저 알아 둘 것

| 질문 | 답 |
|---|---|
| 왜 Render인가? | 서버 안의 생성 워커가 항상 돌아야 하고, Supabase(서울)와 가까운 싱가포르 리전이 있으며, Dockerfile 없이 GitHub 저장소만으로 배포됩니다 |
| 비용 | Render는 **워크스페이스 요금제**와 **인스턴스 비용**을 따로 받습니다. 요금표의 Hobby·Pro·Scale은 워크스페이스 요금제이고, 옆의 "+ compute"가 인스턴스 비용입니다. 워크스페이스는 **Hobby($0)**, 인스턴스는 `0.5c-512mb`(옛 Starter, 0.5 CPU·512MB) **월 $7**이라 합쳐서 **월 $7 정도**입니다 |
| Pro($25)가 필요한가? | **아니요.** Pro에 들어 있는 자동 확장은 이 서버에서 켜면 안 되는 기능입니다. Hobby에도 싱가포르 리전이 있습니다 |
| 인스턴스 가격은 어디서 보나? | [render.com/pricing](https://render.com/pricing)의 요금제 표 아래 **Compute** 부분이나, 서비스를 만들 때 인스턴스를 고르는 화면에서 봅니다. 결제 전에 확인하세요 |
| Free 인스턴스는? | 쓰지 않습니다. 15분 동안 요청이 없으면 잠들고, 깨어나는 데 1분쯤 걸리며, 잠든 동안 생성 워커와 정리 작업이 멈춥니다 |
| 인스턴스 수 | **1개만** 둡니다. 횟수 제한 기록이 프로세스 메모리에 있어서 여러 개면 따로 셉니다. 자동 확장을 켜지 않습니다 |
| DB·Storage | Render에는 만들지 않습니다. 기존 Supabase 프로젝트를 그대로 씁니다 |

## 1. 배포 전에 준비할 것

1. **Supabase 프로젝트에 마이그레이션이 모두 적용돼 있어야 합니다.** Render는 마이그레이션을 실행하지 않으므로 항상 DB 마이그레이션 → 서버 배포 순서로 합니다. `docs/supabase-cloud-setup.md` 2절의 `supabase migration list`로 원격과 로컬이 같은지 봅니다.
2. **비밀 값 5개**를 준비합니다. 뜻은 `server/.env`와 같습니다(`server/.env.example` 참고). 코드·채팅에 붙이지 않습니다.

   | 변수 | 값 |
   |---|---|
   | `SUPABASE_URL` | `https://<project-ref>.supabase.co` |
   | `SUPABASE_SERVICE_ROLE_KEY` | Supabase의 `service_role` 키 |
   | `DATABASE_URL` | Supavisor pooler 연결 문자열(transaction mode, 6543). 직접 연결(`db.<project-ref>.supabase.co`)은 IPv6 문제로 쓰지 않습니다 |
   | `OPENROUTER_API_KEY` | 이미지·대화 생성과 얼굴 분석용 |
   | `OPENAI_API_KEY` | 대화 안전 검사(Moderation)용 |

   - `SUPABASE_JWT_SECRET`은 넣지 않습니다. 지금 프로젝트는 ES256이라 서버가 `SUPABASE_URL`의 JWKS로 토큰을 검증합니다. 레거시 HS256 프로젝트를 쓸 때만 서비스의 **Environment**에 직접 추가합니다.
   - 나머지 설정(`GENERATION_CONCURRENCY` 등)은 코드 기본값이 `.env.example`과 같아서 넣지 않아도 됩니다.
3. **Render가 저장소를 읽을 수 있어야 합니다.** Render를 GitHub와 연결했는데 저장소 목록에 `taektegi/bogle_Yeahsso`가 안 보이면, 저장소 주인(`taektegi`)이 Render GitHub App 설치를 승인해야 합니다.
   - 승인을 받기 어려우면: 저장소가 공개라서 **New → Web Service → Public Git Repository**에 저장소 주소를 넣어 직접 만들 수 있습니다. 이때는 Blueprint를 쓰지 않으므로 5절 표의 값을 직접 입력하고, 자동 배포 대신 **Manual Deploy**로 배포합니다.

## 2. 처음 배포하기 (Blueprint)

1. [dashboard.render.com](https://dashboard.render.com)에서 **New → Blueprint**를 누릅니다.
2. 저장소 `taektegi/bogle_Yeahsso`를 고르고 브랜치는 `main`으로 둡니다. Render가 루트의 `render.yaml`을 읽어 `bogle-api` 서비스를 보여 줍니다.
3. 비밀 값을 입력하라는 칸(`render.yaml`에서 `sync: false`인 5개)에 1절의 값을 넣습니다.
4. 워크스페이스 요금제를 고르라고 하면 **Hobby**를 고릅니다. 인스턴스는 `render.yaml`의 `plan: 0.5c-512mb`로 정해지므로 따로 고르지 않습니다. 유료 인스턴스라서 결제 수단 등록을 요구할 수 있습니다.
5. 배포를 시작합니다. 빌드(`pip install .`)와 시작이 끝나고 `/v1/health`가 200을 돌려주면 배포가 끝난 것입니다.

## 3. 배포 확인

서비스 화면 위쪽의 주소(`https://bogle-api-xxxx.onrender.com` 형태)로 확인합니다.

| 순서 | 확인 | 기대 결과 | 다르면 |
|---|---|---|---|
| 1 | `GET /v1/health` | `{"status":"ok"}` | **Logs**에서 빌드·시작 오류 확인 |
| 2 | `/docs` | OpenAPI 문서 | |
| 3 | `GET /v1/me` (토큰 포함) | 200과 프로필 | 503이면 `DATABASE_URL`, 401이면 `SUPABASE_URL` |
| 4 | 앱에서 친구 만들기 한 번 | 생성 작업이 `succeeded`까지 진행 | **Logs**에서 OpenRouter·Storage 오류 확인 |

## 4. 앱을 배포한 서버에 연결하기

앱은 `BOGLE_API_URL`로 서버 주소를 받습니다. `/v1`은 앱이 붙이므로 **주소만** 넣습니다.

```bash
flutter run --dart-define=BOGLE_API_URL=https://bogle-api-xxxx.onrender.com
```

함께 넣는 나머지 값(`SUPABASE_URL`, `SUPABASE_ANON_KEY` 등)은 `frontend/lib/src/data/api/api_client.dart` 맨 위 주석을 따릅니다.

## 5. 설정값 (Blueprint 없이 직접 만들 때)

기준은 `render.yaml`입니다. 값을 바꾸면 `render.yaml`과 이 표를 같이 고칩니다.

| 항목 | 값 |
|---|---|
| Language | Python 3 |
| Branch | `main` |
| Region | Singapore |
| Instance Type | 0.5 CPU · 512 MB (`0.5c-512mb`) |
| Root Directory | `server` |
| Build Command | `pip install .` |
| Start Command | `uvicorn app.main:app --host 0.0.0.0 --port $PORT --workers 1 --no-access-log` |
| Health Check Path | `/v1/health` |
| 환경 변수 | `PYTHON_VERSION=3.11.11`, `APP_ENV=production`, 1절의 비밀 값 5개 |

## 6. 운영 중 주의할 점

- **시연 중에는 `main`에 머지하지 않습니다.** CI가 통과한 `main` 커밋은 자동으로 배포됩니다. 배포로 서버가 바뀌면 진행 중이던 친구 생성과 창문 배경 생성은 `generation_interrupted`(다시 시도 가능)로 실패 처리되고, 얼굴 분석은 좌표 없음으로 끝납니다.
- **재배포·재시작하면 횟수 제한 기록이 초기화됩니다.** 기록이 메모리에만 있기 때문입니다.
- **메모리가 부족하면** 서버가 재시작되고 **Events**·**Logs**에 기록이 남습니다. 그때는 Instance Type을 `1c-2g`로 올리고 `render.yaml`의 `plan`도 같이 바꿉니다.
- **비밀 값 바꾸기**: 서비스의 **Environment**에서 고칩니다. `sync: false` 값은 이후 Blueprint 동기화가 덮어쓰지 않습니다.
- **Supabase 무료 프로젝트는 활동이 없으면 일시 중지될 수 있습니다.** 시연 전에 Supabase 대시보드에서 상태를 확인합니다.
- **시연이 끝나면** 서비스를 삭제(**Settings → Delete Web Service**)해야 요금이 더 나가지 않습니다.

## 확인한 것과 확인하지 못한 것 (2026-11-01)

확인한 것:
- `render.yaml`이 Render 공식 스키마(`https://render.com/schema/render.yaml.json`)를 통과합니다.
- `main`(`d02315e`, 창문 배경 생성 포함)의 `server/`를 `git archive`로 깨끗하게 받아 `.env` 없이 Build Command와 Start Command를 그대로 실행했습니다. `/v1/health` 200, `/docs` 200, 토큰 없는 `/v1/me` 401이 나왔습니다. 로컬에 3.11이 없어 Python 3.12로 확인했습니다.
- DB·Storage 없이 뜬 서버의 메모리는 약 70MB였습니다.

확인하지 못한 것:
- 실제 Render 배포, Render의 Python 3.11.11 빌드, GitHub 연결과 `checksPass` 자동 배포
- DB에 연결하고 생성 작업이 돌 때의 메모리 사용량(512MB로 충분한지). 서버 안에서 친구 생성(최대 2개), 창문 배경 생성(1개), 얼굴 분석이 함께 돌 수 있습니다
- Render 싱가포르와 Supabase 서울 사이의 실제 응답 시간
