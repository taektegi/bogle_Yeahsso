-- B 담당 FR-03~05. 공개 API 쓰기는 FastAPI만 허용한다.
create table public.generation_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source_asset_id uuid not null,
  source_type text not null check (source_type in ('drawing', 'photo')),
  status text not null default 'queued'
    check (status in ('queued', 'processing', 'succeeded', 'failed', 'cancelled')),
  idempotency_key text not null check (idempotency_key ~ '^[A-Za-z0-9_-]{8,64}$'),
  request_fingerprint text not null,
  model text not null,
  prompt_version text not null,
  art_asset_id uuid,
  thumbnail_asset_id uuid,
  accent_argb bigint check (accent_argb between 0 and 4294967295),
  error_code text,
  error_message text,
  error_retryable boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  started_at timestamptz,
  worker_owner uuid,
  finished_at timestamptz,
  unique (user_id, id),
  unique (user_id, idempotency_key),
  foreign key (user_id, source_asset_id) references public.assets(user_id, id)
    on delete cascade,
  foreign key (user_id, art_asset_id) references public.assets(user_id, id)
    on delete set null (art_asset_id),
  foreign key (user_id, thumbnail_asset_id) references public.assets(user_id, id)
    on delete set null (thumbnail_asset_id),
  check (status <> 'succeeded' or
    (art_asset_id is not null and thumbnail_asset_id is not null and accent_argb is not null)),
  check (status <> 'failed' or (error_code is not null and error_message is not null))
);
create index generation_jobs_queue_idx on public.generation_jobs(created_at, id)
  where status = 'queued';
create index generation_jobs_user_created_idx on public.generation_jobs(user_id, created_at);
create index generation_jobs_source_idx on public.generation_jobs(source_asset_id);
create index generation_jobs_art_idx on public.generation_jobs(art_asset_id);
create index generation_jobs_thumbnail_idx on public.generation_jobs(thumbnail_asset_id);
create trigger set_generation_jobs_updated_at before update on public.generation_jobs
  for each row execute function public.set_updated_at();
alter table public.generation_jobs enable row level security;
revoke all on public.generation_jobs from anon, authenticated;
grant select on public.generation_jobs to authenticated;
grant all on public.generation_jobs to service_role;
create policy generation_jobs_select_own on public.generation_jobs for select
  to authenticated using ((select auth.uid()) = user_id);

-- 작업을 24시간 뒤 정리해도 저장된 친구와 저장 멱등 키는 남긴다.
alter table public.friends add constraint friends_generation_job_fkey
  foreign key (user_id, generation_job_id) references public.generation_jobs(user_id, id)
  on delete set null (generation_job_id);

-- 트랜잭션 pooler에서도 안전한 DB 임대 잠금. 한 서버만 작업을 맡는다.
create table public.generation_worker_lease (
  id integer primary key check (id = 1),
  owner uuid not null,
  expires_at timestamptz not null
);
alter table public.generation_worker_lease enable row level security;
revoke all on public.generation_worker_lease from anon, authenticated;
grant all on public.generation_worker_lease to service_role;
