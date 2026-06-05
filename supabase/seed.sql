-- =============================================================
-- Lift App — Seed Data
-- Run after schema.sql. Populates exercises, exercise_state,
-- cycle_plan, plan_state, and plan_config.
--
-- Weights are Ben's CURRENT working loads (logged Set 1/2/3
-- columns of the updated Strength_Tracking_Ramping_Sets sheet).
--
-- Progression state computed from the weights:
--   threshold:  5 / set3 > 0.20  → rep_ladder → READY
--   classic:    target_s2 = ceil(s3 * 0.9 / 5) * 5
--               target_s1 = ceil(s3 * 0.8 / 5) * 5
--               s2 < target_s2  → catch_up_set2
--               s1 < target_s1  → catch_up_set1
--               else            → ready
-- =============================================================

-- Hard-coded UUIDs so exercise_state inserts can reference them.
-- Superset group for Lateral Raise + Curl (Day 2, position 3):
-- superset_group_id = 'b0000000-0000-0000-0000-000000000001'

-- ----------------------------------------------------------
-- EXERCISES
-- ----------------------------------------------------------
INSERT INTO lift.exercises
  (id, name, gym_day, day_order, goal_reps, form_cue, is_bodyweight, is_optional, superset_group_id, is_superset_anchor, progression_hold_until_phase)
VALUES

  -- DAY 1 ------------------------------------------------
  (
    'a1000001-0000-0000-0000-000000000000',
    'Single-leg RDL', 1, 1, 10,
    'Soft knee, heavy heel. Keep hips square — don''t let the floating hip rotate up.',
    false, false, NULL, false, NULL
  ),
  (
    'a1000002-0000-0000-0000-000000000000',
    'Bench press', 1, 2, 12,
    'Feet through the floor. Drive your feet down to create a stable base.',
    false, false, NULL, false, NULL
  ),
  (
    'a1000003-0000-0000-0000-000000000000',
    'Renegade rows', 1, 3, 10,
    'Wide feet, quiet hips. Imagine a bowl of water on your lower back — row without spilling.',
    false, false, NULL, false, NULL
  ),
  (
    'a1000004-0000-0000-0000-000000000000',
    'Russian twists', 1, 4, 12,
    'Rotate the ribs, not just the arms. Follow the weight with your eyes and chest.',
    false, false, NULL, false, NULL
  ),
  -- Day 1 finisher
  (
    'a1000005-0000-0000-0000-000000000000',
    'Lateral lunge', 1, 5, 12,
    'Push the hips back into the working side, knee tracking over the foot. Keep the trailing leg straight.',
    false, true, NULL, false, NULL
  ),

  -- DAY 2 ------------------------------------------------
  -- progression_hold_until_phase=3: limited ROM (partial depth) in phases 1–2
  -- hitting goal reps at partial depth is not a true progression signal
  (
    'a2000001-0000-0000-0000-000000000000',
    'Single-leg bench squat', 2, 1, 10,
    'Knee over the shoelaces. Sit back — knee must not cave inward.',
    false, false, NULL, false, 3
  ),
  (
    'a2000002-0000-0000-0000-000000000000',
    'DB push press', 2, 2, 8,
    'Zip up your core. Don''t let your ribcage flare or back arch on the drive.',
    false, false, NULL, false, NULL
  ),
  -- Lateral raise is the superset anchor (drives weight for the pair)
  (
    'a2000003-0000-0000-0000-000000000000',
    'Lateral raise', 2, 3, 15,
    'Shoulders down and back. Keep a long neck — don''t let traps take over. Controlled descent.',
    false, false, 'b0000000-0000-0000-0000-000000000001', true, NULL
  ),
  -- Curl matches the anchor''s weight but its own rep target (can''t hit 15 at this load)
  (
    'a2000004-0000-0000-0000-000000000000',
    'Curl', 2, 3, 13,
    'Full range, controlled descent. Squeeze at the top. Don''t swing.',
    false, false, 'b0000000-0000-0000-0000-000000000001', false, NULL
  ),
  (
    'a2000005-0000-0000-0000-000000000000',
    'Plank with shoulder taps', 2, 4, 12,
    'No-wiggle zone. Lift your hand so slowly a bystander wouldn''t see your hips move.',
    true, false, NULL, false, NULL
  ),
  -- Day 2 finisher
  (
    'a2000006-0000-0000-0000-000000000000',
    'Y raise', 2, 5, 15,
    'Thumbs up, arms to a Y. Initiate from the lower traps — light load, long levers.',
    false, true, NULL, false, NULL
  ),

  -- DAY 3 ------------------------------------------------
  -- progression_hold_until_phase=3: limited ROM (partial depth) in phases 1–2
  -- hitting goal reps at partial depth is not a true progression signal
  (
    'a3000001-0000-0000-0000-000000000000',
    'Front squats', 3, 1, 10,
    'Elbows high, knees out. High elbows keep the weight off kneecaps and onto quads/abs.',
    false, false, NULL, false, 3
  ),
  (
    'a3000002-0000-0000-0000-000000000000',
    'Bent-over rows', 3, 2, 10,
    'Squeeze the oranges in your armpits. Pull with elbows, not hands. Spine flat like a tabletop.',
    false, false, NULL, false, NULL
  ),
  (
    'a3000003-0000-0000-0000-000000000000',
    'Glute bridge', 3, 3, 15,
    'Ribs down, chin tucked. Squeeze glutes at the top. Shins perpendicular. Don''t arch the back.',
    false, false, NULL, false, NULL
  ),
  (
    'a3000004-0000-0000-0000-000000000000',
    'Tricep extension', 3, 4, 15,
    'Statue elbows. Upper arm fixed in space — only the forearm moves. Elbows don''t flare.',
    false, false, NULL, false, NULL
  ),
  -- Day 3 finisher
  (
    'a3000005-0000-0000-0000-000000000000',
    'Ab roller', 3, 5, 10,
    'Ribs down, glutes squeezed — roll out only as far as you can keep the low back from sagging.',
    true, true, NULL, false, NULL
  );


