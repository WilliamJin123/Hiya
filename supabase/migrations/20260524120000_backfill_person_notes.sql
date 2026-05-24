-- Backfill: a person's note defaults to the first (earliest) note recorded
-- about them, matching the "first note becomes the person's note" rule applied
-- to newly-created people. Only fills people who don't already have a note.
update public.people p
set notes = sub.note
from (
  select distinct on (person_id)
         person_id,
         note
  from public.conversations
  where note is not null and btrim(note) <> ''
  order by person_id, occurred_at asc
) sub
where p.id = sub.person_id
  and (p.notes is null or btrim(p.notes) = '');
