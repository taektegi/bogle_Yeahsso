# 대상 선택 입력 연동

프론트 release / 개인 백엔드 main. 입력별 API 경로는 모두 POST /v1/generations로 같고, 서버가 sourceType와 photoMode로 프롬프트를 선택한다.

- 스케치북 → drawing / original.
- 카메라·사진 선택 → photo / original.
- 애플 Vision 대상 분리 결과 채택 → photo / subject.
- 회전·자르기·밝기 보정 → 현재 분리 여부 유지.
- 종이 원근 보정·촬영 원본 복원·새 사진 → photo / original.
- 취소·실패 → 현재 이미지와 현재 분리 여부 유지.

PreparedPhoto로 픽셀과 명시적 분리 여부를 전달하고, GenerationInput.photoMode가 요청·멱등 키·미완료 작업 기록에 반영된다. 앱 재시작 후 이어 만들기에서도 해당 조건이 유지된다. 서버에는 새 조건을 DB에 보관하는 20261031000500_generation_photo_mode.sql이 필요하다. API 계약 스냅샷을 최신 서버와 맞췄다. 배포는 DB 마이그레이션 → 서버 → 새 앱 순서다.

BOGLE_API_URL이 없으면 로컬 모드다. 원격 모드에서는 AppServices.remote의 같은 ApiClient가 인증·업로드·생성·폴링을 처리한다. 프론트가 AI 제공자에 직접 호출하거나 입력마다 서버 주소를 선택하는 구조가 아니다. AI 키는 서버에만 둔다.

검증: Flutter 전체 642개 통과, 조건부 3개 건너뜀. 실제 화면에서 대상 선택/종이 보정 → 스튜디오 → 생성 조건 전달, 원본 복원, 동일 픽셀의 모드별 요청 키 구분, 앱 재시작 후 모드·키 유지 검증. 백엔드 실제 임시 PostgreSQL 테스트 479개 통과. 실 AI 생성 품질·실제 응답 속도는 키 연결 후 검수 대상이다.