-- ----------------------------------------------------------
-- EXERCISE STATE
-- Weights = current logged Set 1/2/3. State computed (see header).
-- ----------------------------------------------------------
INSERT INTO lift.exercise_state
  (exercise_id, set1_weight, set2_weight, set3_weight, progression_state)
VALUES

  -- Single-leg RDL: 60/70/75
  --   5/75 = 6.7% → classic. t_s2=70 (✓), t_s1=60 (✓) → ready
  ('a1000001-0000-0000-0000-000000000000', 60, 70, 75, 'ready'),

  -- Bench press: 45/50/55
  --   5/55 = 9.1% → classic. t_s2=50 (✓), t_s1=45 (✓) → ready
  ('a1000002-0000-0000-0000-000000000000', 45, 50, 55, 'ready'),

  -- Renegade rows: 20/25/25
  --   5/25 = 20% → classic (boundary). t_s2=25 (✓), t_s1=20 (✓) → ready
  ('a1000003-0000-0000-0000-000000000000', 20, 25, 25, 'ready'),

  -- Russian twists: 25/30/30
  --   5/30 = 16.7% → classic. t_s2=30 (✓), t_s1=25 (✓) → ready
  ('a1000004-0000-0000-0000-000000000000', 25, 30, 30, 'ready'),

  -- Lateral lunge (finisher): 30/30/30
  --   5/30 = 16.7% → classic. t_s2=30 (✓), t_s1=25 (✓) → ready
  ('a1000005-0000-0000-0000-000000000000', 30, 30, 30, 'ready'),

  -- Single-leg bench squat: 20/25/30
  --   5/30 = 16.7% → classic. t_s2=30 → s2=25 < 30 → catch_up_set2
  ('a2000001-0000-0000-0000-000000000000', 20, 25, 30, 'catch_up_set2'),

  -- DB push press: 45/50/55
  --   5/55 = 9.1% → classic. t_s2=50 (✓), t_s1=45 (✓) → ready
  ('a2000002-0000-0000-0000-000000000000', 45, 50, 55, 'ready'),

  -- Lateral raise: 10/10/15
  --   5/15 = 33% > 20% → rep ladder → ready
  ('a2000003-0000-0000-0000-000000000000', 10, 10, 15, 'ready'),

  -- Curl: 10/10/15
  --   5/15 = 33% > 20% → rep ladder → ready
  ('a2000004-0000-0000-0000-000000000000', 10, 10, 15, 'ready'),

  -- Plank with shoulder taps: bodyweight
  ('a2000005-0000-0000-0000-000000000000', NULL, NULL, NULL, 'ready'),

  -- Y raise (finisher): 5/5/5
  --   5/5 = 100% > 20% → rep ladder → ready
  ('a2000006-0000-0000-0000-000000000000', 5, 5, 5, 'ready'),

  -- Front squats: 55/60/70
  --   5/70 = 7.1% → classic. t_s2=65 → s2=60 < 65 → catch_up_set2
  ('a3000001-0000-0000-0000-000000000000', 55, 60, 70, 'catch_up_set2'),

  -- Bent-over rows: 40/40/45
  --   5/45 = 11.1% → classic. t_s2=45 → s2=40 < 45 → catch_up_set2
  ('a3000002-0000-0000-0000-000000000000', 40, 40, 45, 'catch_up_set2'),

  -- Glute bridge: 60/70/75
  --   5/75 = 6.7% → classic. t_s2=70 (✓), t_s1=60 (✓) → ready
  ('a3000003-0000-0000-0000-000000000000', 60, 70, 75, 'ready'),

  -- Tricep extension: 40/40/45
  --   5/45 = 11.1% → classic. t_s2=45 → s2=40 < 45 → catch_up_set2
  ('a3000004-0000-0000-0000-000000000000', 40, 40, 45, 'catch_up_set2'),

  -- Ab roller (finisher): bodyweight
  ('a3000005-0000-0000-0000-000000000000', NULL, NULL, NULL, 'ready');


