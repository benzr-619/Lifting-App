---
name: progression-engine
description: Full detail on the lifting progression state machine, amber suppression, and exercise skipping
metadata:
  type: project
---

# Progression Engine

**Key functions:** `runProgressionEngine`, `progressionVariant`, `classicTargets`, `repFloor`, `repCeiling`, `computeProgressionStep`

## Shared progression math (`computeProgressionStep`)
The catch-up target formulas (`classicTargets`), rep floor/ceiling (`repFloor`/`repCeiling`), and the 2-consecutive-under-floor stall/deload detection are implemented once, in `computeProgressionStep` — a pure, storage-agnostic function shared by the lift engine (`runProgressionEngine`, DB-backed `exercise_state` rows) and the rehab engine (`runRehabProgressionStep` in `.claude/rules/rehab.md`, localStorage-backed records). Neither `computeProgressionStep` nor the three math helpers touch a database or localStorage — they take plain weight/state inputs and return a patch; callers own persistence. This is the single source of truth for progression math — do not reimplement catch-up/stall logic anywhere else.

Signature: `computeProgressionStep(state, setsData, opts)`
- `state`: `{ s1w, s2w, s3w, progressionState, consecutiveFailures }` — storage-agnostic weight/state shape (not DB column names).
- `setsData`: `[{reps, skipped}, ...]`, index 0 = set1.
- `opts`: `{ goalReps, variant, progressionConfirmed, holdOnSuccess }`. `holdOnSuccess` is a generic escape hatch for "a success+confirmed evaluation should be a total no-op, don't even persist an in-flight state correction" — the lift engine passes `amberKneeHold` through it (see Amber suppression below). Rehab never sets it since rehab has no readiness-gate concept by design.
- Returns a patch with only the changed keys (`s1w`/`s2w`/`s3w`/`progressionState`/`consecutiveFailures`), or `{}` if nothing changes.

`runProgressionEngine` translates between the DB's `set1_weight`/`set2_weight`/`set3_weight`/`progression_state`/`consecutive_failures` column names and the shared function's neutral `s1w`/`s2w`/`s3w`/`progressionState`/`consecutiveFailures` shape immediately before/after calling `computeProgressionStep`. No lift-specific logic (ROM hold, deload freeze, amber suppression) lives inside the shared function — those gates run in `runProgressionEngine` before it decides whether/how to call `computeProgressionStep`.

**Rep-ladder catch-up correction** (inside `computeProgressionStep`): a `rep_ladder`-variant exercise in `'ready'` state is only actually ready once set1/set2 have reached their `classicTargets` for the current set3 weight. If either lags (e.g. a freshly-seeded exercise with set1/set2 below set3 — this happened for real with Lateral raise/Curl, corrected 2026-08-09), the function silently treats the exercise as `catch_up_set2`/`catch_up_set1` instead of requiring a fresh ceiling-rep hit on set3, and persists the correction on the very next evaluation (success, partial, or stall) — it doesn't wait for a specific outcome. Apply the same check when hand-seeding new rep-ladder exercises in `supabase/seed.sql`: don't seed `'ready'` if set1/set2 are below their classic targets for set3 — seed the correct catch-up state directly.

## Mode selection
Per exercise, chosen at runtime via `progressionVariant(set3_weight)`: if a 5 lb step is >20% of set-3 weight → **rep-ladder**. Otherwise → **classic catch-up**.

Classic threshold: set3 must reach **25 lbs** before auto-progression kicks in.

## `progression_type` column
`exercises.progression_type` (TEXT, default `'weight'`) gates alternate engines:
- `'weight'` → classic/rep-ladder logic (all exercises by default)
- `'stance'` → `runStanceProgression` (Plank with shoulder taps); stance codes stored in set1/2/3_weight: `1` = shoulder width, `2` = feet together
- Bodyweight exercises (`is_bodyweight = true`) exit `runProgressionEngine` early — no progression regardless of type. Ab roller is the example.
- ROM hold: if `ex.progression_hold_until_phase` is set AND `APP.planState.rom_stage < ex.progression_hold_until_phase`, the engine returns early. This gate keys off `rom_stage` (not `current_phase`) — front squats and single-leg bench squat require `rom_stage = 3` (full ROM). A phase advance does not unlock this.

## Finishers
Optional exercises (`is_optional = true`) **do** run through the full progression engine — the old `is_optional` guard was removed. Only ab roller is exempt (bodyweight). Lateral lunge = classic. Y raise = rep-ladder (5 lbs currently).

