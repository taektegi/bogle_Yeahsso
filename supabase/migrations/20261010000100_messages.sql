-- 친구와 나눈 대화 (FR-09).
-- 사용자 메시지에 client_message_id를 붙여 앱의 중복 전송에도 한 번만 저장한다.

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  character_id uuid not null,
  role text not null,
  text text not null,
  source text,
  client_message_id text,
  request_fingerprint text,
  reply_to_id uuid,
  created_at timestamptz not null default now(),

  constraint messages_character_owner_fkey
    foreign key (user_id, character_id)
    references public.friends (user_id, id)
    on delete cascade,
  constraint messages_user_character_id_key unique (user_id, character_id, id),
  constraint messages_reply_owner_fkey
    foreign key (user_id, character_id, reply_to_id)
    references public.messages (user_id, character_id, id)
    on delete cascade,
  constraint messages_role_check check (role in ('user', 'assistant')),
  constraint messages_text_check check (char_length(btrim(text)) between 1 and 2000),
  constraint messages_source_check check (source is null or source in ('ai', 'script')),
  constraint messages_client_message_id_format_check
    check (client_message_id is null or client_message_id ~ '^[A-Za-z0-9_-]{8,64}$'),
  constraint messages_shape_check check (
    (
      role = 'user'
      and source is null
      and client_message_id is not null
      and request_fingerprint is not null
      and reply_to_id is null
    )
    or
    (
      role = 'assistant'
      and source is not null
      and client_message_id is null
      and request_fingerprint is null
      and reply_to_id is not null
    )
  ),
  constraint messages_character_id_client_message_id_key
    unique (character_id, client_message_id),
  constraint messages_reply_to_id_key unique (reply_to_id)
);

create index messages_user_character_created_idx
  on public.messages (user_id, character_id, created_at desc, id desc);

alter table public.messages enable row level security;

revoke all on public.messages from anon, authenticated;
grant select on public.messages to authenticated;

create policy messages_select_own
  on public.messages for select to authenticated
  using ((select auth.uid()) = user_id);
