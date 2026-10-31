-- 얼굴 분석을 그림 생성 성공 뒤에 따로 진행한다. 아이는 얼굴 분석을 기다리지 않고
-- 다음 화면으로 넘어가고, 분석 결과는 생성 작업과 이미 저장된 친구에 나중에 채운다.
--   pending     : 그림은 성공했고 얼굴 분석이 진행 중이다 (face는 null)
--   ready       : 얼굴 좌표가 face에 저장됐다
--   unavailable : 분석 실패·시간 초과·생략·서버 재시작으로 얼굴 좌표가 없다 (face는 null)
alter table public.generation_jobs
  add column face_status text
    check (face_status in ('pending', 'ready', 'unavailable'));

-- 이미 성공한 작업은 저장된 face로 상태를 정한다.
update public.generation_jobs
  set face_status = case when face is null then 'unavailable' else 'ready' end
  where status = 'succeeded';

-- 값이 없는 성공 작업(진단 스크립트·시드가 직접 넣은 행)은 API가 face로 상태를 계산한다.
alter table public.generation_jobs
  add constraint generation_jobs_face_status_result_check
  check (
    face_status is null
    or (status = 'succeeded' and (face_status = 'ready') = (face is not null))
  );