## Rep-ladder state machine
When `progressionVariant` returns `'rep_ladder'` and `progState === 'ready'`:
- **Ceiling** = `goal_reps + 5`. Hitting ceiling on set 3 + confirm → advance set3 weight by 5 lbs, enter `catch_up_set2`.
- Below ceiling but ≥ goal → stay `ready`, no weight change.
- `catch_up_set2` / `catch_up_set1` in rep-ladder fall through to **classic** catch-up logic.
- `defaultReps(ex, setIdx)` pre-fill per set: sets 1–2 (`setIdx` 0–1) → `goal_reps`; set 3 (`setIdx` 2) → ceiling (`goal_reps + 5`). Catch-up states (`catch_up_set2`, `catch_up_set1`) always use `goal_reps` regardless of set.
- Hint on set 3 shows: `"Hit <ceiling> reps on set 3 → advance to <next> lbs"`. Sets 1–2 show a reminder info line pointing to the set-3 target.

## Classic catch-up state machine
Advance order: set3 first, then set2, then set1.
State sequence: `ready → catch_up_set2 → catch_up_set1 → ready`
Catch-up targets: set2 = `ceil(s3·0.9/5)·5`, set1 = `ceil(s3·0.8/5)·5`

Rep floor = `ceil(goal·0.8)`; ceiling = `goal+5`.
- **Success:** actual_reps ≥ goal on the evaluated set.
- **Stall:** 2 consecutive sessions under floor → deload set3 by 10% (round to 5), re-enter catch-up.
- **Increments:** 5 lb only.
- Skipped sets and bodyweight exercises never advance progression or count as stalls.
- Progression frozen for **knee-loading exercises only** while `in_deload` when `deload_freezes_progression` is true (read from `plan_config`). Non-knee-loading exercises (bench, rows, curls, etc.) progress normally during a deload — a knee flare has no clinical basis to freeze upper body work. `runStanceProgression` has no deload freeze at all (Plank is not knee-loading).
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

When amber + knee-loading + user hit goal + confirmed: `runProgressionEngine` passes `holdOnSuccess: true` into `computeProgressionStep`, which returns `{}` (no write) for that evaluation — **no DB write**, and note this discards even an in-flight rep-ladder catch-up correction for that one evaluation (matches the original "hold flat this session; don't touch state" behavior exactly). Stall counting still runs on other paths (underFloor). Stance and non-knee-loading exercises are unaffected.

## Detraining deload (`checkDetrain`)
Called once per fresh session start (not for resumed sessions). Checks calendar days elapsed since each weighted exercise's most recent completed set, using the last 10 completed sessions for the current gym_day as the history window.

**Trigger:** elapsed > 14 days.

**Math:** same as stall deload — `set3 = round(set3 × 0.9 / 5) × 5`, recompute set2/set1 targets via `classicTargets`, enter `catch_up_set2`. `consecutive_failures` reset to 0 (layoff ≠ rep-floor failure; distinguish the cause if needed later).

**Exclusions:**
- Bodyweight exercises (`is_bodyweight = true`)
- Stance exercises (`progression_type = 'stance'`)
- Any knee-loading exercise already under `in_deload + deload_freezes_progression = true`
- Exercises with no completed sets on record (new exercise — no deload)

**Display:** deload reason is stored in `APP.detrainingNotes[exercise_id]` and shown as:
- A warning line in `rExerciseRow` (workout overview) when the exercise is active
- An amber banner in `rLogSet` on set 1 only

**No skip-counter:** under the opportunistic-lift model, missing a lift is an absence, not a discrete event — a counter would never reliably increment.

## Exercise-level skipping
`skipWholeExercise(idx, reason)` logs all 3 sets as skipped and calls `finishExercise`.
- Main exercises: "Skip…" button → reason sheet (niggle / travel / other).
- Optional finishers: one-tap "Skip", no reason required.
- Niggle skips trigger `markNiggleFlare`.

---

## Clinical rationale ("why" for each major rule)

Rules in this file encode specific clinical and engineering decisions. This section documents which are evidence-derived vs. deliberate engineering choices, so a future agent knows which are safe to tune without re-checking the literature.

### Amber suppression scoped to knee-loading exercises only (`isKneeLoading`)
**Rule:** Under amber readiness, weight advances are suppressed for `isKneeLoading` exercises only. Non-knee-loading exercises (bench press, rows, curls, plank) progress normally during a knee-flare deload.
**Evidence:** PFP/quadriceps tendinopathy flares affect patellofemoral and peri-patellar tendon tissue specifically. The evidence base's relative-rest model means maintaining load where it is clinically safe while reducing load at the affected joint. There is no clinical basis for suppressing bench press or rows during a knee flare — those exercises produce zero patellofemoral stress. Blanket progression freeze would unnecessarily impair upper-body and systemic training capacity.
**Why this matters:** If someone changes `isKneeLoading` to `() => true` (affect all exercises) or removes the check, the code will still appear to work, but the clinical protocol will be wrong — upper-body work will silently stall during every knee flare.

