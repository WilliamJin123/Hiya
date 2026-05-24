-- Follow-up to the promotion of Kola/Cedric/Jason: their existing conversations
-- were snapshotted was_cold_at_time = true, so they still showed in the cold
-- "Approaches" tally. Since they were known beforehand, those logs were never
-- cold approaches — reclassify them as warm.
update public.conversations c
set was_cold_at_time = false
from public.people p
where c.person_id = p.id
  and p.status = 'warm'
  and lower(p.name) in ('kola', 'cedric', 'jason');
