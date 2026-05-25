-- Anonymous "quick approach" people: nameless cold approaches that count toward
-- the Approaches goal/streak but are never shown as relationships (People list,
-- follow-up suggestions). Each quick approach is its own hidden person so the
-- per-person count tallies each attempt.
alter table public.people
  add column anonymous boolean not null default false;
