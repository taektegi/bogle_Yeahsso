# Technology Stack

## Programming Languages
- SQL (PostgreSQL 방언, PL/pgSQL) - 버전 명시 없음 - 백엔드 워크스페이스 마이그레이션
- Dart - SDK `^3.11.3` - Flutter 앱
- Python - 버전 명시 없음 - 모션 서버

## Frameworks
- Supabase (Postgres, Auth, Storage, PostgREST) - 버전 명시 없음 - 백엔드 워크스페이스. 현재 보글 백엔드용으로 사용된 적 없음
- Flutter - Dart SDK `^3.11.3`에 대응 - iPad 앱 (iOS 15 이상, 가로 화면 — PRD 기준)
- FastAPI `0.115.6` - 모션 HTTP API
- uvicorn `0.32.1` - 모션 서버 ASGI 실행
- TorchServe - 버전은 `torchserve.properties`/`setup.sh`에 따름 - 모션 파이프라인 모델 서빙(로컬)

## Infrastructure
- Supabase Postgres - "오늘의 필름" 테이블 5개
- Supabase Storage - 비공개 버킷 `film-media`, 경로 `{user_id}/{film_id}/{category}/{file_name}`
- Supabase Auth - `auth.users` 기반 프로필 자동 생성
- 모션 서버 로컬 파일 시스템 - `motion_server/data/jobs/<id>/`
- 클라우드 계정·리전·배포 환경: 정의 없음

## Build Tools
- Supabase CLI - 버전 명시 없음 - `supabase start`, `db reset`, `db push`
- Flutter / pub - 앱 빌드
- pip - 모션 서버 의존성

## Testing Tools
- `flutter_test`, `integration_test` (Flutter SDK 포함) - 앱 위젯·통합 테스트
- `flutter_lints ^6.0.0` - 앱 정적 분석
- 백엔드·모션 서버: 테스트 도구 없음 (pgTAP, pytest 등 미도입)
