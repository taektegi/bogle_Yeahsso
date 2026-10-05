# 클라우드 Supabase와 Google 로그인 설정 안내

| 항목 | 내용 |
|---|---|
| 작성일 | 2026-10-05 |
| 대상 | 담당 A(권희준). 클라우드 프로젝트와 Google OAuth를 처음 만드는 사람 |
| 목적 | 개발용 클라우드 Supabase 프로젝트를 만들고, Google 로그인으로 서버(`/v1/me`)까지 한 번에 확인한다 |
| 근거 | `requirements.md` FR-01, NFR-03, NFR-11. 로컬 Supabase 검증 결과는 `supabase/README.md`와 PR #10 |

> **주의**: 아래 화면 이름과 메뉴 위치는 2026-10 기준으로 아는 구조입니다. Supabase·Google Cloud 콘솔은 자주 바뀌므로 이름이 조금 다르면 비슷한 항목을 찾으세요. 작성 당시 Supabase 공식 문서를 직접 열어 보지 못했습니다. 막히면 [Supabase의 Google 로그인 문서](https://supabase.com/docs/guides/auth/social-login/auth-google)를 확인하세요.
>
> 1~2절과 6~8절은 이메일 계정으로, 3~4절은 **Web 클라이언트와 브라우저 방식으로** 실제로 따라 해 봤습니다(맨 아래 "클라우드 검증 결과"). **iOS 클라이언트와 5절(앱의 네이티브 로그인)은 아직 따라 해 보지 않았습니다.** 해 본 뒤 달랐던 부분은 이 문서에 고쳐 주세요.

## 0. 먼저 알아 둘 것

| 질문 | 답 |
|---|---|
| 팀원도 클라우드 프로젝트가 필요한가? | **아니요.** 각자 로컬 Supabase(`server/README.md`의 "로컬 Supabase로 서버 확인하기")로 개발합니다. 클라우드는 Google 로그인 확인, 앱 연동, 시연용입니다 |
| 프로젝트는 몇 개? | **개발용 1개를 먼저** 만듭니다. 시연용은 따로 만들어 분리합니다 (NFR-11). 시연용 프로젝트는 시연이 가까워지면 만듭니다 |
| 비용 | 무료(Free) 플랜으로 시작할 수 있습니다. **무료 프로젝트는 일정 기간(약 1주) 활동이 없으면 일시 중지될 수 있으니** 시연 전에 상태를 확인하세요 |
| 클라우드 키는 누가 가지나? | 서버를 띄우는 사람(지금은 권희준)과 배포 환경만. 팀원에게 `service_role` 키를 나눠 주지 않습니다 |
| 시연 기기는? | **아이패드 한 대(iOS)** 로 정했습니다. 그래서 Google에는 **Web 클라이언트와 iOS 클라이언트**만 만들고 Android 클라이언트(SHA-1)는 만들지 않습니다. 프론트에 Mac과 아이패드가 있어 iOS 빌드는 가능합니다 |

## 1. Supabase 프로젝트 만들기

1. [supabase.com/dashboard](https://supabase.com/dashboard)에 로그인하고 **New project**를 만듭니다.
   - 이름: `bogle-dev` (시연용은 `bogle-demo`)
   - Region: **Northeast Asia (Seoul)** 이 가까워서 빠릅니다
   - **Database password**: 길고 무작위로 만들고 **비밀번호 관리자에 저장**합니다. 나중에 `db push`와 `DATABASE_URL`에 씁니다. 코드·채팅에 붙이지 않습니다
2. 만들어지면 프로젝트 주소의 ref(`https://<project-ref>.supabase.co`의 `<project-ref>`)를 적어 둡니다.

## 2. 마이그레이션 적용하기

저장소 루트에서 실행합니다 (PowerShell). **`supabase link`로 어느 프로젝트인지 반드시 확인한 뒤** `db push` 합니다.

```powershell
supabase login
supabase link --project-ref <project-ref>     # CLI 2.117에서는 비밀번호를 묻지 않았습니다
supabase migration list                       # 원격 칸이 비어 있고 로컬 4개만 있어야 정상
supabase db push --dry-run                    # 적용될 목록만 미리 보기
supabase db push                              # supabase/migrations/*.sql 적용
```

- 확인한 CLI(2.117.0)에서는 `link`가 DB 비밀번호를 묻지 않았습니다. 로그인 토큰으로 프로젝트를 확인하고, 이후 `migration list`·`db push`는 CLI가 임시 로그인 역할을 만들어 접속했습니다. 이 방식에서는 DB 비밀번호가 `.env`의 `DATABASE_URL`에만 필요합니다.

- `db reset`은 **원격에 절대 실행하지 않습니다.** 로컬 전용입니다.
- 확인: 대시보드 **Table Editor**에 `profiles`, `friends`, `assets`가 있고, **Storage**에 `bogle-media`(비공개)가 있어야 합니다.
- `Database → Triggers`(또는 `auth.users`)에 `on_auth_user_created`가 있는지 봅니다. 이것이 가입할 때 프로필을 만듭니다.

## 3. Google Cloud에서 OAuth 클라이언트 만들기

[console.cloud.google.com](https://console.cloud.google.com)에서 진행합니다.

### 3.1 프로젝트와 동의 화면
1. 새 프로젝트를 만듭니다 (예: `bogle`).
2. **Google Auth Platform**(예전 이름: *APIs & Services → OAuth consent screen*)으로 들어가 시작합니다.
   - 앱 이름: `보글`, 지원 이메일: 본인 이메일
   - 대상(Audience): **External(외부)**
   - 게시 상태: **Testing(테스트)** 로 둡니다. 시연용 계정만 쓰므로 심사받을 필요가 없습니다
   - **Test users**에 **시연·개발에 쓸 Google 계정을 모두 추가**합니다. 목록에 없는 계정은 로그인이 거부됩니다
   - **실제로 존재하고 활성 상태인 Google 계정만** 추가됩니다. 만들지 않은 주소(예: 짐작한 `이름@gmail.com`)를 넣으면 "이메일 주소는 활성 상태인 Google 계정 … 연결되어 있어야 합니다"라는 오류가 나고 저장되지 않습니다. 개발 확인에는 **본인 계정 하나**로 충분하고, 시연용 계정은 시연 전에 만들어서 추가합니다
3. 범위(scope)는 기본인 `openid`, `email`, `profile`이면 충분합니다. 민감한 범위를 추가하지 않습니다.

> Testing 상태에서는 로그인 유지(리프레시 토큰)가 약 7일 뒤 끊길 수 있습니다. 시연 직전에 다시 로그인해 두세요.

### 3.2 클라이언트 ID 만들기
**Clients(사용자 인증 정보) → Create client**에서 만듭니다.

시연 기기가 아이패드이므로 아래 **두 개**를 만듭니다.

| 종류 | 용도 | 입력값 |
|---|---|---|
| **Web application** | Supabase에 등록하는 ID이고, 앱이 `serverClientId`로 씁니다 | Authorized redirect URI: `https://<project-ref>.supabase.co/auth/v1/callback` |
| **iOS** | 아이패드(iOS) 앱의 네이티브 로그인 | **번들 ID**(앱의 Bundle Identifier. 프론트에게 받습니다) |

> **애플리케이션 유형을 반드시 "웹 애플리케이션"으로 고릅니다.** "데스크톱 앱" 등 다른 유형으로 만들면 **승인된 리디렉션 URI 칸이 없고**, 로그인할 때 `400 redirect_uri_mismatch`가 납니다(실제로 겪은 실수). 클라이언트 상세 화면 제목이 "웹 애플리케이션의 클라이언트 ID"인지 확인하세요. 유형은 나중에 바꿀 수 없으므로 잘못 만들었으면 새로 만들고 Supabase의 Client ID·secret도 새 값으로 바꿉니다.

- **승인된 리디렉션 URI**에는 4절에서 복사한 Supabase의 **Callback URL**을 붙여 넣습니다. 끝에 `/`나 공백이 붙지 않게 하고, **승인된 JavaScript 원본**은 비워 둡니다. 설정이 반영되는 데 몇 분이 걸릴 수 있습니다.
- "This client will be used by an AI-powered agent" 체크박스는 체크하지 않습니다.
- Web application의 **Client ID와 Client secret**을 안전한 곳에 저장합니다. 클라이언트 상세 화면에서 secret의 복사 버튼으로 나중에도 복사할 수 있습니다. secret은 Supabase에만 넣고 앱·저장소·채팅에는 넣지 않습니다.
- iOS 클라이언트를 만들면 **iOS URL scheme**(`com.googleusercontent.apps.…` 형태)이 함께 나옵니다. 앱의 `Info.plist`에 필요하므로 5절에 쓰기 위해 적어 둡니다.
- Android 기기를 쓰게 되면 **Android 클라이언트**(패키지 이름 + 디버그/릴리스 SHA-1 지문)를 추가하고 4절 Client IDs에도 넣습니다.

## 4. Supabase에 Google 연결하기

대시보드 **Authentication → Sign In / Providers(또는 Providers) → Google**:

0. 이 화면의 **Callback URL (for OAuth)** 을 복사 버튼으로 복사해 둡니다. 3.2절의 승인된 리디렉션 URI에 그대로 붙여 넣는 값입니다. 직접 타이핑하면 오타가 나기 쉽습니다.
1. **Enable Sign in with Google**을 켭니다.
2. **Client IDs**: **Web application의 Client ID와 iOS Client ID를 쉼표로 구분해서 함께** 넣습니다 (예: `<web-id>,<ios-id>`). iOS ID가 아직 없으면 Web ID만 먼저 넣고, 나중에 쉼표로 추가합니다.
3. **Client Secret**: Web application의 secret을 넣습니다 (iOS 클라이언트에는 secret이 없습니다).
4. **Skip nonce check**를 **켭니다.** iOS 네이티브 로그인이 이 설정 없이는 실패합니다.
5. **Authentication → URL Configuration**
   - 앱이 브라우저를 거치는 OAuth 방식을 쓰면 앱의 **딥링크 주소**를 Redirect URLs에 추가합니다 (예: `io.supabase.bogle://login-callback`). 네이티브 로그인(`signInWithIdToken`)만 쓰면 필요 없습니다
   - Site URL은 앱이 쓰지 않으면 기본값으로 둡니다

## 5. 앱에서 로그인하는 방법 (Flutter, 참고)

앱 연동은 FR-11.1입니다. 구현할 사람이 정해지면 아래를 따릅니다. **두 방식 중 하나를 고릅니다.**

| 방식 | 설명 | 추천 |
|---|---|---|
| **네이티브 로그인** | `google_sign_in`으로 Google 계정을 고르고, 받은 ID 토큰을 `supabase.auth.signInWithIdToken`에 넘김 | 모바일에서 화면이 자연스러움. **추천** (프론트 확인 대기) |
| 브라우저 OAuth | `supabase.auth.signInWithOAuth(OAuthProvider.google)` + 딥링크 | 설정이 적지만 브라우저가 한 번 열림 |

```dart
// 네이티브 로그인 스케치 (supabase_flutter, google_sign_in)
final googleSignIn = GoogleSignIn(
  serverClientId: '<Web application Client ID>',
  clientId: '<iOS Client ID>',
);
final account = await googleSignIn.signIn();
final auth = await account!.authentication;
await Supabase.instance.client.auth.signInWithIdToken(
  provider: OAuthProvider.google,
  idToken: auth.idToken!,
  accessToken: auth.accessToken,
);
```

- **iOS 설정** (`ios/Runner/Info.plist`):
  - `GIDClientID`: iOS Client ID
  - `CFBundleURLTypes`의 `CFBundleURLSchemes`: 3.2절에서 적어 둔 iOS URL scheme (`com.googleusercontent.apps.…`)
  - 앱의 Bundle Identifier가 3.2절의 iOS 클라이언트에 등록한 번들 ID와 **같아야** 합니다
- `google_sign_in`의 API는 버전마다 다릅니다(예: 최신 버전은 `GoogleSignIn.instance.initialize(...)` 방식). 위 코드는 형태를 보여 주는 스케치이므로, 쓰는 버전의 문서를 따르세요.
- 아이패드 실기기에 올리려면 Xcode에서 Apple ID로 서명하고, 기기에서 **개발자 모드**를 켜야 합니다 (설정 → 개인정보 보호 및 보안). 무료 Apple ID는 서명이 짧게 만료되므로 시연 직전에 다시 올려 두세요.
- 앱에는 **Supabase 주소와 publishable(anon) 키만** 넣습니다. `service_role` 키와 Google secret은 넣지 않습니다 (NFR-03).
- 서버 호출에는 `Authorization: Bearer <session.accessToken>`을 붙입니다. 401이 오면 SDK로 토큰을 갱신하고 한 번만 다시 요청합니다 (API 계약 v1 2절).

## 6. 서버에 클라우드 값 넣기

`server/.env`를 채웁니다. **이 파일은 커밋하지 않습니다.**

> 서버는 `server/`에서 실행하고 `.env`를 그 폴더 기준으로 읽습니다. 저장소 루트에 `.env`를 만들면 읽히지 않습니다.
> 검증 중에 있었던 실수입니다. ① `SUPABASE_SERVICE_ROLE_KEY`에 키 대신 한글 안내 문구가 들어가 Storage 호출이 `UnicodeEncodeError`로 실패했습니다(서버 기동·`/v1/me`는 이 키를 쓰지 않아 정상이라 늦게 드러납니다). ② `SUPABASE_JWT_SECRET`에 서비스 키를 같이 넣었습니다. ES256 프로젝트에서는 비워 둡니다. ③ 마지막 줄 끝에 줄바꿈이 없는 `.env`에 `Add-Content`로 덧붙이면 앞 줄과 붙어 버립니다.

| 이름 | 값을 얻는 곳 |
|---|---|
| `SUPABASE_URL` | `https://<project-ref>.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | 대시보드 **Project Settings → API Keys**. 아래 참고 |
| `SUPABASE_JWT_SECRET` | **JWT Keys** 화면이 레거시 비밀(HS256)이면 그 값. 비대칭 키(ES256/RS256)면 비워도 됨 |
| `DATABASE_URL` | 대시보드 **Connect**의 **Pooler(Supavisor)** 연결 문자열. 아래 참고 |

### 서비스 키
- 대시보드에 **레거시 `service_role` 키**(JWT 형태)와 새 **secret key**(`sb_secret_...` 형태)가 함께 보일 수 있습니다.
- 서버는 Storage 호출에 이 키를 `Authorization`과 `apikey` 헤더 둘 다로 보냅니다. 레거시 `service_role` 키로는 클라우드에서 동작을 확인했습니다. **새 secret key로 이 방식이 동작하는지는 확인하지 못했습니다.** 먼저 레거시 `service_role` 키로 확인하고, 새 키로 바꿀 때는 8절 확인을 다시 하세요.

### 연결 문자열
- **직접 연결**(`db.<project-ref>.supabase.co:5432`)은 IPv6만 지원하는 경우가 있어 집·학교 네트워크에서 안 붙을 수 있습니다. **Pooler 문자열을 쓰세요.** 사용자 이름은 `postgres.<project-ref>` 형태입니다.
- Transaction mode(포트 6543)와 Session mode(포트 5432) 모두 쓸 수 있습니다. 서버는 prepared statement를 끄고 연결해서 transaction mode에서도 동작합니다 (로컬 pooler에서 확인함).
- 비밀번호에 `@`, `:`, `/` 같은 문자가 들어 있으면 URL 인코딩해야 합니다.

### JWT 서명 방식 확인
- **Project Settings → JWT Keys(또는 JWT Settings)**에서 현재 서명 방식을 봅니다.
  - 비대칭 키(ES256/RS256): `SUPABASE_URL`만 있으면 서버가 `https://<project-ref>.supabase.co/auth/v1/.well-known/jwks.json`에서 공개 키를 받습니다. 로컬과 클라우드(ES256)에서 확인한 경로입니다.
  - 레거시 공유 비밀(HS256): `SUPABASE_JWT_SECRET`도 채웁니다. **이 경로는 실제 토큰으로는 아직 확인하지 못했습니다.**
- 어느 쪽인지 모르겠으면 둘 다 채웁니다. 서버가 토큰 헤더의 알고리즘에 맞는 키만 씁니다.

## 7. 서버 실행과 시드

```powershell
cd server
uvicorn app.main:app --no-access-log
```

- 시드 친구는 계정이 먼저 있어야 합니다. **앱(또는 8절의 방법)으로 Google 로그인을 한 번** 해서 계정을 만든 뒤:

```powershell
python -m scripts.seed --email <로그인한 Google 이메일>
```

- **실행 전에 `.env`가 개발용 프로젝트를 가리키는지 확인합니다** (시연용 프로젝트에 시드를 넣지 않습니다).

## 8. 끝에서 끝까지 확인

Flutter 앱이 아직 없어도 확인할 수 있습니다. 순서대로 확인하고 결과를 기록합니다.

| # | 확인 | 기대 결과 | 안 되면 |
|---|---|---|---|
| 1 | Google 계정으로 로그인 (앱, 또는 아래 "앱 없이 로그인하기") | 로그인 성공 | 3.1의 Test users, 4의 Client ID·secret, redirect URI를 확인 |
| 2 | 대시보드 **Authentication → Users** | 방금 로그인한 계정이 있음 | |
| 3 | **Table Editor → profiles** | 같은 사용자 ID의 행이 있고 닉네임이 `그린고블린` | `on_auth_user_created` 트리거를 확인 |
| 4 | `GET /v1/me` (토큰 포함) | 200과 프로필 | 401이면 6절의 JWT 서명 방식과 `SUPABASE_URL`을 확인 |
| 5 | 시드 후 `GET /v1/characters` | 시드 친구 3명과 `art.url` | 503이면 `SUPABASE_SERVICE_ROLE_KEY`와 키 종류(6절)를 확인 |
| 6 | `art.url`을 브라우저에서 열기 | PNG가 보임 | |
| 7 | `DELETE /v1/characters/{id}` | 204. **Storage에서 파일이 사라지고** `assets` 행도 사라짐 | |
| 8 | 다른 Google 계정으로 로그인해 남의 친구 ID로 `GET` | 404 | |
| 9 | 토큰 없이 / 변조한 토큰으로 `GET /v1/me` | 401 | |

### 앱 없이 로그인하기 (Flutter가 아직 없을 때)
- **Authentication → Users**에서 직접 사용자를 만들 수 있지만, 그것은 Google 로그인이 아닙니다 (이메일·비밀번호 계정). 서버·DB·Storage 확인(4~9번)에는 충분합니다.
- **Google 로그인은 브라우저만으로 확인할 수 있습니다** (실제로 해 본 방법). Web 클라이언트(3.2절)와 Supabase 연결(4절)이 끝났다면:
  1. **시크릿 창**에서 `https://<project-ref>.supabase.co/auth/v1/authorize?provider=google`을 엽니다.
  2. Test users에 넣은 계정으로 로그인하고 동의합니다.
  3. 로그인 후 Supabase의 Site URL(기본값 `http://localhost:3000`)로 돌아옵니다. **페이지가 열리지 않고 "사이트에 연결할 수 없음(ERR_CONNECTION_REFUSED)"이 떠도 정상입니다.** 주소창에 `#access_token=…`이 붙어 있으면 로그인에 성공한 것입니다.
  4. 대시보드 **Authentication → Users**와 **Table Editor → profiles**에 행이 생겼는지 봅니다.
- **주소창의 `access_token`과 `refresh_token`은 1시간 동안 내 계정으로 쓸 수 있는 비밀입니다.** 주소 전체를 채팅·PR에 붙이지 말고, 확인이 끝나면 창을 닫습니다.
- 이 토큰으로 서버를 확인하려면 토큰을 명령 기록에 남기지 않도록 `Read-Host`를 씁니다.

```powershell
$u = Read-Host "주소창의 주소 전체를 붙여넣기"
$t = ($u -split 'access_token=')[1].Split('&')[0]
Invoke-RestMethod http://localhost:8000/v1/me -Headers @{ Authorization = "Bearer $t" }
```

### Google 로그인 오류와 원인 (실제로 겪은 것 포함)

| 증상 | 원인 | 해결 |
|---|---|---|
| `400 redirect_uri_mismatch` | ① 클라이언트를 **웹 애플리케이션이 아닌 유형**(예: 데스크톱 앱)으로 만듦 ② 등록한 리디렉션 URI가 Supabase의 Callback URL과 다름 | ① 웹 애플리케이션으로 새로 만들고 Supabase의 Client ID·secret을 바꿉니다 ② Callback URL을 복사 버튼으로 복사해 다시 등록합니다 |
| "액세스 차단됨 / 앱이 테스트 중" | 그 계정이 Test users에 없음 | 3.1절에서 계정을 추가합니다 |
| Test users 저장 시 "활성 상태인 Google 계정과 연결되어 있어야 합니다" | 존재하지 않는 계정 주소 | 실제 Google 계정을 넣습니다 |
| `Unable to exchange external code` | Client ID나 secret 오타 | 4절 값을 다시 붙여 넣고 저장합니다 |
| 설정을 바꿨는데도 같은 오류 | Google 설정 반영 지연, 브라우저가 이전 상태를 기억 | 몇 분 기다린 뒤 **시크릿 창**에서 다시 시도합니다 |
| 오류 화면의 "오류 세부정보"에 주소가 안 나옴 | 이 화면은 `flowName`만 보여 줌 | Supabase의 Callback URL과 Google의 승인된 리디렉션 URI를 직접 비교합니다 |

## 9. 보안 점검

- [ ] `service_role`/secret 키, DB 비밀번호, Google Client secret이 **저장소·PR·채팅에 올라가지 않았다**
- [ ] 앱에는 Supabase 주소와 publishable(anon) 키만 있다
- [ ] 개발용과 시연용 프로젝트가 분리돼 있다
- [ ] Google 동의 화면이 Testing이고, Test users에 시연 계정만 있다 (실제 아동 계정을 넣지 않는다, D-09)
- [ ] 서버 `.env`가 어느 프로젝트를 가리키는지 확인하고 시드를 실행했다

키가 노출됐다면 **대시보드에서 키를 바로 재발급(rotate)** 합니다. 커밋에서 지우는 것만으로는 이미 노출된 것으로 봅니다.

## 10. 끝낸 뒤 알려 줄 것

- 8절 표의 결과 (특히 4번의 JWT 방식, 5번의 키 종류, 7번의 삭제)
- 달랐던 화면 이름·절차: 이 문서를 고칩니다
- 배포 환경이 정해지면 `.env`를 그곳의 비밀 저장소로 옮기는 방법

## 클라우드 검증 결과

| 항목 | 내용 |
|---|---|
| 확인한 날짜 | 2026-10-05 |
| 대상 | 새로 만든 개발용 프로젝트(Free 플랜, Seoul). 프로젝트 ref와 주소는 문서에 쓰지 않는다 |
| 마이그레이션 | 4개 모두 `db push`로 적용. `migration list`에서 원격과 로컬 일치 |
| JWT 서명 방식 | **ES256**(비대칭). `SUPABASE_URL`의 JWKS로 검증됨. `SUPABASE_JWT_SECRET`은 비워 둠 |
| 서비스 키 | **레거시 `service_role` 키**(JWT 형태). 새 `sb_secret_...` 키는 확인하지 않음 |
| 연결 방식 | Supavisor **Transaction mode(6543)** 의 pooler 문자열 |
| 확인 방법 | 이메일 계정 2개(A, B)로 서버(`uvicorn`)에 요청. 키·토큰은 환경변수에만 두고 출력하지 않는 확인용 스크립트로 실행 |

### 8절 표 결과

| # | 확인 | 결과 |
|---|---|---|
| 1 | Google 로그인 | **통과**(Web 클라이언트, 브라우저 방식. 로그인 후 `localhost:3000/#access_token=…`으로 돌아오고 ES256 토큰 발급, 대시보드에서 확인). **iOS 네이티브 로그인은 건너뜀**(앱·iOS 번들 ID가 있어야 함) |
| 2 | Authentication → Users에 계정 있음 | 통과 |
| 3 | `profiles` 자동 생성, 닉네임 `그린고블린` | 통과(대시보드에서 직접 확인) |
| 4 | `GET /v1/me` | 통과(200, ES256) |
| 5 | 시드 후 `GET /v1/characters` | 통과(친구 3명) |
| 6 | `art.url` 열기 | 통과(200, `image/png`, PNG 시그니처) |
| 7 | 삭제 | 통과(204, 재조회 404, `assets` 행 9→6, 옛 서명 URL이 열리지 않음, 대시보드 Storage에서 파일 감소 확인) |
| 8 | 다른 계정으로 남의 친구 `GET`·`status`·`DELETE` | 통과(모두 404, A의 친구는 그대로) |
| 9 | 토큰 없음·변조 | 통과(둘 다 401) |
| - | `PATCH /v1/me` | 통과 |
| - | 세 테이블 RLS, `on_auth_user_created`, 비공개 버킷 | 통과(대시보드에서 직접 확인) |

### 확인하지 못한 것
- **iOS 클라이언트와 아이패드 앱의 네이티브 로그인**(`google_sign_in` + `signInWithIdToken`), `Skip nonce check`의 효과, 5절 전체
- Google 로그인으로 받은 토큰으로 서버 `GET /v1/me` 호출 (서버는 이메일 계정 토큰으로만 확인했다. 같은 ES256 토큰 방식이라 같은 경로이지만 Google 토큰으로 직접 호출한 기록은 없다)
- 새 `sb_secret_...` 서비스 키
- 레거시 HS256 토큰(이 프로젝트는 ES256)
- 미사용 에셋 정리 작업(`cleanup`)의 클라우드 동작
- Transaction mode 외의 Session mode(5432)

### 안내서와 달랐던 점
- `supabase link`가 DB 비밀번호를 묻지 않았다(2절에 반영).
- `.env` 위치와 실수 사례를 6절에 적었다. 서비스 키 대신 다른 값이 들어가도 서버 기동과 `/v1/me`는 정상이라 시드나 Storage를 쓸 때에야 드러난다.
- Google 로그인 설정에서 겪은 것을 3.1·3.2·8절에 반영했다: Test users에는 실제 계정만 들어간다, 클라이언트 유형은 반드시 웹 애플리케이션이어야 한다(데스크톱 앱으로 만들어 `redirect_uri_mismatch`가 났다), 로그인 성공 후 `localhost:3000` 연결 오류는 정상이다, 클라이언트 secret은 상세 화면에서 나중에도 복사할 수 있다.
- Windows PowerShell 5.1의 `Invoke-WebRequest`는 charset이 없는 JSON을 UTF-8로 읽지 못해 한글이 깨져 보인다. 서버 오류가 아니라 확인 스크립트 쪽 문제였고, 응답을 UTF-8로 직접 해석하면 해결된다.
