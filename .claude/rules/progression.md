---
name: progression-engine
description: Full detail on the lifting progression state machine, amber suppression, and exercise skipping
metadata:
  type: project
---

# Progression Engine

**Key functions:** `runProgressionEngine`, `progressionVariant`, `classicTargets`, `repFloor`

## Mode selection
Per exercise, chosen at runtime via `progressionVariant(set3_weight)`: if a 5 lb step is >20% of set-3 weight → **rep-ladder**. Otherwise → **classic catch-up**.

Classic threshold: set3 must reach **25 lbs** before auto-progression kicks in.

## `progression_type` column
`exercises.progression_type` (TEXT, default `'weight'`) gates alternate engines:
- `'weight'` → classic/rep-ladder logic (all exercises by default)
- `'stance'` → `runStanceProgression` (Plank with shoulder taps); stance codes stored in set1/2/3_weight: `1` = shoulder width, `2` = feet together
- Bodyweight exercises (`is_bodyweight = true`) exit `runProgressionEngine` early — no progression regardless of type. Ab roller is the example.

## Finishers
Optional exercises (`is_optional = true`) **do** run through the full progression engine — the old `is_optional` guard was removed. Only ab roller is exempt (bodyweight). Lateral lunge = classic. Y raise = rep-ladder (5 lbs currently).

## Rep-ladder state machine
When `progressionVariant` returns `'rep_ladder'` and `progState === 'ready'`:
- **Ceiling** = `goal_reps + 5`. Hitting ceiling on set 3 + confirm → advance set3 weight by 5 lbs, enter `catch_up_set2`.
- Below ceiling but ≥ goal → stay `ready`, no weight change.
- `catch_up_set2` / `catch_up_set1` in rep-ladder fall through to **classic** catch-up logic.
- `pendingReps` pre-filled with ceiling (not goal) for rep-ladder exercises so the target is visible at the gym.
- Hint on set 3 shows: `"Hit <ceiling> reps on set 3 → advance to <next> lbs"`.

## Classic catch-up state machine
Advance order: set3 first, then set2, then set1.
State sequence: `ready → catch_up_set2 → catch_up_set1 → ready`
Catch-up targets: set2 = `ceil(s3·0.9/5)·5`, set1 = `ceil(s3·0.8/5)·5`

Rep floor = `ceil(goal·0.8)`; ceiling = `goal+5`.
- **Success:** actual_reps ≥ goal on the evaluated set.
- **Stall:** 2 consecutive sessions under floor → deload set3 by 10% (round to 5), re-enter catch-up.
- **Increments:** 5 lb only.
- Skipped sets and bodyweight exercises never advance progression or count as stalls.
- Progression frozen entirely while `in_deload` when `deload_freezes_progression` is true (read from `plan_config`).
- `progression_hold_until_phase` (front squats, single-leg bench squat = 3): all advances suppressed while `current_phase` < that value.

## Stance progression (`runStanceProgression`)
Used when `ex.progression_type === 'stance'`. Stance code in weight fields: 1 = shoulder width, 2 = feet together.
- `catch_up_set2`: evaluated set = set 2. On success + confirm → set2_weight = set3_weight, move to `catch_up_set1`.
- `catch_up_set1`: evaluated set = set 1. On success + confirm → set1_weight = set3_weight, move to `ready`.
- `ready`: all sets at max stance, nothing further.
- No stall/deload logic for stance.

## Progression is opt-in
Weight (and stance) advances only when user taps "Confirm progression" on set 3 (`APP.progressionReady`). Stall counting and deload regressions remain automatic. Rep-ladder exercises show the confirm button (it advances weight when ceiling is hit). `progressionHint()` drives the button label.

## Superset gotcha
`finishExercise` skips **all** exercises sharing the same `superset_group_id` as the just-finished exercise, not just +1. Without this, the workout stalls on the un-logged partner exercise.

## Amber suppression (knee-aware)
`isKneeLoading(ex)` substring-matches `ex.name` (lowercased) against: `['front squat', 'single-leg bench squat', 'romanian deadlift', 'push press']`.

When amber + knee-loading + user hit goal + confirmed: early `return` with **no DB write**. Stall counting still runs. Stance and non-knee-loading exercises are unaffected.

## Exercise-level skipping
`skipWholeExercise(idx, reason)` logs all 3 sets as skipped and calls `finishExercise`.
- Main exercises: "Skip…" button → reason sheet (niggle / travel / other).
- Optional finishers: one-tap "Skip", no reason required.
- Niggle skips trigger `markNiggleFlare`.
