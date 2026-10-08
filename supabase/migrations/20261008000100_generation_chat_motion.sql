-- 친구 만들기·대화·모션 (junsang 브랜치)
--
-- 이 마이그레이션이 만드는 것
--   generation_jobs : 아이 그림 → 캐릭터 그림 생성 작업 (FR-04)
--   chat_messages   : 친구의 집 대화 기록 (FR-09)
--   motion_jobs     : 친구 그림의 모션 클립 작업 (FR-10)
-- 그리고 friends에 앱이 쓰는 값을 더한다.
--   personality     : 성격을 아이가 직접 적거나 말한 문장 (앱의 자유 입력)
--   bedtime_minute, wake_minute : 친구마다 다른 잠자는 시간 (앱의 수면 시간 편집)
--   face            : 얼굴 지도 (눈·입·볼·머리, 보는 방향). 앱이 얼굴을 움직이고 간식을 입에 댄다.
--   updated 가능    : 이름·성격·소개·말투·수면 시간은 앱의 수정 화면에서 바뀐다.

-- ---------------------------------------------------------------------------
-- generation_jobs
-- ---------------------------------------------------------------------------

create table public.generation_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,

  source_asset_id uuid not null,
  -- drawing: 그림판 PNG / photo: 종이에 그린 그림을 찍은 사진
  source_type text not null,
  status text not null default 'queued',

  -- 성공 결과 (status = 'succeeded'일 때만 채운다)
  art_asset_id uuid,
  thumbnail_asset_id uuid,
  accent_argb bigint,
  face jsonb,

  -- 실패 사유 (status = 'failed'일 때만). code는 API 계약 3.3절의 generation_* 코드다.
  error_code text,
  error_retryable boolean,

  -- 처리 횟수 (서버가 재시작돼 다시 처리하면 늘어난다)와 시각
  attempts integer not null default 0,
  started_at timestamptz,
  finished_at timestamptz,

  -- 멱등 키 (docs/idempotency-design.md)
  idempotency_key text not null,
  request_fingerprint text not null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint generation_jobs_user_id_id_key unique (user_id, id),
  constraint generation_jobs_user_id_idempotency_key_key unique (user_id, idempotency_key),
  constraint generation_jobs_idempotency_key_format_check
    check (idempotency_key ~ '^[A-Za-z0-9_-]{8,64}$'),
  constraint generation_jobs_source_type_check check (source_type in ('drawing', 'photo')),
  constraint generation_jobs_status_check
    check (status in ('queued', 'processing', 'succeeded', 'failed', 'cancelled')),
  constraint generation_jobs_error_code_check
    check (
      error_code is null or error_code in (
        'generation_rejected', 'invalid_source_image', 'generation_timeout',
        'generation_unavailable'
      )
    ),
  constraint generation_jobs_result_check
    check (
      status <> 'succeeded'
      or (art_asset_id is not null and thumbnail_asset_id is not null and accent_argb is not null)
    ),
  constraint generation_jobs_failure_check
    check (status <> 'failed' or (error_code is not null and error_retryable is not null)),
  constraint generation_jobs_accent_argb_check
    check (accent_argb is null or accent_argb between 0 and 4294967295),
  -- 남의 에셋은 가리킬 수 없다. 원본이 지워지면(친구 삭제·정리) 그 작업도 함께 지운다.
  constraint generation_jobs_source_asset_fkey
    foreign key (user_id, source_asset_id) references public.assets (user_id, id)
    on delete cascade,
  constraint generation_jobs_art_asset_fkey
    foreign key (user_id, art_asset_id) references public.assets (user_id, id)
    on delete set null (art_asset_id),
  constraint generation_jobs_thumbnail_asset_fkey
    foreign key (user_id, thumbnail_asset_id) references public.assets (user_id, id)
    on delete set null (thumbnail_asset_id)
);

-- 처리기가 기다리는 작업을 오래된 순으로 찾는다.
create index generation_jobs_waiting_idx
  on public.generation_jobs (created_at)
  where status in ('queued', 'processing');

create index generation_jobs_created_at_idx on public.generation_jobs (created_at);

create trigger set_generation_jobs_updated_at
  before update on public.generation_jobs
  for each row execute function public.set_updated_at();

