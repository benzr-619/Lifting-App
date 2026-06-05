-- =============================================================
-- Migration 003: user_id + RLS
--
-- What this does:
--   1. Adds user_id to all user-owned tables
--   2. Backfills existing rows with Ben's user_id
--   3. Makes user_id NOT NULL
--   4. Fixes constraints for multi-user correctness:
--        - exercise_state: UNIQUE(user_id, exercise_id) replaces UNIQUE(exercise_id)
--        - daily_log:      UNIQUE(user_id, log_date)    replaces UNIQUE(log_date)
--        - plan_state:     UNIQUE(user_id)              replaces singleton_guard UNIQUE
--        - plan_config:    UNIQUE(user_id)              replaces singleton_guard UNIQUE
--   5. Enables RLS on all lift tables
--   6. Adds policies: reference tables → authenticated read;
--                     user-owned tables → owner-only CRUD
--   7. Recreates views as SECURITY INVOKER so RLS applies
--
-- Reference tables (exercises, cycle_plan) need no user_id —
-- they are shared static config. RLS on them just requires login.
--
-- Ben's user_id: 1438970f-eff7-4a02-906a-072acd711f86
-- =============================================================

-- ----------------------------------------------------------
-- 1. Add user_id columns (nullable first for backfill)
-- ----------------------------------------------------------

ALTER TABLE lift.exercise_state
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE lift.sessions
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE lift.session_sets
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE lift.plan_state
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE lift.plan_config
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE lift.daily_log
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

-- ----------------------------------------------------------
-- 2. Backfill existing rows
-- ----------------------------------------------------------

UPDATE lift.exercise_state SET user_id = '1438970f-eff7-4a02-906a-072acd711f86' WHERE user_id IS NULL;
UPDATE lift.sessions        SET user_id = '1438970f-eff7-4a02-906a-072acd711f86' WHERE user_id IS NULL;
UPDATE lift.session_sets    SET user_id = '1438970f-eff7-4a02-906a-072acd711f86' WHERE user_id IS NULL;
UPDATE lift.plan_state      SET user_id = '1438970f-eff7-4a02-906a-072acd711f86' WHERE user_id IS NULL;
UPDATE lift.plan_config     SET user_id = '1438970f-eff7-4a02-906a-072acd711f86' WHERE user_id IS NULL;
UPDATE lift.daily_log       SET user_id = '1438970f-eff7-4a02-906a-072acd711f86' WHERE user_id IS NULL;

-- ----------------------------------------------------------
-- 3. Make user_id NOT NULL
-- ----------------------------------------------------------

ALTER TABLE lift.exercise_state ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE lift.sessions        ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE lift.session_sets    ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE lift.plan_state      ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE lift.plan_config     ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE lift.daily_log       ALTER COLUMN user_id SET NOT NULL;

-- ----------------------------------------------------------
-- 3b. Set DEFAULT auth.uid() so app INSERTs don't need explicit user_id
-- ----------------------------------------------------------

ALTER TABLE lift.exercise_state ALTER COLUMN user_id SET DEFAULT auth.uid();
ALTER TABLE lift.sessions        ALTER COLUMN user_id SET DEFAULT auth.uid();
ALTER TABLE lift.session_sets    ALTER COLUMN user_id SET DEFAULT auth.uid();
ALTER TABLE lift.plan_state      ALTER COLUMN user_id SET DEFAULT auth.uid();
ALTER TABLE lift.plan_config     ALTER COLUMN user_id SET DEFAULT auth.uid();
ALTER TABLE lift.daily_log       ALTER COLUMN user_id SET DEFAULT auth.uid();

-- ----------------------------------------------------------
-- 4. Fix constraints for multi-user correctness
-- ----------------------------------------------------------

-- exercise_state: was UNIQUE(exercise_id) — one state per exercise globally.
-- Now UNIQUE(user_id, exercise_id) — one state per user per exercise.
ALTER TABLE lift.exercise_state
  DROP CONSTRAINT IF EXISTS exercise_state_exercise_id_key;
ALTER TABLE lift.exercise_state
  ADD CONSTRAINT exercise_state_user_exercise_key UNIQUE (user_id, exercise_id);

-- daily_log: was UNIQUE(log_date) — one entry per date globally.
-- Now UNIQUE(user_id, log_date) — one entry per user per date.
ALTER TABLE lift.daily_log
  DROP CONSTRAINT IF EXISTS daily_log_log_date_key;
ALTER TABLE lift.daily_log
  ADD CONSTRAINT daily_log_user_date_key UNIQUE (user_id, log_date);

-- plan_state: singleton_guard enforced one row globally.
-- Drop it; UNIQUE(user_id) enforces one row per user instead.
ALTER TABLE lift.plan_state
  DROP CONSTRAINT IF EXISTS plan_state_singleton_guard_key;
ALTER TABLE lift.plan_state
  ADD CONSTRAINT plan_state_user_key UNIQUE (user_id);

