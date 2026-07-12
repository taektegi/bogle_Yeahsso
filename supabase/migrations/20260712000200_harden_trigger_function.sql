-- The Auth trigger may call this function, but API roles must not call it directly.
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- Supports ownership filtering and auth.users cascade deletion.
create index reflection_messages_user_id_idx
  on public.reflection_messages (user_id);
