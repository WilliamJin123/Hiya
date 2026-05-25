-- Durable "this relationship began as a cold approach" flag, independent of
-- the live cold/warm bucket (which graduates over time). Classification of
-- was_cold_at_time moves from a status snapshot to a chronological recompute.

alter table public.people
  add column met_cold boolean not null default false;

-- Backfill: met cold if still cold (a pending approach) or any conversation
-- was logged while cold.
update public.people p
   set met_cold = true
 where p.status = 'cold'
    or exists (
      select 1 from public.conversations c
       where c.person_id = p.id and c.was_cold_at_time
    );

-- Retire the BEFORE INSERT status snapshot — classification is now chronological.
drop trigger if exists set_was_cold_at_time_before_insert on public.conversations;
drop function if exists public.set_was_cold_at_time();

-- Recompute one person's flags: earliest meeting (occurred_at, id) is cold iff
-- met_cold; every other meeting is warm.
create or replace function public.recompute_cold_flags(p uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  earliest uuid;
  is_cold boolean;
begin
  select met_cold into is_cold from public.people where id = p;
  update public.conversations set was_cold_at_time = false
   where person_id = p and was_cold_at_time;
  if coalesce(is_cold, false) then
    select id into earliest
      from public.conversations
     where person_id = p
     order by occurred_at asc, id asc
     limit 1;
    if earliest is not null then
      update public.conversations set was_cold_at_time = true where id = earliest;
    end if;
  end if;
end;
$$;

-- Trigger glue for conversations. Recompute only fires on inserts/deletes and
-- on changes to occurred_at/person_id, so the was_cold_at_time UPDATE inside
-- recompute does NOT re-fire it (no recursion).
create or replace function public.recompute_cold_flags_on_conversation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (tg_op = 'DELETE') then
    perform public.recompute_cold_flags(old.person_id);
    return old;
  end if;
  perform public.recompute_cold_flags(new.person_id);
  if (tg_op = 'UPDATE' and old.person_id is distinct from new.person_id) then
    perform public.recompute_cold_flags(old.person_id);
  end if;
  return new;
end;
$$;

drop trigger if exists recompute_cold_flags_conv on public.conversations;
create trigger recompute_cold_flags_conv
  after insert or delete or update of occurred_at, person_id
  on public.conversations
  for each row execute function public.recompute_cold_flags_on_conversation();

-- Trigger glue for people: recompute when met_cold changes.
create or replace function public.recompute_cold_flags_on_person()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.recompute_cold_flags(new.id);
  return new;
end;
$$;

drop trigger if exists recompute_cold_flags_person on public.people;
create trigger recompute_cold_flags_person
  after update of met_cold on public.people
  for each row execute function public.recompute_cold_flags_on_person();

-- One-time normalize for existing data.
do $$
declare r record;
begin
  for r in select id from public.people loop
    perform public.recompute_cold_flags(r.id);
  end loop;
end $$;