-- plan_config: same treatment as plan_state.
ALTER TABLE lift.plan_config
  DROP CONSTRAINT IF EXISTS plan_config_singleton_guard_key;
ALTER TABLE lift.plan_config
  ADD CONSTRAINT plan_config_user_key UNIQUE (user_id);

-- ----------------------------------------------------------
-- 5. Enable RLS on all lift tables
-- ----------------------------------------------------------

ALTER TABLE lift.exercises      ENABLE ROW LEVEL SECURITY;
ALTER TABLE lift.exercise_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE lift.sessions        ENABLE ROW LEVEL SECURITY;
ALTER TABLE lift.session_sets    ENABLE ROW LEVEL SECURITY;
ALTER TABLE lift.cycle_plan      ENABLE ROW LEVEL SECURITY;
ALTER TABLE lift.plan_state      ENABLE ROW LEVEL SECURITY;
ALTER TABLE lift.plan_config     ENABLE ROW LEVEL SECURITY;
ALTER TABLE lift.daily_log       ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------
-- 6. RLS Policies
-- ----------------------------------------------------------

-- exercises: shared reference data; any authenticated user can read.
-- No INSERT/UPDATE/DELETE from the app — manage via Supabase dashboard.
DROP POLICY IF EXISTS "Authenticated read exercises" ON lift.exercises;
CREATE POLICY "Authenticated read exercises"
  ON lift.exercises FOR SELECT
  TO authenticated
  USING (true);

-- cycle_plan: same as exercises.
DROP POLICY IF EXISTS "Authenticated read cycle_plan" ON lift.cycle_plan;
CREATE POLICY "Authenticated read cycle_plan"
  ON lift.cycle_plan FOR SELECT
  TO authenticated
  USING (true);

-- exercise_state: users manage their own rows only.
DROP POLICY IF EXISTS "Users manage own exercise_state" ON lift.exercise_state;
CREATE POLICY "Users manage own exercise_state"
  ON lift.exercise_state FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- sessions: users manage their own rows only.
DROP POLICY IF EXISTS "Users manage own sessions" ON lift.sessions;
CREATE POLICY "Users manage own sessions"
  ON lift.sessions FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- session_sets: users manage their own rows only.
DROP POLICY IF EXISTS "Users manage own session_sets" ON lift.session_sets;
CREATE POLICY "Users manage own session_sets"
  ON lift.session_sets FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- plan_state: users manage their own singleton.
DROP POLICY IF EXISTS "Users manage own plan_state" ON lift.plan_state;
CREATE POLICY "Users manage own plan_state"
  ON lift.plan_state FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- plan_config: users manage their own singleton.
DROP POLICY IF EXISTS "Users manage own plan_config" ON lift.plan_config;
CREATE POLICY "Users manage own plan_config"
  ON lift.plan_config FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- daily_log: users manage their own rows only.
DROP POLICY IF EXISTS "Users manage own daily_log" ON lift.daily_log;
CREATE POLICY "Users manage own daily_log"
  ON lift.daily_log FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ----------------------------------------------------------
-- 7. Recreate views as SECURITY INVOKER
--
-- PostgreSQL views are SECURITY INVOKER by default, but we make
-- it explicit so RLS on the underlying tables is always enforced
-- (the querying user's policies apply, not the view owner's).
-- DROP + CREATE is required because OR REPLACE can't change
-- the security mode.
-- ----------------------------------------------------------

DROP VIEW IF EXISTS lift.v_readiness;
CREATE VIEW lift.v_readiness
  WITH (security_invoker = true)
AS
SELECT
  dl.log_date,
  dl.knee_pain_level,
  dl.joint_fullness,
  dl.run_outcome,
  CASE
    WHEN COALESCE(dl.joint_fullness, false)
      OR dl.knee_pain_level >= 4
      OR dl.run_outcome = 'flagged'                                    THEN 'red'
    WHEN dl.knee_pain_level = 3                                        THEN 'amber'
    ELSE 'green'
  END AS readiness
FROM lift.daily_log dl
ORDER BY dl.log_date DESC
LIMIT 1;

DROP VIEW IF EXISTS lift.v_phase_ready;
CREATE VIEW lift.v_phase_ready
  WITH (security_invoker = true)
AS
SELECT
  ps.current_phase,
  ps.current_cycle_day,
  ps.clean_cycles_completed,
  pc.clean_cycles_required,
  (ps.clean_cycles_completed >= pc.clean_cycles_required
   AND ps.current_phase < 3) AS ready_to_advance
FROM lift.plan_state ps
CROSS JOIN lift.plan_config pc;

-- =============================================================
-- App-side change required (index.html):
--
-- Replace the anon Supabase client with an authenticated session.
-- The app must call supabase.auth.signInWithPassword() (or use a
-- pre-existing session token) before any DB calls.
--
-- Simplest approach for a single-user app: call signInWithPassword
-- at boot inside loadBootData() and gate all DB calls on the
-- returned session. The anon key in the config stays as-is; it's
-- only used for the initial auth handshake.
-- =============================================================
