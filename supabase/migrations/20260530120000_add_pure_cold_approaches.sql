-- "Pure cold" approaches: cold approaches made in a non-social environment
-- (e.g. on the street) where the user initiates with no social pretext and
-- brings all the social energy. Unlike was_cold_at_time (which the
-- recompute_cold_flags trigger derives from chronology), this is a user choice
-- at log time, so it is set explicitly on insert and never recomputed.
--
-- Surfaced by the experimental "hard mode": at least N of today's approaches
-- must be pure cold. N lives in the app (HardMode.pureColdQuota), not here.
alter table public.conversations
  add column was_pure_cold boolean not null default false;
