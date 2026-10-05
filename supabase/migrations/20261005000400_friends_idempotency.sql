-- 친구 생성 요청의 멱등 키 (담당 A). 설계: docs/idempotency-design.md
--
-- `POST /v1/characters`는 `Idempotency-Key`로 중복 요청을 막는다. 키는 만들어진 친구 행에 함께
-- 저장한다. 같은 사용자가 같은 키로 다시 요청하면 새 친구를 만들지 않고 이미 만든 친구를 돌려주고,
-- 요청 내용(지문)이 다르면 409로 거절한다.
--
-- 시드 친구나 이 마이그레이션 이전에 만든 친구는 키가 없다(null). null은 서로 충돌하지 않는다.

alter table public.friends
  add column idempotency_key text,
  add column request_fingerprint text;

alter table public.friends
  -- 키와 지문은 함께 있거나 함께 없어야 한다.
  add constraint friends_idempotency_check
    check ((idempotency_key is null) = (request_fingerprint is null)),
  -- 키 형식은 API 계약과 같다: 8–64자 영문·숫자·'-'·'_'
  add constraint friends_idempotency_key_format_check
    check (idempotency_key is null or idempotency_key ~ '^[A-Za-z0-9_-]{8,64}$'),
  -- 같은 사용자의 같은 키는 친구 하나뿐이다. 다른 사용자의 같은 키는 서로 무관하다.
  add constraint friends_user_id_idempotency_key_key unique (user_id, idempotency_key);