-- 친구는 자기가 태어난 작업을 가리킨다. 작업은 24시간 뒤 정리되므로 그때 null이 된다.
alter table public.friends
  add constraint friends_generation_job_fkey
    foreign key (generation_job_id) references public.generation_jobs (id)
    on delete set null;

-- ---------------------------------------------------------------------------
-- friends: 앱이 쓰는 값
-- ---------------------------------------------------------------------------

alter table public.friends
  add column personality text not null default '',
  add column bedtime_minute smallint not null default 1320,
  add column wake_minute smallint not null default 360,
  add column face jsonb;

alter table public.friends
  add constraint friends_personality_check check (char_length(personality) <= 60),
  add constraint friends_bedtime_minute_check check (bedtime_minute between 0 and 1439),
  add constraint friends_wake_minute_check check (wake_minute between 0 and 1439);

-- ---------------------------------------------------------------------------
-- chat_messages
-- ---------------------------------------------------------------------------

create table public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  character_id uuid not null,
  -- 아이가 보낸 메시지와 그에 대한 친구의 답은 같은 client_message_id를 공유한다.
  client_message_id text not null,
  role text not null,
  text text not null,
  -- assistant만: ai(생성형) | script(스크립트 대사로 대체)
  source text,
  request_fingerprint text not null,
  created_at timestamptz not null default now(),

  constraint chat_messages_character_fkey
    foreign key (user_id, character_id) references public.friends (user_id, id)
    on delete cascade,
  constraint chat_messages_role_check check (role in ('user', 'assistant')),
  constraint chat_messages_source_check
    check ((role = 'assistant') = (source is not null) and (source is null or source in ('ai', 'script'))),
  constraint chat_messages_text_check check (char_length(text) between 1 and 400),
  constraint chat_messages_client_message_id_format_check
    check (client_message_id ~ '^[A-Za-z0-9_-]{8,64}$'),
  constraint chat_messages_character_id_client_message_id_role_key
    unique (character_id, client_message_id, role)
);

create index chat_messages_character_created_idx
  on public.chat_messages (character_id, created_at desc, id desc);

-- ---------------------------------------------------------------------------
-- motion_jobs: 친구마다 하나
-- ---------------------------------------------------------------------------

create table public.motion_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  character_id uuid not null,
  -- queued | working | ready | unsupported | failed (앱 저장소 motion_server와 같은 값)
  status text not null default 'queued',
  -- unsupported의 이유: not_humanoid | background | no_figure | disabled
  reason text,
  -- 모션 서버의 작업 ID
  remote_id text,
  attempts integer not null default 0,
  -- {"jump": {"assetId": "...", "box": [l, t, r, b]}, ...}
  clips jsonb not null default '{}'::jsonb,
  -- clips가 쓰는 에셋 (정리 작업이 지우지 않도록)
  asset_ids uuid[] not null default '{}',
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint motion_jobs_character_fkey
    foreign key (user_id, character_id) references public.friends (user_id, id)
    on delete cascade,
  constraint motion_jobs_character_id_key unique (character_id),
  constraint motion_jobs_status_check
    check (status in ('queued', 'working', 'ready', 'unsupported', 'failed'))
);

create index motion_jobs_waiting_idx
  on public.motion_jobs (created_at)
  where status in ('queued', 'working');

create trigger set_motion_jobs_updated_at
  before update on public.motion_jobs
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- RLS와 권한: 앱은 내 것만 읽고, 쓰기는 서버(service_role)만 한다.
-- ---------------------------------------------------------------------------

alter table public.generation_jobs enable row level security;
alter table public.chat_messages enable row level security;
alter table public.motion_jobs enable row level security;

revoke all on public.generation_jobs, public.chat_messages, public.motion_jobs
  from anon, authenticated;
grant select on public.generation_jobs, public.chat_messages, public.motion_jobs
  to authenticated;

create policy generation_jobs_select_own
  on public.generation_jobs for select to authenticated
  using ((select auth.uid()) = user_id);

create policy chat_messages_select_own
  on public.chat_messages for select to authenticated
  using ((select auth.uid()) = user_id);

create policy motion_jobs_select_own
  on public.motion_jobs for select to authenticated
  using ((select auth.uid()) = user_id);
