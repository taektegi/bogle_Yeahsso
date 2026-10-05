# 클라우드 Supabase와 Google 로그인 설정 안내

| 항목 | 내용 |
|---|---|
| 작성일 | 2026-10-05 |
| 대상 | 담당 A(권희준). 클라우드 프로젝트와 Google OAuth를 처음 만드는 사람 |
| 목적 | 개발용 클라우드 Supabase 프로젝트를 만들고, Google 로그인으로 서버(`/v1/me`)까지 한 번에 확인한다 |
| 근거 | `requirements.md` FR-01, NFR-03, NFR-11. 로컬 Supabase 검증 결과는 `supabase/README.md`와 PR #10 |

> **주의**: 아래 화면 이름과 메뉴 위치는 2026-10 기준으로 아는 구조입니다. Supabase·Google Cloud 콘솔은 자주 바뀌므로 이름이 조금 다르면 비슷한 항목을 찾으세요. 작성 당시 Supabase 공식 문서를 직접 열어 보지 못했습니다. 막히면 [Supabase의 Google 로그인 문서](https://supabase.com/docs/guides/auth/social-login/auth-google)를 확인하세요.
>
> 이 안내서는 **실제로 따라 해 본 것이 아닙니다.** 끝까지 해 본 뒤 달랐던 부분은 이 문서에 고쳐 주세요.

## 0. 먼저 알아 둘 것

| 질문 | 답 |
|---|---|
| 팀원도 클라우드 프로젝트가 필요한가? | **아니요.** 각자 로컬 Supabase(`server/README.md`의 "로컬 Supabase로 서버 확인하기")로 개발합니다. 클라우드는 Google 로그인 확인, 앱 연동, 시연용입니다 |
| 프로젝트는 몇 개? | **개발용 1개를 먼저** 만듭니다. 시연용은 따로 만들어 분리합니다 (NFR-11). 시연용 프로젝트는 시연이 가까워지면 만듭니다 |
| 비용 | 무료(Free) 플랜으로 시작할 수 있습니다. **무료 프로젝트는 일정 기간(약 1주) 활동이 없으면 일시 중지될 수 있으니** 시연 전에 상태를 확인하세요 |
| 클라우드 키는 누가 가지나? | 서버를 띄우는 사람(지금은 권희준)과 배포 환경만. 팀원에게 `service_role` 키를 나눠 주지 않습니다 |

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
supabase link --project-ref <project-ref>     # DB 비밀번호를 물어봅니다
supabase db push                              # supabase/migrations/*.sql 적용
```

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
3. 범위(scope)는 기본인 `openid`, `email`, `profile`이면 충분합니다. 민감한 범위를 추가하지 않습니다.

> Testing 상태에서는 로그인 유지(리프레시 토큰)가 약 7일 뒤 끊길 수 있습니다. 시연 직전에 다시 로그인해 두세요.

### 3.2 클라이언트 ID 만들기
**Clients(사용자 인증 정보) → Create client**에서 만듭니다.

| 종류 | 언제 필요한가 | 입력값 |
|---|---|---|
| **Web application** | **항상 필요.** Supabase에 등록하는 ID이고, 앱이 `serverClientId`로 씁니다 | Authorized redirect URI: `https://<project-ref>.supabase.co/auth/v1/callback` |
| Android | Android 앱에서 네이티브 로그인할 때 | 패키지 이름 + 디버그/릴리스 **SHA-1 지문** |
| iOS | iOS 앱에서 네이티브 로그인할 때 | 번들 ID |

- Web application의 **Client ID와 Client secret**을 안전한 곳에 저장합니다. secret은 Supabase에만 넣고 앱·저장소에는 넣지 않습니다.
- 앱 플랫폼(Android/iOS)은 프론트 개발자에게 확인한 뒤 필요한 것만 만듭니다. 시연 기기가 한 종류라면 그 종류만 만듭니다.

## 4. Supabase에 Google 연결하기

대시보드 **Authentication → Sign In / Providers(또는 Providers) → Google**:

1. **Enable Sign in with Google**을 켭니다.
2. **Client IDs**: Web application의 Client ID를 넣습니다. 네이티브 로그인을 쓰면 Android·iOS의 Client ID도 **쉼표로 구분해서 함께** 넣습니다.
3. **Client Secret**: Web application의 secret을 넣습니다.
4. iOS에서 네이티브 로그인을 쓰면 **Skip nonce check**를 켭니다.
5. **Authentication → URL Configuration**
   - 앱이 브라우저를 거치는 OAuth 방식을 쓰면 앱의 **딥링크 주소**를 Redirect URLs에 추가합니다 (예: `io.supabase.bogle://login-callback`). 네이티브 로그인(`signInWithIdToken`)만 쓰면 필요 없습니다
   - Site URL은 앱이 쓰지 않으면 기본값으로 둡니다

## 5. 앱에서 로그인하는 방법 (Flutter, 참고)

앱 연동은 FR-11.1입니다. 구현할 사람이 정해지면 아래를 따릅니다. **두 방식 중 하나를 고릅니다.**

| 방식 | 설명 | 추천 |
|---|---|---|
| **네이티브 로그인** | `google_sign_in`으로 Google 계정을 고르고, 받은 ID 토큰을 `supabase.auth.signInWithIdToken`에 넘김 | 모바일에서 화면이 자연스러움. **추천** |
| 브라우저 OAuth | `supabase.auth.signInWithOAuth(OAuthProvider.google)` + 딥링크 | 설정이 적지만 브라우저가 한 번 열림 |

```dart
// 네이티브 로그인 스케치 (supabase_flutter, google_sign_in)
final googleSignIn = GoogleSignIn(
  serverClientId: '<Web application Client ID>',
  clientId: '<iOS Client ID>', // iOS만
);
final account = await googleSignIn.signIn();
final auth = await account!.authentication;
await Supabase.instance.client.auth.signInWithIdToken(
  provider: OAuthProvider.google,
  idToken: auth.idToken!,
  accessToken: auth.accessToken,
);
```

- 앱에는 **Supabase 주소와 publishable(anon) 키만** 넣습니다. `service_role` 키와 Google secret은 넣지 않습니다 (NFR-03).
- 서버 호출에는 `Authorization: Bearer <session.accessToken>`을 붙입니다. 401이 오면 SDK로 토큰을 갱신하고 한 번만 다시 요청합니다 (API 계약 v1 2절).

## 6. 서버에 클라우드 값 넣기

`server/.env`를 채웁니다. **이 파일은 커밋하지 않습니다.**

| 이름 | 값을 얻는 곳 |
|---|---|
| `SUPABASE_URL` | `https://<project-ref>.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | 대시보드 **Project Settings → API Keys**. 아래 참고 |
| `SUPABASE_JWT_SECRET` | **JWT Keys** 화면이 레거시 비밀(HS256)이면 그 값. 비대칭 키(ES256/RS256)면 비워도 됨 |
| `DATABASE_URL` | 대시보드 **Connect**의 **Pooler(Supavisor)** 연결 문자열. 아래 참고 |

### 서비스 키
- 대시보드에 **레거시 `service_role` 키**(JWT 형태)와 새 **secret key**(`sb_secret_...` 형태)가 함께 보일 수 있습니다.
- 서버는 Storage 호출에 이 키를 `Authorization`과 `apikey` 헤더 둘 다로 보냅니다. **새 secret key로 이 방식이 동작하는지는 확인하지 못했습니다.** 먼저 레거시 `service_role` 키로 확인하고, 새 키로 바꿀 때는 8절 확인을 다시 하세요.

### 연결 문자열
- **직접 연결**(`db.<project-ref>.supabase.co:5432`)은 IPv6만 지원하는 경우가 있어 집·학교 네트워크에서 안 붙을 수 있습니다. **Pooler 문자열을 쓰세요.** 사용자 이름은 `postgres.<project-ref>` 형태입니다.
- Transaction mode(포트 6543)와 Session mode(포트 5432) 모두 쓸 수 있습니다. 서버는 prepared statement를 끄고 연결해서 transaction mode에서도 동작합니다 (로컬 pooler에서 확인함).
- 비밀번호에 `@`, `:`, `/` 같은 문자가 들어 있으면 URL 인코딩해야 합니다.

### JWT 서명 방식 확인
- **Project Settings → JWT Keys(또는 JWT Settings)**에서 현재 서명 방식을 봅니다.
  - 비대칭 키(ES256/RS256): `SUPABASE_URL`만 있으면 서버가 `https://<project-ref>.supabase.co/auth/v1/.well-known/jwks.json`에서 공개 키를 받습니다. 로컬에서 확인한 경로입니다.
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
- 진짜 Google 로그인(1번)은 앱 또는 **브라우저 OAuth** 테스트로만 볼 수 있습니다. 가장 간단한 방법은 임시 Flutter 화면이나 작은 웹 페이지(supabase-js)에서 `signInWithOAuth`를 호출해 로그인한 뒤 액세스 토큰을 복사하는 것입니다. 이 경우 3.2의 Web client redirect URI와 4의 Redirect URLs에 그 페이지 주소를 추가해야 합니다.

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
