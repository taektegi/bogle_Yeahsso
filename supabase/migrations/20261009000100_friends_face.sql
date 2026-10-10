-- 생성된 PNG의 얼굴 좌표 지도. 분석 실패는 친구 생성 실패가 아니므로 null을 허용한다.
-- 좌표의 상세 범위·유한 수치·PNG 크기 일치는 FastAPI가 저장 전에 검증한다.

alter table public.friends
  add column face jsonb;

alter table public.friends
  add constraint friends_face_object_check
  check (
    face is null
    or (
      jsonb_typeof(face) = 'object'
      and face ->> 'version' = '1'
    )
  );
