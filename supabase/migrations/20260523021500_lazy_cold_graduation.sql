-- Slice 2.5: switch from immediate graduation to lazy time-based graduation.
-- Previously, the first conversation with a Cold person immediately flipped
-- them to Warm via an AFTER INSERT trigger. The desired behavior is that
-- a person you just met *today* stays Cold for the whole day (so repeat
-- conversations with them today still count as Cold approaches), and only
-- graduates once the daily cycle resets.
--
-- The app now calls a graduate-past-due update on each refresh:
--   UPDATE people SET status='warm' WHERE status='cold' AND last_logged_at < start_of_today
-- so we no longer need a DB-side AFTER INSERT trigger.
--
-- The BEFORE INSERT trigger (snapshot was_cold_at_time onto each new row)
-- stays — its semantics are unchanged.

drop trigger if exists graduate_person_on_cold_log_after_insert on public.conversations;
drop function if exists public.graduate_person_on_cold_log();
