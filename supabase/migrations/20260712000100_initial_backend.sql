-- Initial backend schema for 오늘의 필름.

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.films (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  recorded_date date not null,
  title text,
  one_line text,
  memorable_quote text,
  status text not null default 'draft',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint films_status_check check (status in ('draft', 'completed'))
);

create index films_user_id_recorded_date_idx
  on public.films (user_id, recorded_date desc);

create table public.film_photos (
  id uuid primary key default gen_random_uuid(),
  film_id uuid not null references public.films(id) on delete cascade,
  storage_path text not null,
  display_order integer not null default 0,
  is_representative boolean not null default false,
  created_at timestamptz not null default now(),
  constraint film_photos_display_order_check check (display_order >= 0)
);

create unique index film_photos_one_representative_per_film_idx
  on public.film_photos (film_id)
  where is_representative;

create index film_photos_film_id_display_order_idx
  on public.film_photos (film_id, display_order);

create table public.reflection_sessions (
  id uuid primary key default gen_random_uuid(),
  film_id uuid not null unique references public.films(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'active',
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint reflection_sessions_status_check
    check (status in ('active', 'completed', 'cancelled'))
);

create index reflection_sessions_user_id_started_at_idx
  on public.reflection_sessions (user_id, started_at desc);

create table public.reflection_messages (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.reflection_sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null,
  content text not null,
  message_order integer not null,
  created_at timestamptz not null default now(),
  constraint reflection_messages_role_check check (role in ('user', 'assistant')),
  constraint reflection_messages_message_order_check check (message_order >= 0),
  constraint reflection_messages_session_order_key unique (session_id, message_order)
);

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

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger films_set_updated_at
before update on public.films
for each row execute function public.set_updated_at();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.films enable row level security;
alter table public.film_photos enable row level security;
alter table public.reflection_sessions enable row level security;
alter table public.reflection_messages enable row level security;

create policy "profiles_select_own"
on public.profiles for select to authenticated
using ((select auth.uid()) = id);

create policy "profiles_update_own"
on public.profiles for update to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

create policy "films_select_own"
on public.films for select to authenticated
using ((select auth.uid()) = user_id);

create policy "films_insert_own"
on public.films for insert to authenticated
with check ((select auth.uid()) = user_id);

create policy "films_update_own"
on public.films for update to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "films_delete_own"
on public.films for delete to authenticated
using ((select auth.uid()) = user_id);

create policy "film_photos_select_own"
on public.film_photos for select to authenticated
using (exists (
  select 1 from public.films
  where films.id = film_photos.film_id
    and films.user_id = (select auth.uid())
));

create policy "film_photos_insert_own"
on public.film_photos for insert to authenticated
with check (exists (
  select 1 from public.films
  where films.id = film_photos.film_id
    and films.user_id = (select auth.uid())
));

create policy "film_photos_update_own"
on public.film_photos for update to authenticated
using (exists (
  select 1 from public.films
  where films.id = film_photos.film_id
    and films.user_id = (select auth.uid())
))
with check (exists (
  select 1 from public.films
  where films.id = film_photos.film_id
    and films.user_id = (select auth.uid())
));

create policy "film_photos_delete_own"
on public.film_photos for delete to authenticated
using (exists (
  select 1 from public.films
  where films.id = film_photos.film_id
    and films.user_id = (select auth.uid())
));

create policy "reflection_sessions_select_own"
on public.reflection_sessions for select to authenticated
using ((select auth.uid()) = user_id);

create policy "reflection_sessions_insert_own"
on public.reflection_sessions for insert to authenticated
with check (
  (select auth.uid()) = user_id
  and exists (
    select 1 from public.films
    where films.id = reflection_sessions.film_id
      and films.user_id = (select auth.uid())
  )
);

create policy "reflection_sessions_update_own"
on public.reflection_sessions for update to authenticated
using ((select auth.uid()) = user_id)
with check (
  (select auth.uid()) = user_id
  and exists (
    select 1 from public.films
    where films.id = reflection_sessions.film_id
      and films.user_id = (select auth.uid())
  )
);

create policy "reflection_sessions_delete_own"
on public.reflection_sessions for delete to authenticated
using ((select auth.uid()) = user_id);

create policy "reflection_messages_select_own"
on public.reflection_messages for select to authenticated
using (
  (select auth.uid()) = user_id
  and exists (
    select 1 from public.reflection_sessions
    where reflection_sessions.id = reflection_messages.session_id
      and reflection_sessions.user_id = (select auth.uid())
  )
);

create policy "reflection_messages_insert_own"
on public.reflection_messages for insert to authenticated
with check (
  (select auth.uid()) = user_id
  and exists (
    select 1 from public.reflection_sessions
    where reflection_sessions.id = reflection_messages.session_id
      and reflection_sessions.user_id = (select auth.uid())
  )
);

create policy "reflection_messages_update_own"
on public.reflection_messages for update to authenticated
using (
  (select auth.uid()) = user_id
  and exists (
    select 1 from public.reflection_sessions
    where reflection_sessions.id = reflection_messages.session_id
      and reflection_sessions.user_id = (select auth.uid())
  )
)
with check (
  (select auth.uid()) = user_id
  and exists (
    select 1 from public.reflection_sessions
    where reflection_sessions.id = reflection_messages.session_id
      and reflection_sessions.user_id = (select auth.uid())
  )
);

create policy "reflection_messages_delete_own"
on public.reflection_messages for delete to authenticated
using (
  (select auth.uid()) = user_id
  and exists (
    select 1 from public.reflection_sessions
    where reflection_sessions.id = reflection_messages.session_id
      and reflection_sessions.user_id = (select auth.uid())
  )
);

insert into storage.buckets (id, name, public)
values ('film-media', 'film-media', false);

create policy "film_media_select_own"
on storage.objects for select to authenticated
using (
  bucket_id = 'film-media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "film_media_insert_own"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'film-media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "film_media_update_own"
on storage.objects for update to authenticated
using (
  bucket_id = 'film-media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'film-media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "film_media_delete_own"
on storage.objects for delete to authenticated
using (
  bucket_id = 'film-media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
