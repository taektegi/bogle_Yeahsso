-- 보글 공통 뼈대 스키마 (담당 A)
--
-- 이 마이그레이션이 만드는 것: profiles, friends, 비공개 Storage bucket.
-- 업로드·생성 작업(B), 대화·모션(C) 테이블은 각 담당이 새 마이그레이션으로 추가한다.
--
-- 쓰기 원칙: 앱은 DB에 직접 쓰지 않는다. 모든 쓰기는 FastAPI 서버(service_role)가 한다.
-- 그래서 authenticated 역할에는 읽기(select) 권한과 "내 것만" 정책만 준다.

-- ---------------------------------------------------------------------------
-- 공통 트리거 함수
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- friends: 사용자가 만든 캐릭터 친구 (FR-05, FR-06)
-- ---------------------------------------------------------------------------
-- 친구 설정(이름·성격 유형·좋아하는 것·말투)은 저장 후 바뀌지 않는다 (D-24).
-- introduction만 저장 직후 AI가 채우므로 한 번 갱신될 수 있다 (FR-05.4).

create table public.friends (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,

  name text not null,
  -- 성격 유형 목록은 기획에서 정한다 (OI-01). 목록이 확정되기 전까지 값은 서버가 검증한다.
  personality_type text not null,
  favorite_things text[] not null,
  speech_style text not null,
  -- 소개 문구는 최대 70자. 생성에 실패하면 빈 문자열로 두고 앱이 기본 문구를 보여 준다.
  introduction text not null default '',

  -- 비공개 bucket(bogle-media) 안의 객체 경로. 항상 '{user_id}/'로 시작한다.
  source_path text,
  art_path text not null,
  thumbnail_path text not null,
  -- 캐릭터 대표색 ARGB (예: 0xFF8A6FD1). 부호 없는 32비트라서 bigint를 쓴다.
  accent_argb bigint not null,

  -- 친구 생성 작업 ID. 작업 하나로는 친구 하나만 만들 수 있다 (FR-05.2, FR-05.6).
  -- 작업 테이블은 담당 B가 만들고, 그때 외래 키를 추가한다.
  generation_job_id uuid unique,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- profiles.avatar_friend_id가 "내 친구"만 가리키도록 하는 복합 외래 키용
  constraint friends_user_id_id_key unique (user_id, id),

  -- 이름 1–12자는 사용자에게 보이는 글자(grapheme) 기준이라 API가 검사한다 (FR-05.1).
  -- DB는 코드 포인트 수로 느슨한 상한만 둔다.
  constraint friends_name_check
    check (char_length(btrim(name)) >= 1 and char_length(name) <= 48),
  constraint friends_personality_type_check
    check (char_length(btrim(personality_type)) >= 1),
  constraint friends_favorite_things_check
    check (cardinality(favorite_things) >= 1),
  constraint friends_speech_style_check
    check (speech_style in ('~지요!', '해요체', '반말')),
  constraint friends_introduction_check
    check (char_length(introduction) <= 70),
  constraint friends_accent_argb_check
    check (accent_argb between 0 and 4294967295),
  constraint friends_source_path_owner_check
    check (source_path is null or starts_with(source_path, user_id::text || '/')),
  constraint friends_art_path_owner_check
    check (starts_with(art_path, user_id::text || '/')),
  constraint friends_thumbnail_path_owner_check
    check (starts_with(thumbnail_path, user_id::text || '/'))
);

-- 보관함 목록: 내 친구를 최신순으로 (FR-06.1, OI-07 기본값)
create index friends_user_id_created_at_idx
  on public.friends (user_id, created_at desc);

create trigger set_friends_updated_at
  before update on public.friends
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- profiles: auth.users와 1:1인 아이 프로필 (FR-02)
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  -- 공백을 제거한 값을 저장한다. 1–12자 (FR-02.1)
  nickname text not null default '그린고블린',
  -- null이면 기본 아바타. 내 친구 중 하나만 지정할 수 있다 (FR-02.2).
  avatar_friend_id uuid,
  -- 알림 설정값만 저장한다. 실제 푸시는 보내지 않는다 (FR-02.3).
  friend_notifications boolean not null default true,
  order_notifications boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint profiles_nickname_check
    check (nickname = btrim(nickname) and char_length(nickname) between 1 and 12),
  -- (id, avatar_friend_id)가 friends(user_id, id)와 일치해야 하므로 남의 친구는 지정할 수 없다.
  -- 지정한 친구가 삭제되면 avatar_friend_id만 null(기본 아바타)로 돌아간다.
  constraint profiles_avatar_friend_fkey
    foreign key (id, avatar_friend_id)
    references public.friends (user_id, id)
    on delete set null (avatar_friend_id)
);

create trigger set_profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- 처음 로그인(auth.users 생성)하면 프로필을 자동으로 만든다 (FR-01.1).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- RLS와 권한 (FR-01.4)
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.friends enable row level security;

-- 앱(authenticated)은 읽기만 한다. 쓰기는 service_role을 쓰는 FastAPI 서버만 한다.
revoke all on public.profiles, public.friends from anon, authenticated;
grant select on public.profiles, public.friends to authenticated;

create policy profiles_select_own
  on public.profiles for select to authenticated
  using ((select auth.uid()) = id);

create policy friends_select_own
  on public.friends for select to authenticated
  using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- Storage: 비공개 bucket (FR-01.5, FR-03.4)
-- ---------------------------------------------------------------------------
-- 객체 경로는 '{user_id}/...'로 시작한다. 앱에는 서버가 만든 만료되는 서명 URL로만 준다.
-- 업로드·삭제는 서버(service_role)가 Storage API로 한다. authenticated에는 쓰기 정책을 만들지 않는다.

insert into storage.buckets (id, name, public)
values ('bogle-media', 'bogle-media', false)
on conflict (id) do nothing;

create policy bogle_media_select_own
  on storage.objects for select to authenticated
  using (
    bucket_id = 'bogle-media'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
