-- Migration 009: glute bridge -> single-leg glute bridge
--
-- The bilateral Glute bridge (a3000003) is deactivated, not renamed or deleted —
-- its session_sets history must keep reading as the bilateral exercise it was
-- logged as. A new unilateral exercise replaces it in the day-3 workout, seeded
-- light (20/20/20) so the engine climbs from clean unweighted form rather than
-- starting heavy.

UPDATE lift.exercises SET is_active = false WHERE id = 'a3000003-0000-0000-0000-000000000000';

INSERT INTO lift.exercises
  (id, name, gym_day, day_order, goal_reps, rest_short_seconds, rest_long_seconds, form_cue, is_bodyweight, is_optional, max_weight, is_active)
VALUES (
  'a3000006-0000-0000-0000-000000000000',
  'Single-leg glute bridge', 3, 3, 15, 60, 180,
  'Keep the pelvis level — don''t let the floating hip drop. Ribs down, no lumbar arch.',
  false, false, 80, true
);

-- user_id is NOT NULL with no useful default outside an authenticated request
-- context (auth.uid() is null when applying via migration) — set explicitly to
-- match the single existing user_id already in lift.exercise_state.
INSERT INTO lift.exercise_state (exercise_id, user_id, set1_weight, set2_weight, set3_weight, progression_state)
VALUES ('a3000006-0000-0000-0000-000000000000', '1438970f-eff7-4a02-906a-072acd711f86', 20, 20, 20, 'ready');
