-- Optional free-text location per meeting (place name or address).
alter table public.conversations
  add column location text;
