-- Cold/Warm status on people + was_cold_at_time snapshot on conversations.
-- Slice 2.0 foundation.

-- 1. people.status: 'cold' (stranger / not-yet-engaged) | 'warm' (relationship in progress)
alter table public.people
  add column status text not null default 'cold'
    check (status in ('cold', 'warm'));

alter table public.people
  add column status_changed_at timestamptz;

-- Backfill: any person with at least one logged conversation has already
-- graduated to warm. Set status_changed_at to the time of their first log.
update public.people p
   set status = 'warm',
       status_changed_at = first_log.first_at
  from (
    select person_id, min(occurred_at) as first_at
      from public.conversations
     group by person_id
  ) first_log
 where p.id = first_log.person_id;

-- 2. conversations.was_cold_at_time: snapshot of the person's status at the
-- moment this conversation was logged. Stable historical record (won't shift
-- if the person is later demoted/promoted manually).
alter table public.conversations
  add column was_cold_at_time boolean not null default false;

-- Backfill: the FIRST conversation with each person was the cold one;
-- everything after is warm. Use occurred_at to determine ordering.
update public.conversations c
   set was_cold_at_time = true
  from (
    select id from (
      select id,
             row_number() over (partition by person_id order by occurred_at, id) as rn
        from public.conversations
    ) ranked
     where rn = 1
  ) first_convs
 where c.id = first_convs.id;

-- 3. Trigger: BEFORE INSERT — snapshot the person's current status into
-- was_cold_at_time on the new conversation row. Lets app code stay simple
-- (just insert; the DB knows what the person's status was).
create or replace function public.set_was_cold_at_time()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  current_status text;
begin
  select status into current_status
    from public.people
   where id = new.person_id;
  new.was_cold_at_time := (current_status = 'cold');
  return new;
end;
$$;

drop trigger if exists set_was_cold_at_time_before_insert on public.conversations;
create trigger set_was_cold_at_time_before_insert
  before insert on public.conversations
  for each row execute function public.set_was_cold_at_time();

-- 4. Trigger: AFTER INSERT — if the conversation was cold, graduate the
-- person to warm and stamp status_changed_at. Idempotent: only fires when
-- the person is currently cold.
create or replace function public.graduate_person_on_cold_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.was_cold_at_time then
    update public.people
       set status = 'warm',
           status_changed_at = now()
     where id = new.person_id
       and status = 'cold';
  end if;
  return new;
end;
$$;

drop trigger if exists graduate_person_on_cold_log_after_insert on public.conversations;
create trigger graduate_person_on_cold_log_after_insert
  after insert on public.conversations
  for each row execute function public.graduate_person_on_cold_log();