### ROM gate (`progression_hold_until_phase`) keys off `rom_stage`, not `current_phase`
**Rule:** Front squats and single-leg bench squat have `progression_hold_until_phase = 3`, checked against `APP.planState.rom_stage` (not `current_phase`). All weight advances are suppressed until `rom_stage ≥ 3`.
**Evidence:**
- Powers et al. (2014): to minimise PFJ stress, squats should be performed from **0° to 45° of knee flexion**. PFJ stress is highest between 60° and 90°.
- Kernozek et al. (2020): reducing squat depth by ~6° reduced patellofemoral joint forces by **14.4%**.
- Evidence base protocol: *"gradually deepen to 60° over 4–6 weeks, monitoring 24-hour symptom response."*
**Why it keys off `rom_stage` not `current_phase`:** ROM advancement is time-gated (28-day minimum per stage) to allow the 4–6 week symptom-response observation window the evidence base prescribes. Phase can advance faster than that. Tying the gate to phase would allow weight advances (at depth) on a timeline that outpaces the symptom-monitoring window. See `.claude/rules/rehab.md` § ROM stage gate for full rationale.
**Column name note:** `progression_hold_until_phase` is a legacy name predating the ROM/phase decoupling. It now stores the required `rom_stage` integer.

### Deload freeze scoped to knee-loading exercises only (during `in_deload`)
**Rule:** `deload_freezes_progression` from `plan_config` freezes progression on knee-loading exercises only during a deload. `runStanceProgression` (Plank) has no deload freeze at all.
**Evidence:** Same rationale as amber suppression — PFP/tendinopathy flare is joint-specific. A knee flare has no clinical basis for freezing upper-body strength progression. The deload model is *relative* rest, not systemic load cessation. See `.claude/rules/rehab.md` § Relative-rest deload.

### Isometric pre-load → immediate analgesia before HSR
**Rule:** Isometric exercise (5 × 45 s) is performed before the HSR lift rotation. The 2-minute inter-set rest is enforced by the app.
**Evidence:** Rio et al. (2015) — isometric knee extension at ~60° (5 × 45 s at ~80% MVIC) → immediate analgesia lasting ≥45 min, with cortical inhibition release. Used as a pre-session warm-up: reduces tendinopathy pain before weighted exercises and primes quadriceps activation. See `.claude/rules/rehab.md` § Isometric pre-load for full citation.

### Detraining deload: 14-day trigger
**Rule:** `checkDetrain` applies a −10% deload to an exercise when >14 days have elapsed since the most recent completed set.
**Evidence:** **Engineering choice, not a direct evidence-base citation.** General strength-detraining literature (multiple reviews) suggests measurable strength decrements begin at approximately 2–4 weeks of detraining in trained individuals. The 14-day (2-week) trigger is a conservative approximation of the lower bound of that window. The RTF does not give an exact threshold for this; 14 days was chosen to catch long training gaps before they become clinically significant without being overly sensitive to a single missed session. Safe to adjust within the 10–21 day range without re-checking the literature.

### Rep-ladder mode: >20% threshold for mode selection
**Rule:** `progressionVariant(set3Weight)` returns `'rep_ladder'` when `5 / set3Weight > 0.20` (i.e., a 5 lb increment is >20% of the current weight).
**Evidence:** **Engineering choice, not evidence-derived.** The >20% heuristic approximates the point at which a 5 lb increment is "too large" to constitute a clean linear progressive overload (a standard loading principle). Below this threshold, 5 lbs is a small enough step that straight classic catch-up is appropriate. Above it, the rep-ladder allows building a larger rep base before advancing weight, reducing injury risk from premature load jumps. Safe to tune.

### Classic catch-up threshold: 25 lbs minimum for auto-progression
**Rule:** Classic catch-up mode does not auto-advance weights until set3 reaches 25 lbs.
**Evidence:** **Engineering choice, not evidence-derived.** At very low weights, even a 5 lb increment is a large relative jump, and the rep-ladder should be handling those cases (they will have `5/weight > 0.20` already). The 25 lb threshold is a backstop to prevent edge-case weight values from entering the classic engine prematurely. Safe to tune.
