---
name: progression-engine
description: Full detail on the lifting progression state machine, amber suppression, and exercise skipping
metadata:
  type: project
---

# Progression Engine

**Key functions:** `runProgressionEngine`, `progressionVariant`, `classicTargets`, `repFloor`

## Mode selection
Per exercise, chosen at runtime: if a 5 lb step is >20% of set-3 weight → **rep-ladder** (light loads; rep-based progression, weight advances manually). Otherwise → **classic catch-up** (state machine below).

## Classic catch-up state machine
Advance order: set3 first, then set2, then set1.
State sequence: `ready → catch_up_set2 → catch_up_set1 → ready`
Catch-up targets: set2 = `ceil(s3·0.9/5)·5`, set1 = `ceil(s3·0.8/5)·5`

Rep floor = `ceil(goal·0.8)`; ceiling = `goal+5`.
- **Success:** actual_reps ≥ goal on the evaluated set.
- **Stall:** 2 consecutive sessions under floor → deload set3 by 10% (round to 5), re-enter catch-up.
- **Increments:** 5 lb only.
- Skipped sets and bodyweight/optional exercises never advance progression or count as stalls.
- Progression frozen entirely while `in_deload` when `deload_freezes_progression` is true (read from `plan_config`).
- `progression_hold_until_phase` (front squats, single-leg bench squat = 3): all advances suppressed while `current_phase` < that value.

## Progression is opt-in
Weight advances only when user taps "Confirm progression" on set 3 (`APP.progressionReady`). The engine computes and displays the next weight but doesn't write without confirmation. Stall counting and deload regressions remain automatic. (`progressionReady` replaced the old `formHold` flag.)

## Amber suppression (knee-aware)
`isKneeLoading(ex)` substring-matches `ex.name` (lowercased) against: `['front squat', 'single-leg bench squat', 'romanian deadlift', 'push press']`.

When amber + knee-loading + user hit goal + confirmed: `runProgressionEngine` does an early `return` with **no DB write**. The progression state machine and failure counters are left exactly as-is. Stall counting (`underFloor` branch) still runs normally on amber days. Next green session proceeds from the same state as if the amber session never happened. The "Confirm progression" button is replaced with an amber-coloured note. All non-knee-loading exercises advance normally under amber.

## Exercise-level skipping
`skipWholeExercise(idx, reason)` logs all 3 sets as skipped and calls `finishExercise`.
- Main exercises: "Skip…" button → reason sheet (niggle / travel / other).
- Optional finishers: one-tap "Skip", no reason required.
- Niggle skips trigger `markNiggleFlare`.
