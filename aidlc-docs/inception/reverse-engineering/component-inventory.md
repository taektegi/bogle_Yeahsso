# Component Inventory

## Application Packages
- `bogle_app` (Flutter, 연관 저장소 `Frontend/Bogle_doll_making_app`) - 보글 iPad 앱. 모든 사용자 흐름의 UI와 프로토타입 규칙, 메모리 저장소
- `motion_server` (Python/FastAPI, 같은 저장소 하위) - 그림 → 움직임 GIF 선택형 서비스

## Infrastructure Packages
- `supabase` (현재 워크스페이스) - Supabase CLI 마이그레이션 - "오늘의 필름" DB 스키마·RLS·Storage 버킷. 보글 도메인 아님
- IaC(CDK/Terraform/CloudFormation): 없음

## Shared Packages
- 없음. 앱과 서버가 공유하는 계약(OpenAPI, DTO 패키지, 공용 스키마)이 없다. 모션 API 계약은 `motion_service.dart`와 `app.py`에 각각 손으로 맞춰져 있다.

## Test Packages
- `test/`, `integration_test/` (Flutter, 연관 저장소) - Unit/Widget/Integration - 43개 파일. UI와 메모리 mock 동작 검증(로딩·설정·보관함·집·주문·프로필·모션 클라이언트 등)
- 백엔드 워크스페이스: 테스트 없음 (RLS·마이그레이션 검증 없음)
- 모션 서버: 테스트 없음

## Total Count
- **Total Packages**: 4
- **Application**: 2 (`bogle_app`, `motion_server`)
- **Infrastructure**: 1 (`supabase`)
- **Shared**: 0
- **Test**: 1 (`bogle_app`의 test/integration_test)
