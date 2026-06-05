-- Migration 003: enable Row Level Security + policies for the anon role
-- ---------------------------------------------------------------------------
-- The app talks to Supabase ONLY as the `anon` role (public key in index.html,
-- no auth flow). With RLS enabled and no policies, Postgres default-denies and
-- every query fails — this migration adds the policies that keep the app
-- working once RLS is on.
--
-- SECURITY NOTE: the anon key is public, so these permissive policies do NOT
-- make the data private — anyone with the key can do what the app can. This
-- migration only closes Supabase's "RLS off = wide open" default and is a
-- prerequisite for a real auth-based lockdown later (see bottom of file).
--
-- Edits done from the Supabase SQL editor run as the `postgres` role, which
-- BYPASSES RLS — so seeding/manual fixes keep working regardless of policies.
-- Views (v_readiness, v_phase_ready) can't have RLS; they keep working via the
-- existing SELECT grant to anon. No action needed for them.
--
-- Run this whole file in the Supabase SQL editor.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- READ-ONLY reference tables (app only SELECTs these; writes happen via SQL)
-- ---------------------------------------------------------------------------
ALTER TABLE lift.exercises   ENABLE ROW LEVEL SECURITY;
ALTER TABLE lift.cycle_plan  ENABLE ROW LEVEL SECURITY;
ALTER TABLE lift.plan_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY anon_read_exercises   ON lift.exercises
  FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY anon_read_cycle_plan  ON lift.cycle_plan
  FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY anon_read_plan_config ON lift.plan_config
  FOR SELECT TO anon, authenticated USING (true);

-- ---------------------------------------------------------------------------
-- READ/WRITE tables (the app mutates these at runtime)
--   exercise_state — SELECT + UPDATE (progression)
--   plan_state     — SELECT + UPDATE (cursor, deload, phase)
--   sessions       — SELECT + INSERT + UPDATE
--   session_sets   — SELECT + INSERT
--   daily_log      — SELECT + INSERT + UPDATE (check-in upsert, run/rehab toggles)
-- FOR ALL keeps every current and near-future client call working.
-- ---------------------------------------------------------------------------
ALTER TABLE lift.exercise_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE lift.plan_state     ENABLE ROW LEVEL SECURITY;
ALTER TABLE lift.sessions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE lift.session_sets   ENABLE ROW LEVEL SECURITY;
ALTER TABLE lift.daily_log      ENABLE ROW LEVEL SECURITY;

CREATE POLICY anon_all_exercise_state ON lift.exercise_state
  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY anon_all_plan_state ON lift.plan_state
  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY anon_all_sessions ON lift.sessions
  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY anon_all_session_sets ON lift.session_sets
  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY anon_all_daily_log ON lift.daily_log
  FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

-- ===========================================================================
-- OPTIONAL HARDENING (do NOT run unless you also add auth to the app)
-- ---------------------------------------------------------------------------
-- The above leaves the data publicly read/writable by design (no auth). To
-- actually lock it down for a single user:
--   1. Create one Supabase Auth user (email+password) and sign in from the app
--      so requests carry the `authenticated` role + a JWT.
--   2. Drop the `anon` grants in the policies above (keep only `authenticated`),
--      OR scope rows with `auth.uid()` if you add a user_id column per table.
--   3. Replace the embedded anon key usage with a real sign-in flow.
-- Until then, treat the database as public.
-- ===========================================================================
