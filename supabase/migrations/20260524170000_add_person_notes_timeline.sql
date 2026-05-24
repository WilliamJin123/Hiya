----------------------------------------------------------------------
-- person_notes: dated timeline of notes about a person. Each entry keeps an
-- immutable created_at ("learned on") plus an updated_at that is null until
-- the entry is first edited.
----------------------------------------------------------------------
create table public.person_notes (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  person_id  uuid not null references public.people(id) on delete cascade,
  body       text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

create index person_notes_person_created_idx
  on public.person_notes(person_id, created_at desc);

alter table public.person_notes enable row level security;

create policy "person_notes_select_own" on public.person_notes
  for select using (auth.uid() = owner_id);
create policy "person_notes_insert_own" on public.person_notes
  for insert with check (auth.uid() = owner_id);
create policy "person_notes_update_own" on public.person_notes
  for update using (auth.uid() = owner_id);
create policy "person_notes_delete_own" on public.person_notes
  for delete using (auth.uid() = owner_id);

----------------------------------------------------------------------
-- Backfill: seed one entry per person who already has a note. The "learned on"
-- date is the person's earliest conversation, falling back to when the person
-- record itself was created.
----------------------------------------------------------------------
insert into public.person_notes (owner_id, person_id, body, created_at)
select p.owner_id,
       p.id,
       p.notes,
       coalesce(
         (select min(c.occurred_at) from public.conversations c where c.person_id = p.id),
         p.created_at
       )
from public.people p
where p.notes is not null and btrim(p.notes) <> '';
