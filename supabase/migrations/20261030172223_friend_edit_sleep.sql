-- 사용자 결정: 앱의 친구 편집과 개별 수면 일정을 서버에도 보존한다.
alter table public.friends
    add column personality text check (char_length(personality) <= 120),
    add column bedtime integer not null default 1260 check (bedtime between 0 and 1439),
    add column wake_time integer not null default 420 check (wake_time between 0 and 1439);
-- Flutter의 글자 수는 grapheme 기준이다. API가 70자를 검사하고 DB는 느슨한 상한만 둔다.
alter table public.friends drop constraint friends_introduction_check;
alter table public.friends add constraint friends_introduction_check
    check (char_length(introduction) <= 2048);
-- 기존 소유권 RLS와 updated_at 트리거를 그대로 사용한다.
