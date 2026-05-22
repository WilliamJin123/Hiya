-- Hiya: initial schema
-- Tables: profiles, people, conversations
-- + RLS, signup trigger, person-last-logged trigger

----------------------------------------------------------------------
-- profiles: per-user settings, mirrors auth.users 1-to-1
----------------------------------------------------------------------
create table public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  display_name    text,
  daily_goal      int  not null default 10 check (daily_goal between 1 and 50),
  streak_mode     text not null default 'hard' check (streak_mode in ('hard', 'soft')),
  timezone        text not null default 'UTC',
  created_at      timestamptz not null default now()
);

----------------------------------------------------------------------
-- people: persisted social graph (one row per person the user has logged)
----------------------------------------------------------------------
create table public.people (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references public.profiles(id) on delete cascade,
  name            text not null check (length(trim(name)) > 0),
  created_at      timestamptz not null default now(),
  last_logged_at  timestamptz not null default now()
);

create index people_owner_last_logged_idx
  on public.people(owner_id, last_logged_at desc);

----------------------------------------------------------------------
-- conversations: one row per logged interaction
----------------------------------------------------------------------
create table public.conversations (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references public.profiles(id) on delete cascade,
  person_id       uuid not null references public.people(id) on delete cascade,
  occurred_at     timestamptz not null default now(),
  valence         text check (valence in ('positive', 'neutral', 'negative')),
  note            text,
  created_at      timestamptz not null default now()
);

create index conversations_owner_occurred_idx
  on public.conversations(owner_id, occurred_at desc);

----------------------------------------------------------------------
-- Trigger: auto-create profile row on new auth user
----------------------------------------------------------------------
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

----------------------------------------------------------------------
-- Trigger: keep people.last_logged_at fresh when a conversation is added
----------------------------------------------------------------------
create function public.update_person_last_logged()
returns trigger
language plpgsql
as $$
begin
  update public.people
     set last_logged_at = new.occurred_at
   where id = new.person_id
     and last_logged_at < new.occurred_at;
  return new;
end;
$$;

create trigger on_conversation_insert
  after insert on public.conversations
  for each row execute function public.update_person_last_logged();

----------------------------------------------------------------------
-- Row-Level Security
----------------------------------------------------------------------
alter table public.profiles      enable row level security;
alter table public.people        enable row level security;
alter table public.conversations enable row level security;

-- profiles: a user can read and update only their own row.
-- (inserts happen via the signup trigger, deletes cascade from auth.users)
create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id);

-- people: full CRUD for owner
create policy "people_select_own" on public.people
  for select using (auth.uid() = owner_id);
create policy "people_insert_own" on public.people
  for insert with check (auth.uid() = owner_id);
create policy "people_update_own" on public.people
  for update using (auth.uid() = owner_id);
create policy "people_delete_own" on public.people
  for delete using (auth.uid() = owner_id);

-- conversations: full CRUD for owner
create policy "conversations_select_own" on public.conversations
  for select using (auth.uid() = owner_id);
create policy "conversations_insert_own" on public.conversations
  for insert with check (auth.uid() = owner_id);
create policy "conversations_update_own" on public.conversations
  for update using (auth.uid() = owner_id);
create policy "conversations_delete_own" on public.conversations
  for delete using (auth.uid() = owner_id);
