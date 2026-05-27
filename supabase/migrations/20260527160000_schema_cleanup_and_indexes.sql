-- Schema hardening + cleanup: FK indexes, role-scoped RLS, drop a dead column.

----------------------------------------------------------------------
-- Indexes on foreign-key columns (Postgres does NOT auto-index FKs).
----------------------------------------------------------------------
-- conversations.person_id is unindexed yet hit on hot paths: the per-person
-- history query (WHERE person_id = ? ORDER BY occurred_at), recompute_cold_flags'
-- earliest-conversation lookup, and the person/account cascade-delete scans.
create index if not exists conversations_person_occurred_idx
  on public.conversations(person_id, occurred_at);

-- person_notes.owner_id is unindexed; the profiles -> person_notes cascade
-- (account deletion) would otherwise seq-scan it.
create index if not exists person_notes_owner_idx
  on public.person_notes(owner_id);

----------------------------------------------------------------------
-- Scope every RLS policy to the `authenticated` role. Anonymous *sign-ins*
-- carry the authenticated role too, so this changes nothing for real users,
-- but stops the policies being evaluated for the bare `anon` role and matches
-- Supabase's own advisor guidance. USING/WITH CHECK are left intact.
----------------------------------------------------------------------
alter policy "profiles_select_own"        on public.profiles      to authenticated;
alter policy "profiles_update_own"        on public.profiles      to authenticated;

alter policy "people_select_own"          on public.people        to authenticated;
alter policy "people_insert_own"          on public.people        to authenticated;
alter policy "people_update_own"          on public.people        to authenticated;
alter policy "people_delete_own"          on public.people        to authenticated;

alter policy "conversations_select_own"   on public.conversations to authenticated;
alter policy "conversations_insert_own"   on public.conversations to authenticated;
alter policy "conversations_update_own"   on public.conversations to authenticated;
alter policy "conversations_delete_own"   on public.conversations to authenticated;

alter policy "challenges_select_own"      on public.challenges    to authenticated;
alter policy "challenges_insert_own"      on public.challenges    to authenticated;
alter policy "challenges_update_own"      on public.challenges    to authenticated;
alter policy "challenges_delete_own"      on public.challenges    to authenticated;

alter policy "person_notes_select_own"    on public.person_notes  to authenticated;
alter policy "person_notes_insert_own"    on public.person_notes  to authenticated;
alter policy "person_notes_update_own"    on public.person_notes  to authenticated;
alter policy "person_notes_delete_own"    on public.person_notes  to authenticated;

----------------------------------------------------------------------
-- Drop the legacy single daily goal. Superseded by cold_daily_goal /
-- warm_daily_goal since the per-mode-goals migration; nothing reads it.
-- (streak_mode and timezone are intentionally kept — earmarked for the
-- forgiving-streak feature.)
----------------------------------------------------------------------
alter table public.profiles drop column daily_goal;
