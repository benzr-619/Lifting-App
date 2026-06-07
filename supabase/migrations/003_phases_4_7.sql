-- Migration 003: Extend rehab/run plan from 3 phases (24 days) to 7 phases (56 days).
-- Adds cycle_plan rows for days 25–56, relaxes two CHECK constraints, and updates v_phase_ready.

-- ----------------------------------------------------------
-- 1. Extend cycle_plan.day_number CHECK (1–24 → 1–56)
-- ----------------------------------------------------------
ALTER TABLE lift.cycle_plan DROP CONSTRAINT cycle_plan_day_number_check;
ALTER TABLE lift.cycle_plan ADD CONSTRAINT cycle_plan_day_number_check
  CHECK (day_number BETWEEN 1 AND 56);

-- ----------------------------------------------------------
-- 2. Extend plan_state.current_phase CHECK (1–3 → 1–7)
-- ----------------------------------------------------------
ALTER TABLE lift.plan_state DROP CONSTRAINT plan_state_current_phase_check;
ALTER TABLE lift.plan_state ADD CONSTRAINT plan_state_current_phase_check
  CHECK (current_phase BETWEEN 1 AND 7);

-- ----------------------------------------------------------
-- 3. Rebuild v_phase_ready (DROP + CREATE; OR REPLACE can't change expressions cleanly)
--    Change: current_phase < 3  →  current_phase < 7
-- ----------------------------------------------------------
DROP VIEW IF EXISTS lift.v_phase_ready;
CREATE VIEW lift.v_phase_ready AS
  SELECT
    ps.current_phase,
    ps.current_cycle_day,
    ps.clean_cycles_completed,
    pc.clean_cycles_required,
    ps.clean_cycles_completed >= pc.clean_cycles_required
      AND ps.current_phase < 7 AS ready_to_advance
  FROM lift.plan_state ps
  CROSS JOIN lift.plan_config pc;

-- ----------------------------------------------------------
-- 4. Seed days 25–56
--    Columns: day_number, run_miles, run_notes, target_cadence, is_lift_day, gym_notes,
--             rehab_exercise, rehab_timing
--
-- NOTE on deload_run_mile_cap: plan_config currently has this at 2.0 mi.
-- That cap is too aggressive for Phases 6–7 where easy days are 4–5 miles.
-- Raise it in the DB (via a future migration or direct update) when entering Phase 6.
-- The value is read from plan_config at runtime — no code change needed.
-- ----------------------------------------------------------
INSERT INTO lift.cycle_plan
  (day_number, run_miles, run_notes, target_cadence, is_lift_day, gym_notes, rehab_exercise, rehab_timing)
VALUES

  -- PHASE 4 — Days 25–32 (~22 mi/cycle) --------------------------------
  -- Goal: longer top-end runs, same 5 run days, prove Phase 3 gains held.
  -- New: eccentric single-leg calf raises, Copenhagen adduction plank, TKE with band.
  -- Drop: isometric pre-load as prescribed exercise (conditional only going forward).
  (25, 5.0, NULL, 180, true,  NULL,
   'Plyometric warm-up (3×10 single-leg hops)', 'before_run'),

  (26, 3.0, 'Consecutive-day run', 180, false, NULL,
   'Foot Core Strengthening (short foot + single-leg balance)', 'before_run'),

  (27, NULL, NULL, NULL, true,  NULL,
   'Weighted Lateral Step-Downs (3×12)', 'after_lift'),

  (28, 5.5, NULL, 180, false, NULL,
   'Plyometric warm-up (3×10 single-leg hops)', 'before_run'),

  (29, NULL, NULL, NULL, true,  NULL,
   'Copenhagen Adduction Plank (3×8–10/side)', 'after_lift'),

  (30, 4.0, NULL, 180, false, NULL,
   'Plyometric warm-up (3×10 single-leg hops)', 'before_run'),

  (31, 4.5, NULL, 180, true,  NULL,
   'Comprehensive lower limb mobility', 'standalone'),

  (32, NULL, NULL, NULL, true,  NULL,
   'Weighted Lateral Step-Downs (3×12)', 'after_lift'),

  -- PHASE 5 — Days 33–40 (~27.5 mi/cycle) --------------------------------
  -- Goal: 6th run day; triple consecutive-day block as key probe.
  -- New: soleus calf raise (bent-knee), banded hip flexion/psoas march, drop landings.
  -- Foot core becomes 2-min warm-up drill (not a dedicated rehab session).
  (33, 5.5, NULL, 180, true,  NULL,
   'Plyometric warm-up (3×10 single-leg hops)', 'before_run'),

  (34, 3.5, 'Consecutive-day run', 180, false, NULL,
   'Foot Core Strengthening (short foot + single-leg balance)', 'before_run'),

  (35, 4.0, 'Consecutive-day run — triple block', 180, false, NULL,
   'Light plyometric warm-up (3×10 single-leg hops)', 'before_run'),

  (36, NULL, NULL, NULL, true,  NULL,
   'Weighted Lateral Step-Downs (3×12)', 'after_lift'),

  (37, 6.0, NULL, 180, false, NULL,
   'Plyometric warm-up (3×10 single-leg hops)', 'before_run'),

  (38, 3.5, NULL, 180, true,  NULL,
   'Copenhagen Adduction Plank (3×8–10/side)', 'after_lift'),

  (39, NULL, NULL, NULL, true,  NULL,
   'Comprehensive lower limb mobility', 'standalone'),

  (40, 5.0, NULL, 180, false, NULL,
   'Foot Core Strengthening (short foot + single-leg balance)', 'before_run'),

  -- PHASE 6 — Days 41–48 (~30 mi/cycle) --------------------------------
  -- Goal: introduce strides (neuromuscular prep); long run to 7.5 mi.
  -- New: A-skips + high knees as drills, tibialis anterior work.
  -- Step-downs reduced to 1×/cycle (maintenance only); standalone isometrics gone.
  -- REMINDER: raise deload_run_mile_cap in plan_config before entering this phase.
  (41, 6.0, '6×20s strides at end of run', 180, true,  NULL,
   'Plyometric warm-up (3×10 single-leg hops)', 'before_run'),

  (42, 4.0, 'Consecutive-day run', 180, false, NULL,
   'Foot Core drill (short foot + single-leg balance)', 'before_run'),

  (43, NULL, NULL, NULL, true,  NULL,
   'Weighted Lateral Step-Downs (3×12) — maintenance, 1×/cycle', 'after_lift'),

  (44, 7.5, 'Long run', 180, false, NULL,
   'Plyometric warm-up (3×10 single-leg hops)', 'before_run'),

  (45, NULL, NULL, NULL, true,  NULL,
   'Copenhagen Adduction Plank (3×8–10/side)', 'after_lift'),

  (46, 5.0, 'Strides', 180, false, NULL,
   'A-skips + high knees 2×20m', 'before_run'),

  (47, 4.5, NULL, 180, true,  NULL,
   'Comprehensive lower limb mobility', 'standalone'),

  (48, 3.0, NULL, 180, false, NULL,
   'Foot Core drill (short foot + single-leg balance)', 'before_run'),

  -- PHASE 7 — Days 49–56 (~35.5 mi/cycle) --------------------------------
  -- Goal: one structured workout/cycle (fartlek); long run reaches 10 mi.
  -- "Rehab slot" is now pre-run activation (~8–10 min): mini-band lateral walks 2×15,
  -- banded hip flexion march 1×12/side, A-skips 2×20m, single-leg calf raises 1×10/side,
  -- short foot 30s/side. TKE kept as permanent 1-set maintenance item.
  -- REMINDER: raise deload_run_mile_cap in plan_config before entering this phase.
  (49, 6.0, NULL, 180, true,  NULL,
   'Pre-run activation (mini-band walks, hip march, A-skips, calf raises, short foot)', 'before_run'),

  (50, 4.5, 'Consecutive-day run', 180, false, NULL,
   'Pre-run activation (mini-band walks, hip march, A-skips, calf raises, short foot)', 'before_run'),

  (51, NULL, NULL, NULL, true,  NULL,
   'Copenhagen Adduction Plank (3×8–10/side)', 'after_lift'),

  (52, 7.0, 'fartlek: 6×3 min on / 2 min off', 180, false, NULL,
   'Pre-run activation (mini-band walks, hip march, A-skips, calf raises, short foot)', 'before_run'),

  (53, 4.5, NULL, 180, true,  NULL,
   'Lateral band walks maintenance (2×15)', 'after_lift'),

  (54, NULL, NULL, NULL, true,  NULL,
   'Comprehensive lower limb mobility', 'standalone'),

  (55, 10.0, 'Long run', 180, false, NULL,
   'Pre-run activation (mini-band walks, hip march, A-skips, calf raises, short foot)', 'before_run'),

  (56, 3.5, 'Shake-out', 180, true,  NULL,
   'Pre-run activation (mini-band walks, hip march, A-skips, calf raises, short foot)', 'before_run');
