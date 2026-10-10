-- FR-10.6: 생성 작업의 검증된 얼굴 좌표를 친구 저장 전까지 보관한다.
alter table public.generation_jobs
  add column face jsonb;

alter table public.generation_jobs
  add constraint generation_jobs_face_object_check
  check (
    face is null
    or (
      jsonb_typeof(face) = 'object'
      and face ->> 'version' = '1'
    )
  );
