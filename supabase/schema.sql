-- =============================================================
-- Lift App — Supabase Schema
-- All tables live in the `lift` schema to share a Supabase
-- instance cleanly with other apps (public schema untouched).
-- =============================================================

CREATE SCHEMA IF NOT EXISTS lift;

-- ----------------------------------------------------------
-- ENUM: progression state for the set catch-up state machine
-- ----------------------------------------------------------
CREATE TYPE lift.progression_state AS ENUM (
  'ready',           -- all sets at target; next success advances set3
  'catch_up_set2',   -- set3 just advanced; next success catches up set2
  'catch_up_set1'    -- set2 caught up; next success catches up set1
);

-- ----------------------------------------------------------
-- EXERCISES
-- Static config for each exercise. Weights and state are in
-- exercise_state. Supersets share a superset_group_id UUID;
-- is_superset_anchor=true marks the exercise that drives weight.
-- is_optional=true marks finishers — never block session
-- completion and never feed the stall/deload logic.
-- progression_hold_until_phase: if set, suppress ALL weight/state
--   advances while current_phase < this value. Used for exercises
--   performed at limited ROM in early phases (front squats and
--   single-leg bench squats in phases 1–2 — hitting goal reps at
--   partial depth is not a true progression signal; unlock at phase 3
--   when full ROM resumes). NULL = no hold, progress normally.
-- ----------------------------------------------------------
CREATE TABLE lift.exercises (
  id                           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name                         TEXT        NOT NULL,
  gym_day                      SMALLINT    NOT NULL CHECK (gym_day IN (1, 2, 3)),
  day_order                    SMALLINT    NOT NULL,   -- position within the day (supersets share same value)
  goal_reps                    SMALLINT    NOT NULL,
  increment_lbs                SMALLINT    NOT NULL DEFAULT 5,
  rest_short_seconds           SMALLINT    NOT NULL DEFAULT 60,   -- rest between set 1 → 2
  rest_long_seconds            SMALLINT    NOT NULL DEFAULT 180,  -- rest between set 2 → 3
  form_cue                     TEXT,
  is_bodyweight                BOOLEAN     NOT NULL DEFAULT false, -- no weight tracking if true
  is_optional                  BOOLEAN     NOT NULL DEFAULT false, -- finisher: skippable, excluded from progression
  superset_group_id            UUID,                  -- NULL = not a superset
  is_superset_anchor           BOOLEAN     NOT NULL DEFAULT false,
  progression_hold_until_phase SMALLINT,              -- NULL = always progress; 3 = hold until phase 3
  created_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX ON lift.exercises (gym_day, day_order);

-- ----------------------------------------------------------
-- EXERCISE STATE
-- One row per exercise. Tracks current weights and where we
-- are in the progression state machine.
-- set_weight columns are NULL for bodyweight exercises.
-- ----------------------------------------------------------
CREATE TABLE lift.exercise_state (
  id                   UUID                   PRIMARY KEY DEFAULT gen_random_uuid(),
  exercise_id          UUID                   NOT NULL UNIQUE REFERENCES lift.exercises (id) ON DELETE CASCADE,
  set1_weight          SMALLINT,
  set2_weight          SMALLINT,
  set3_weight          SMALLINT,
  progression_state    lift.progression_state NOT NULL DEFAULT 'ready',
  consecutive_failures SMALLINT               NOT NULL DEFAULT 0,
  updated_at           TIMESTAMPTZ            NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------
-- SESSIONS
-- One row per gym visit. Links sets to a date and gym day.
-- ----------------------------------------------------------
CREATE TABLE lift.sessions (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_day      SMALLINT    NOT NULL CHECK (gym_day IN (1, 2, 3)),
  started_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  notes        TEXT
);

CREATE INDEX ON lift.sessions (gym_day);
CREATE INDEX ON lift.sessions (started_at DESC);

-- ----------------------------------------------------------
-- SESSION SETS
-- The actual logged data: weight and reps for every set in
-- every session. target_reps is snapshotted at log time so
-- history stays accurate even after progression.
--
-- A set can be SKIPPED (travel/no equipment, or an acute
-- niggle being protected). A skipped set carries no reps and
-- must NOT advance progression or count toward stalls.
--   set_status='skipped'  → actual_reps NULL, skip_reason set
--   set_status='completed'→ actual_reps NOT NULL, skip_reason NULL
-- skip_reason 'niggle' is pain-driven (breaks a clean cycle and
-- feeds the coach); 'travel_equipment' is neutral.
-- ----------------------------------------------------------
CREATE TABLE lift.session_sets (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id   UUID        NOT NULL REFERENCES lift.sessions (id) ON DELETE CASCADE,
  exercise_id  UUID        NOT NULL REFERENCES lift.exercises (id),
  set_number   SMALLINT    NOT NULL CHECK (set_number IN (1, 2, 3)),
  weight_lbs   SMALLINT,   -- NULL for bodyweight
  target_reps  SMALLINT    NOT NULL,
  actual_reps  SMALLINT,   -- NULL when skipped
  good_form    BOOLEAN,
  set_status   TEXT        NOT NULL DEFAULT 'completed'
    CHECK (set_status IN ('completed', 'skipped')),
  skip_reason  TEXT
    CHECK (skip_reason IN ('travel_equipment', 'niggle', 'other')),
  logged_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (session_id, exercise_id, set_number),
  CHECK (
    (set_status = 'completed' AND actual_reps IS NOT NULL AND skip_reason IS NULL)
    OR
    (set_status = 'skipped'   AND actual_reps IS NULL     AND skip_reason IS NOT NULL)
  )
);

CREATE INDEX ON lift.session_sets (session_id);
CREATE INDEX ON lift.session_sets (exercise_id);

-- ----------------------------------------------------------
-- CYCLE PLAN
-- Reference data for the 24 plan days (3 phases × 8-day cycle).
-- The cycle is advanced PER COMPLETED SESSION (like the 3-day
-- lift split), not by calendar — see plan_state. Incidental
-- life rest days are fine and don't break a cycle.
-- is_lift_day = true means a gym session is prescribed for this
--   rehab day; WHICH gym day (1/2/3) is tracked independently in
--   plan_state.current_gym_day so the rotation is never coupled
--   to the rehab phase.
-- run_miles NULL = no run that day.
-- ROM progression (45°/60°/full per phase) is held by Ben, not
-- stored. target_cadence is the personalized step-rate target.
-- ----------------------------------------------------------
CREATE TABLE lift.cycle_plan (
  id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  day_number      SMALLINT     NOT NULL UNIQUE CHECK (day_number BETWEEN 1 AND 24),
  run_miles       DECIMAL(4,1),             -- NULL = no run
  run_notes       TEXT,                     -- e.g. consecutive-day trial markers
  target_cadence  SMALLINT,                 -- steps/min target on run days (NULL = no run)
  is_lift_day     BOOLEAN      NOT NULL DEFAULT false,  -- true = gym session prescribed
  gym_notes       TEXT,
  rehab_exercise  TEXT         NOT NULL,
  rehab_timing    TEXT         NOT NULL DEFAULT 'before_lift'
    CHECK (rehab_timing IN ('before_run', 'before_lift', 'after_lift', 'after_run', 'standalone'))
);

-- ----------------------------------------------------------
-- PLAN STATE (singleton)
-- Tracks position in the rehab plan as a CURSOR, advanced per
-- completed session rather than by date:
--   current_cycle_day 1–8  → maps to cycle_plan via
--     day_number = (current_phase-1)*8 + current_cycle_day
--   current_gym_day 1–3    → which lift to do next; advances
--     independently of the rehab cycle (1→2→3→1→2→3 forever).
--     A phase regression or deload never resets this.
--   current_cycle_rest_days counts calendar days inside the
--     current cycle where no session was logged (life/travel).
--
-- A FLARE = any of:
--   • morning check-in: knee_pain_level >= plan_config.pain_dirty_threshold
--   • morning check-in: joint_fullness = true (positive sweep test)
--   • niggle-skip on a session set
--   • post-run capture: run_outcome = 'flagged' (sharp pain, altered
--       biomechanics, or early abort during a run — triggers immediately,
--       same as a morning pain reading, without waiting for next morning)
-- Because morning check-ins are morning-only, a morning pain reading
-- already means symptoms did not settle overnight — no next-day comparison
-- needed. Flares are handled IMMEDIATELY on the triggering event (not at
-- cycle end):
--   1st flare in the phase → DELOAD (relative rest, not full rest).
--     Set in_deload = true, deload_started_on = today; the deload acts
--     as a modifier on the prescription (see plan_config: cap run
--     distance, suppress plyometrics, freeze lift progression; KEEP the
--     analgesic isometrics + mobility). Exit deload when a check-in is
--     clean (pain <= 3, no swelling) AND >= plan_config.flare_min_rest_days
--     have passed since deload_started_on; then resume the SAME
--     current_cycle_day. The cycle is marked not-clean
--     (current_cycle_clean = false) and phase_flare_count += 1.
--   Nth flare where phase_flare_count >= plan_config.flares_before_regress
--     and current_phase > 1 → step back one phase: current_phase -= 1,
--     current_cycle_day = 1, counters reset (see below).
-- A travel/equipment skip is NOT a flare, but the day it covers still
-- counts toward current_cycle_rest_days if no session was completed.
--
-- On rolling current_cycle_day 8→1, evaluate the finished cycle:
--   CLEAN      (current_cycle_clean = true AND current_cycle_rest_days
--              <= plan_config.max_rest_days_per_cycle):
--              clean_cycles_completed += 1; phase_flare_count = 0;
--              if clean_cycles_completed >= plan_config.clean_cycles_required
--              and current_phase < 3 → advance phase, counter → 0.
--   NOT CLEAN  (a flare happened this cycle, or 3+ rest days):
--              clean_cycles_completed = 0; stay in phase.
--   Then reset current_cycle_clean = true, current_cycle_rest_days = 0.
-- (On a phase regression also reset clean_cycles_completed = 0,
--  phase_flare_count = 0, current_cycle_clean = true, rest_days = 0.)
-- ----------------------------------------------------------
CREATE TABLE lift.plan_state (
  id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  singleton_guard         BOOLEAN     NOT NULL DEFAULT true UNIQUE,  -- enforces one row
  current_phase           SMALLINT    NOT NULL DEFAULT 1 CHECK (current_phase BETWEEN 1 AND 3),
  current_cycle_day       SMALLINT    NOT NULL DEFAULT 1 CHECK (current_cycle_day BETWEEN 1 AND 8),
  current_gym_day         SMALLINT    NOT NULL DEFAULT 1 CHECK (current_gym_day IN (1, 2, 3)),
  current_cycle_rest_days SMALLINT    NOT NULL DEFAULT 0,      -- no-session calendar days this cycle
  clean_cycles_completed  SMALLINT    NOT NULL DEFAULT 0,
  current_cycle_clean     BOOLEAN     NOT NULL DEFAULT true,   -- flips false on a flare this cycle
  phase_flare_count       SMALLINT    NOT NULL DEFAULT 0,      -- flares in this phase since last clean cycle
  in_deload               BOOLEAN     NOT NULL DEFAULT false,  -- relative-rest mode after a flare
  deload_started_on       DATE,                                -- for enforcing flare_min_rest_days floor
  plan_started_at         DATE        NOT NULL DEFAULT CURRENT_DATE,
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------
-- PLAN CONFIG (singleton)
-- Tunable thresholds for the phase-advance gate so the rules
-- can change without touching app code.
--   pain_dirty_threshold  : knee_pain_level >= this marks the
--                           cycle dirty (1–5 scale; default 4).
--   clean_cycles_required : consecutive clean cycles needed to
--                           advance a phase (default 2).
--   max_rest_days_per_cycle: rest days allowed before a cycle is
--                           "incomplete" (default 2; 3+ = incomplete).
--   forgive_travel_skip   : travel/equipment skips don't make a
--                           cycle flare (niggle skips always do).
-- Flare / deload knobs:
--   flares_before_regress : flares in a phase (since last clean
--                           cycle) before a phase regression (default 2).
--   flare_min_rest_days   : minimum days in deload before you can
--                           exit even if symptoms cleared (default 2).
--   deload_run_mile_cap   : max run distance while deloaded (default 2.0).
--   deload_freezes_progression: hold lift weights (no advances) while
--                           deloaded (default true).
--   deload_suppress_plyo  : replace plyometric rehab with the isometric
--                           pre-load while deloaded (default true).
-- ----------------------------------------------------------
CREATE TABLE lift.plan_config (
  id                         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  singleton_guard            BOOLEAN      NOT NULL DEFAULT true UNIQUE,
  pain_dirty_threshold       SMALLINT     NOT NULL DEFAULT 4 CHECK (pain_dirty_threshold BETWEEN 1 AND 5),
  clean_cycles_required      SMALLINT     NOT NULL DEFAULT 2 CHECK (clean_cycles_required >= 1),
  max_rest_days_per_cycle    SMALLINT     NOT NULL DEFAULT 2 CHECK (max_rest_days_per_cycle >= 0),
  forgive_travel_skip        BOOLEAN      NOT NULL DEFAULT true,
  flares_before_regress      SMALLINT     NOT NULL DEFAULT 2 CHECK (flares_before_regress >= 1),
  flare_min_rest_days        SMALLINT     NOT NULL DEFAULT 2 CHECK (flare_min_rest_days >= 0),
  deload_run_mile_cap        DECIMAL(4,1) NOT NULL DEFAULT 2.0,
  deload_freezes_progression BOOLEAN      NOT NULL DEFAULT true,
  deload_suppress_plyo       BOOLEAN      NOT NULL DEFAULT true
);

-- ----------------------------------------------------------
-- DAILY LOG  (the morning check-in + post-run capture)
-- One row per calendar day. Pain + swelling are the inputs to
-- the readiness gate and the clean-cycle evaluation.
--   knee_pain_level (1–5), captured via a behavioral prompt:
--     1–2 noticed at most, no effect, gone by morning
--     3   felt during/after but settled within 24h
--     4–5 changed how you moved/ran, or lingered to next morning
--   joint_fullness: result of the patellar sweep test (swelling).
-- plan_phase / plan_cycle_day snapshot the cursor on that date.
--
-- POST-RUN OUTCOME (recorded immediately after a run):
--   run_outcome = 'clean'   → pain-free or mild discomfort; fine to continue.
--   run_outcome = 'flagged' → any of: sharp pain (>4), altered biomechanics,
--                             or had to abort early. Treated as a FLARE
--                             immediately — triggers deloading the same way a
--                             morning pain≥4 or positive sweep test does.
--   NULL                    → no run performed that day.
-- ----------------------------------------------------------
CREATE TABLE lift.daily_log (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  log_date          DATE        NOT NULL UNIQUE,
  plan_phase        SMALLINT    CHECK (plan_phase BETWEEN 1 AND 3),
  plan_cycle_day    SMALLINT    CHECK (plan_cycle_day BETWEEN 1 AND 8),
  run_completed     BOOLEAN     NOT NULL DEFAULT false,
  run_actual_miles  DECIMAL(4,1),
  run_outcome       TEXT        CHECK (run_outcome IN ('clean', 'flagged')),
  rehab_completed   BOOLEAN     NOT NULL DEFAULT false,
  knee_pain_level   SMALLINT    CHECK (knee_pain_level BETWEEN 1 AND 5),
  joint_fullness    BOOLEAN,    -- TRUE = swelling present (sweep test positive)
  notes             TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX ON lift.daily_log (log_date DESC);

-- ----------------------------------------------------------
-- VIEW: today's readiness gate (green / amber / red)
-- Reads the most recent check-in. The app shows this before a
-- run or lift; amber = hold loads/mileage flat, red = regress.
-- ----------------------------------------------------------
CREATE OR REPLACE VIEW lift.v_readiness AS
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

-- ----------------------------------------------------------
-- VIEW: phase-advance gate
-- Boolean the app reads to decide whether to offer moving to
-- the next 8-day cycle/phase.
-- ----------------------------------------------------------
CREATE OR REPLACE VIEW lift.v_phase_ready AS
SELECT
  ps.current_phase,
  ps.current_cycle_day,
  ps.clean_cycles_completed,
  pc.clean_cycles_required,
  (ps.clean_cycles_completed >= pc.clean_cycles_required
   AND ps.current_phase < 3) AS ready_to_advance
FROM lift.plan_state ps
CROSS JOIN lift.plan_config pc;