-- ----------------------------------------------------------
-- CYCLE PLAN (24 days across 3 phases)
-- Phase 1: days 1–8, Phase 2: days 9–16, Phase 3: days 17–24.
-- Advanced per completed session (see plan_state), not by date.
-- target_cadence 180 on run days (personalized: +9.8% over
-- Ben's natural 164). rehab_timing from the sheet's Before/After.
-- ----------------------------------------------------------
INSERT INTO lift.cycle_plan
  (day_number, run_miles, run_notes, target_cadence, is_lift_day, gym_notes, rehab_exercise, rehab_timing)
VALUES

  -- PHASE 1 — Days 1–8 --------------------------------
  (1,  3.0, NULL, 180, true,  NULL,
   '5×45s Isometric Knee Pre-Load', 'before_run'),

  (2,  NULL, NULL, NULL, true,  NULL,
   'Foot Core Strengthening (short foot + single-leg balance)', 'before_lift'),

  (3,  3.0, NULL, 180, false, NULL,
   '5×45s Isometric Knee Pre-Load', 'before_run'),

  (4,  NULL, NULL, NULL, true,  NULL,
   'Heavy Goblet Lateral Band Walks (3×15)', 'after_lift'),

  (5,  3.5, NULL, 180, false, NULL,
   '5×45s Isometric Knee Pre-Load', 'before_run'),

  (6,  NULL, NULL, NULL, true,  NULL,
   'Foot Core Strengthening (short foot + single-leg balance)', 'before_lift'),

  (7,  3.5, NULL, 180, false, NULL,
   '5×45s Isometric Knee Pre-Load', 'before_run'),

  (8,  NULL, NULL, NULL, true,  NULL,
   'Heavy Goblet Lateral Band Walks (3×15)', 'after_lift'),

  -- PHASE 2 — Days 9–16 --------------------------------
  (9,  4.0, NULL, 180, true,  NULL,
   '5×45s Isometric Knee Pre-Load', 'before_run'),

  (10, 2.0, 'Consecutive-day trial', 180, false, NULL,
   'Foot Core Strengthening (short foot + single-leg balance)', 'before_run'),

  (11, NULL, NULL, NULL, true,  NULL,
   'Heavy Goblet Lateral Band Walks (3×15)', 'after_lift'),

  (12, 3.5, NULL, 180, false, NULL,
   '5×45s Isometric Knee Pre-Load', 'before_run'),

  (13, NULL, NULL, NULL, true,  NULL,
   'Weighted Lateral Step-Downs (3×12)', 'after_lift'),

  (14, 4.0, NULL, 180, false, NULL,
   '5×45s Isometric Knee Pre-Load', 'before_run'),

  (15, NULL, NULL, NULL, true,  NULL,
   'Heavy Goblet Lateral Band Walks (3×15)', 'after_lift'),

  (16, 3.5, NULL, 180, false, NULL,
   '5×45s Isometric Knee Pre-Load', 'before_run'),

  -- PHASE 3 — Days 17–24 --------------------------------
  (17, 4.5, NULL, 180, true,  NULL,
   'High-speed plyometric warm-up (3×10 single-leg hops)', 'before_run'),

  (18, 2.5, 'Consecutive-day run', 180, false, NULL,
   'Foot Core Strengthening (short foot + single-leg balance)', 'before_run'),

  (19, NULL, NULL, NULL, true,  NULL,
   'Single-leg squat to box with knee valgus visual control (3×10)', 'after_lift'),

  (20, 3.5, NULL, 180, false, NULL,
   'High-speed plyometric warm-up (3×10 bounding drills)', 'before_run'),

  (21, 3.0, 'Consecutive-day run', 180, true,  NULL,
   'Heavy Goblet Lateral Band Walks (3×15)', 'after_lift'),

  (22, NULL, NULL, NULL, false, NULL,
   'Comprehensive lower limb mobility', 'standalone'),

  (23, 4.0, NULL, 180, true,  NULL,
   'High-speed plyometric warm-up (3×10 single-leg hops)', 'before_run'),

  (24, NULL, NULL, NULL, true,  NULL,
   'Weighted Lateral Step-Downs (3×12)', 'after_lift');


-- ----------------------------------------------------------
-- PLAN STATE (singleton) — start of the plan.
-- ----------------------------------------------------------
INSERT INTO lift.plan_state
  (current_phase, current_cycle_day, current_gym_day, current_cycle_rest_days, clean_cycles_completed, current_cycle_clean, plan_started_at)
VALUES (1, 1, 3, 0, 0, true, CURRENT_DATE);

-- ----------------------------------------------------------
-- PLAN CONFIG (singleton) — gate thresholds (all tunable).
--   pain >= 4 (or swelling/niggle) flares a cycle; need 2
--   consecutive clean cycles to advance; 3+ rest days makes a
--   cycle incomplete; travel/equipment skips don't flare a cycle.
--   A flare triggers DELOAD (cap runs at 2.0 mi, freeze lift
--   progression, drop plyos, keep isometrics) for >= 2 days until
--   symptoms clear; 2nd flare in a phase regresses a phase.
-- ----------------------------------------------------------
INSERT INTO lift.plan_config
  (pain_dirty_threshold, clean_cycles_required, max_rest_days_per_cycle, forgive_travel_skip,
   flares_before_regress, flare_min_rest_days, deload_run_mile_cap, deload_freezes_progression, deload_suppress_plyo)
VALUES (4, 2, 2, true,
   2, 2, 2.0, true, true);
