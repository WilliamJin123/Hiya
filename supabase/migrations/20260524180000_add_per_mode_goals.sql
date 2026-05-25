----------------------------------------------------------------------
-- Per-mode daily goals: Approaches (cold) and Catch-ups (warm) get
-- independent targets, consistent with the "never share a counter/ring/
-- streak" rule. The legacy single daily_goal column is left in place
-- (unused) to avoid a destructive change; both new columns seed from it.
----------------------------------------------------------------------
alter table public.profiles add column cold_daily_goal int not null default 10;
alter table public.profiles add column warm_daily_goal int not null default 10;

update public.profiles
set cold_daily_goal = coalesce(daily_goal, 10),
    warm_daily_goal = coalesce(daily_goal, 10);
