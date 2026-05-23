-- Free-text notes attached to a person (separate from per-conversation notes).
-- Slice 2.4.

alter table public.people
  add column notes text;
