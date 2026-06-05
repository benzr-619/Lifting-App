-- =============================================================
-- Migration 004: Set DEFAULT auth.uid() on user_id columns
--
-- 003 added and backfilled user_id but left no default, meaning
-- every INSERT from the app would need to pass user_id explicitly.
-- Setting DEFAULT auth.uid() lets the DB fill it in automatically
-- from the authenticated session, so app inserts stay unchanged.
-- =============================================================

ALTER TABLE lift.exercise_state ALTER COLUMN user_id SET DEFAULT auth.uid();
ALTER TABLE lift.sessions        ALTER COLUMN user_id SET DEFAULT auth.uid();
ALTER TABLE lift.session_sets    ALTER COLUMN user_id SET DEFAULT auth.uid();
ALTER TABLE lift.plan_state      ALTER COLUMN user_id SET DEFAULT auth.uid();
ALTER TABLE lift.plan_config     ALTER COLUMN user_id SET DEFAULT auth.uid();
ALTER TABLE lift.daily_log       ALTER COLUMN user_id SET DEFAULT auth.uid();
