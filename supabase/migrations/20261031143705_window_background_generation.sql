-- 캐릭터 아트를 참조한 낮 배경 한 장. 생성 직후 예약하고 저장한 친구에 연결한다.
alter table public.assets drop constraint assets_kind_check;
alter table public.assets add constraint assets_kind_check
  check (kind in ('source','art','thumbnail','motion','background'));

create table public.window_view_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  character_id uuid,
  generation_job_id uuid,
  source_asset_id uuid not null,
  status text not null default 'queued'
    check (status in ('queued','processing','succeeded','failed','cancelled')),
  idempotency_key text not null check (idempotency_key ~ '^[A-Za-z0-9_-]{8,64}$'),
  request_fingerprint text not null,
  model text not null,
  prompt_version text not null,
  day_asset_id uuid,
  night_asset_id uuid,
  error_code text,
  error_message text,
  error_retryable boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  worker_owner uuid,
  unique (user_id,id),
  unique (user_id,idempotency_key),
  foreign key (user_id,character_id) references public.friends(user_id,id) on delete cascade,
  foreign key (user_id,source_asset_id) references public.assets(user_id,id),
  foreign key (user_id,day_asset_id) references public.assets(user_id,id),
  foreign key (user_id,night_asset_id) references public.assets(user_id,id),
  check (status <> 'succeeded' or day_asset_id is not null),
  check (status <> 'failed' or (error_code is not null and error_message is not null))
);
create unique index window_view_active_character on public.window_view_jobs(character_id)
  where status in ('queued','processing');
create index window_view_user_character on public.window_view_jobs(user_id,character_id,created_at);
create index window_view_queue on public.window_view_jobs(created_at,id) where status='queued';
create trigger set_window_view_updated_at before update on public.window_view_jobs
  for each row execute function public.set_updated_at();
alter table public.window_view_jobs enable row level security;
revoke all on public.window_view_jobs from anon,authenticated;
grant select on public.window_view_jobs to authenticated;
grant all on public.window_view_jobs to service_role;
create policy window_view_select_own on public.window_view_jobs for select to authenticated
  using ((select auth.uid())=user_id);

create table public.window_worker_lease (
  id integer primary key check (id=1),
  owner uuid not null,
  expires_at timestamptz not null
);
alter table public.window_worker_lease enable row level security;
revoke all on public.window_worker_lease from anon,authenticated;
grant all on public.window_worker_lease to service_role;

-- 다른 멱등 키의 중복 탭도 같은 작업을 가리키되, 그 요청 키의 지문도 보존한다.
create table public.window_view_requests (
  user_id uuid not null references auth.users(id) on delete cascade,
  idempotency_key text not null check (idempotency_key ~ '^[A-Za-z0-9_-]{8,64}$'),
  request_fingerprint text not null,
  job_id uuid not null,
  primary key (user_id,idempotency_key),
  foreign key (user_id,job_id) references public.window_view_jobs(user_id,id) on delete cascade
);
alter table public.window_view_requests enable row level security;
revoke all on public.window_view_requests from anon,authenticated;
grant select on public.window_view_requests to authenticated;
grant all on public.window_view_requests to service_role;
create policy window_view_request_select_own on public.window_view_requests for select to authenticated
  using ((select auth.uid())=user_id);

-- 원래 생성 작업이 보관 기간 뒤 정리돼도 저장한 친구의 배경은 유지한다.
alter table public.window_view_jobs add constraint window_view_jobs_generation_job_fkey
  foreign key (user_id,generation_job_id) references public.generation_jobs(user_id,id)
  on delete set null (generation_job_id);
create unique index window_view_generation_job on public.window_view_jobs(generation_job_id)
  where generation_job_id is not null;
