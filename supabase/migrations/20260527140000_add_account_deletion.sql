-- Self-service account deletion. The anon key can't touch auth.users, so a
-- SECURITY DEFINER function deletes the *calling* user; cascades wipe all data
-- (profiles -> people / conversations / person_notes / challenges).
create or replace function public.delete_current_user()
returns void
language sql
security definer
set search_path = public
as $$
  delete from auth.users where id = auth.uid();
$$;

revoke execute on function public.delete_current_user() from public;
grant execute on function public.delete_current_user() to authenticated;

-- Hardening: recompute_cold_flags is a SECURITY DEFINER helper only ever called
-- by triggers (which keep access as the definer). Stop it being a directly
-- callable RPC for ordinary clients.
revoke execute on function public.recompute_cold_flags(uuid) from anon, authenticated;
