----------------------------------------------------------------------
-- challenges: one row per started themed challenge (active or finished)
----------------------------------------------------------------------
create table public.challenges (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references public.profiles(id) on delete cascade,
  title         text not null,
  prompt        text not null,
  track         text not null default 'any' check (track in ('cold','warm','any')),
  target_count  int,
  duration_days int,
  source        text not null default 'custom' check (source in ('catalog','custom')),
  template_slug text,
  started_at    timestamptz not null default now(),
  completed_at  timestamptz,
  created_at    timestamptz not null default now()
);

create index challenges_owner_started_idx
  on public.challenges(owner_id, started_at desc);

alter table public.challenges enable row level security;

create policy "challenges_select_own" on public.challenges
  for select using (auth.uid() = owner_id);
create policy "challenges_insert_own" on public.challenges
  for insert with check (auth.uid() = owner_id);
create policy "challenges_update_own" on public.challenges
  for update using (auth.uid() = owner_id);
create policy "challenges_delete_own" on public.challenges
  for delete using (auth.uid() = owner_id);
