-- One-time fix: people the user knew before the app but who landed in the cold
-- "Just Met" section. Promote them to warm "Catch-ups". Scoped to currently-cold
-- rows, so re-running is a no-op once they're warm.
update public.people
set status = 'warm', status_changed_at = now()
where status = 'cold'
  and lower(name) in ('kola', 'cedric', 'jason');
