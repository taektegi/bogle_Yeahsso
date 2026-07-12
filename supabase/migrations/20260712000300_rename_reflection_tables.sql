-- Align current film creation terminology while preserving all data and columns.
alter table public.reflection_sessions rename to film_sessions;
alter table public.reflection_messages rename to film_messages;

alter table public.film_sessions
  rename constraint reflection_sessions_pkey to film_sessions_pkey;
alter table public.film_sessions
  rename constraint reflection_sessions_film_id_key to film_sessions_film_id_key;
alter table public.film_sessions
  rename constraint reflection_sessions_film_id_fkey to film_sessions_film_id_fkey;
alter table public.film_sessions
  rename constraint reflection_sessions_user_id_fkey to film_sessions_user_id_fkey;
alter table public.film_sessions
  rename constraint reflection_sessions_status_check to film_sessions_status_check;

alter table public.film_messages
  rename constraint reflection_messages_pkey to film_messages_pkey;
alter table public.film_messages
  rename constraint reflection_messages_session_id_fkey to film_messages_session_id_fkey;
alter table public.film_messages
  rename constraint reflection_messages_user_id_fkey to film_messages_user_id_fkey;
alter table public.film_messages
  rename constraint reflection_messages_role_check to film_messages_role_check;
alter table public.film_messages
  rename constraint reflection_messages_message_order_check to film_messages_message_order_check;
alter table public.film_messages
  rename constraint reflection_messages_session_order_key to film_messages_session_order_key;

alter index public.reflection_sessions_user_id_started_at_idx
  rename to film_sessions_user_id_started_at_idx;
alter index public.reflection_messages_user_id_idx
  rename to film_messages_user_id_idx;

alter policy "reflection_sessions_select_own"
  on public.film_sessions rename to "film_sessions_select_own";
alter policy "reflection_sessions_insert_own"
  on public.film_sessions rename to "film_sessions_insert_own";
alter policy "reflection_sessions_update_own"
  on public.film_sessions rename to "film_sessions_update_own";
alter policy "reflection_sessions_delete_own"
  on public.film_sessions rename to "film_sessions_delete_own";

alter policy "reflection_messages_select_own"
  on public.film_messages rename to "film_messages_select_own";
alter policy "reflection_messages_insert_own"
  on public.film_messages rename to "film_messages_insert_own";
alter policy "reflection_messages_update_own"
  on public.film_messages rename to "film_messages_update_own";
alter policy "reflection_messages_delete_own"
  on public.film_messages rename to "film_messages_delete_own";
