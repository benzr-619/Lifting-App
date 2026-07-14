---
name: rehab-engine
description: Rehab cursor advance, flare/deload state machine, readiness gate semantics
metadata:
  type: project
---

# Rehab & Flare Engine

## ROM stage cursor (`rom_stage`, `rom_stage_started_on`)
Independent of `current_phase`. Advances on time elapsed, not on phase transitions. Three stages: 1=45°, 2=60°, 3=Full ROM.

**Advance logic** (`maybeAdvanceRomStage`, called each boot after `recomputeCycleRestDays`):
- If `today − rom_stage_started_on ≥ rom_stage_min_days` (28 days, from `plan_config`) AND `rom_stage < 3`: increment `rom_stage`, reset `rom_stage_started_on = today`.
- Phase advance does NOT trigger ROM stage advance — they are fully independent. A phase can advance while ROM stage stays at 1 (if the flare clock keeps resetting it), or ROM stage can reach 3 while still in Phase 1.

**Flare resets the ROM clock** (`applyFlareConsequences`):
- Any confirmed flare (pain ≥ `pain_dirty_threshold`, swelling, or `run_outcome = 'flagged'`) resets `rom_stage_started_on = today` when `rom_stage < 3`.
- The stage number does NOT regress — only the clock resets, requiring another 28-day clean window before advancing.

**Niggle-skip resets the clock** (`markNiggleFlare`):
- When `markNiggleFlare` is called (meaning the isRunAndLiftDay+isKneeLoading exemption did NOT apply), also resets `rom_stage_started_on = today` if `rom_stage < 3`.
- Same exemption applies: run+lift-day knee-loading skips → `markNiggleFlare` is not called → no ROM reset.

**UI**: `rProgressSummary` displays ROM stage and days remaining. `rExerciseRow` and `rLogSet` show a lock indicator for exercises held by the ROM gate.

## Flagged-run flare (fully implemented)
`run_outcome = 'flagged'` now triggers immediate flare consequences — no wait for next morning's check-in.

After logging a run (`toggleRun` or `logAlternateActivity`), a bottom sheet asks "How did that run feel?" with Clean / Flagged options. Selecting "Flagged" calls `saveRunOutcome('flagged')`, which:
1. Writes `run_outcome = 'flagged'` to `daily_log`.
2. Calls `applyFlareConsequences()` directly (same logic as morning check-in flare path).
3. Calls `refreshReadiness()` to update `APP.readiness`.

Un-logging a run (`toggleRun` setting `run_completed = false`) also clears `run_outcome = null`.

The view `v_readiness` treats `run_outcome = 'flagged'` as red (was in the view schema already; now there is UI to set it).

## Cycle-day advance (`maybeWriteCycleDayAdvance`)
The cycle cursor is **fully decoupled from lift completion**. `maybeWriteCycleDayAdvance()` fires on every day type (lift or non-lift) once the rehab+run gate is satisfied. It is called from `toggleRun`, `logAlternateActivity`, `toggleRehab`, and `rehabMarkComplete`.

Gate logic:
- `rehab_completed` must be true.
- If today has a scheduled run (`APP.todayPlan.run_miles !== null`): `run_completed` must also be true.
- Buffer days return early — their 8→1 roll is managed by seam-buffer detection in `loadBootData`.

On completion the function writes `lift_cycle_day_pending: { date }` to localStorage. `loadBootData` applies it the next morning via `advanceCycleDay()`, independent of whatever `lift_gym_day_pending` does.

Rationale: the rehab evidence base treats running progression and strength work as two independently-dosed tracks. Missing a lift (e.g. a 12-hour shift) should not stall the prescribed run program — the cycle advances when run+rehab are done, regardless.

## Gym-day advance (`finishSession` / `lift_gym_day_pending`)
`current_gym_day` only advances when a lift session is actually completed. `finishSession()` writes `lift_gym_day_pending: { date, nextGymDay }`. Applied independently next morning — can lag behind the cycle cursor by any number of days. You never "lose" gym day 2; it simply waits until you lift again.

## Rehab cursor (`advanceCycleDay`)
Advances **one cycle-day per completed rehab+run session** (per-calendar-day, not per-lift). NOT gated on lift completion.
Plan lookup: `day_number = (current_phase - 1) * 8 + current_cycle_day`

On the 8→1 roll, evaluate the cycle:
- **Clean** (no flare, ≤ max rest days from `plan_config`): increment `clean_cycles_completed`; advance phase when threshold reached.
- **Not clean**: reset `clean_cycles_completed` to 0.

`current_gym_day` cycles 1→2→3→1 forever, independent of phase changes or regressions.

## Flare definition (`evaluateFlare`, `markNiggleFlare`)
A flare is triggered by **any** of:
- Morning pain ≥ threshold (from `plan_config`)
- `joint_fullness` (swelling) flag
- A niggle-skip *(see run+lift-day exemption below)*
- `run_outcome = 'flagged'`

### Distinction: dirty-cycle vs full flare
`markNiggleFlare()` only sets `current_cycle_clean = false` — it does NOT increment `phase_flare_count` or trigger deload. Full flare consequences (deload, regression) come only from `evaluateFlare`, which is called exclusively from the morning check-in (`saveCheckin`). A niggle-skip marks the cycle dirty but is not a full flare.

### Run+lift-day exemption (`isRunAndLiftDay`)
When today is both a lift day (`APP.todayPlan.is_lift_day`) and a run has been logged (`APP.todayLog.run_completed`), a niggle-skip of a **knee-loading exercise** (`isKneeLoading(ex)`) is treated as expected provocation — the run pre-loads the knee — and does **not** call `markNiggleFlare`.

- The skip is still logged to `session_sets` with `skip_reason = 'niggle'` normally.
- `phase_flare_count`, `in_deload`, and `current_cycle_clean` are all unaffected.
- Niggle-skips of non-knee-loading exercises on run+lift days still call `markNiggleFlare`.
- On lift-only days (no run logged) niggle-skips always call `markNiggleFlare` regardless of exercise.
- Morning check-in pain ≥ threshold and `joint_fullness` still trigger full flares on any day — the exemption is skip-path only.
- `run_outcome = 'flagged'` behavior is also unchanged.

Implementation: `isRunAndLiftDay()` helper (defined next to `isKneeLoading`) is checked in both `doSkipSet` and `skipWholeExercise` before calling `markNiggleFlare`.

## Flare response
**1st flare in a phase → deload (relative rest, not full rest):**
- Cap run mileage
- Freeze lift progression
- Suppress plyos
- Keep isometrics + mobility

Exit deload: clean check-in AND ≥ `flare_min_rest_days` passed → resume at the same cycle-day.

**2nd flare in a phase before banking a clean cycle → regress one phase.**

Do not simplify these rules back to forced rest — the relative-rest model was chosen deliberately.

## Phase ceiling
- `plan_state.current_phase` CHECK constraint: `BETWEEN 1 AND 7` (migration 003).
- `cycle_plan.day_number` CHECK constraint: `BETWEEN 1 AND 56` (migration 003).
- `daily_log.plan_phase` CHECK constraint: `BETWEEN 1 AND 7` (migration 005b — was capped at 3, blocking phase 4+ log writes).
- `v_phase_ready` uses `current_phase < 7` as the advance gate.
- Phase advance logic in `index.html` (`advanceCycleDay`): `ps.current_phase < 7` — **do not change back to 3**.
- Phases 4–7 semantics shift from ROM-gated rehab to training-load stages; clean-cycle advancement (2 consecutive clean cycles) applies identically.

## Rest-day recompute (`recomputeCycleRestDays`)
Called at the top of `loadBootData()` after initial data load, before any `advanceCycleDay()` call. Recomputes `plan_state.current_cycle_rest_days` from source of truth on every boot — the field was previously always 0 because only resets (never increments) existed.

A calendar day is **active** (not a rest day) if any of these are true for that date: `run_completed = true`, `rehab_completed = true`, `cross_training_completed = true`, or a completed `sessions` row exists. Every other calendar day between cycle start and yesterday counts as a rest day.

Cycle start anchor: most recent `daily_log` row with `plan_phase = current_phase AND plan_cycle_day = 1` — same anchor as `checkStructuralWindows`. If no such row exists, returns early without writing. If the cycle started today, writes 0 and returns.

`advanceCycleDay()` resets `current_cycle_rest_days` to 0 on the 8→1 roll (correct — new cycle starts). The recompute runs before the advance so mid-cycle counts are accurate on every boot.

## Neutral cycle state (`checkStructuralWindows`)
Three-state cycle evaluation: **dirty** (flare / rest budget blown) → existing regression logic; **neutral** (no flare, but a required back-to-back run block was missed) → `clean_cycles_completed` unchanged, no `phase_flare_count` change, no regression; **clean** (no flare, rest within budget, all structural windows satisfied) → existing increment behavior.

Structural test windows live in `lift.structural_test_windows` (migration 005) — one row per back-to-back block per phase. New phases/blocks → add a row, no code change needed.

`checkStructuralWindows(phase)` is called in `advanceCycleDay()` only when `baseClean` is true (dirty supersedes neutral). It scopes to the current cycle pass by finding the most recent `daily_log` row with `plan_cycle_day = 1` for the phase, then verifies each window's cycle_days all have `run_completed = true` AND no calendar gap > 1 day between consecutive run entries.

`plan_state.last_cycle_outcome` ('clean' | 'neutral' | 'dirty') tracks the last completed cycle result and is displayed in `rProgressSummary`. Forward-looking only — historical `clean_cycles_completed` is not retroactively adjusted.

Active seeded windows:
- Phase 2, days 1→2: Day1(4.0mi)→Day2(2.0mi) back-to-back run test
- Phase 5, days 1→3: Triple consecutive-day block (5.5→3.5→4.0mi)

## deload_run_mile_cap
Read from `plan_config` at runtime. Automatically updated by `PHASE_DELOAD_RUN_CAP` in `index.html` when a phase advance fires:
- Phases 1–5: `2.0` mi (seed default)
- Phase 6: `4.0` mi (auto-set on advance)
- Phase 7: `4.5` mi (auto-set on advance)

The `updatePlanConfig(patch)` function handles DB writes and keeps `APP.planConfig` in sync. No manual intervention needed.

## Weighted rehab rest timer (band walks)
Band walk (`type: 'weighted'`) has `rest_short_seconds: 60` and `rest_long_seconds: 180` in `REHAB_EXERCISES`. `rehabLogSet()` checks for `ex.rest_short_seconds` and starts `APP.rehabRestActive` between sets (60s after set 1, 180s after set 2). The weighted block in `rRehab` renders the rest countdown when `rehabRestActive` is true — identical display to the timed rest screen. `rehabSkipRest()` works for both.

## Timed rehab rest timer
Timed exercises (type: `timed`, e.g. Spanish squat isometric) have a **2-minute rest between sets** enforced by the app.

State fields on `APP`:
- `rehabRestActive` (bool) — true while inter-set rest is running
- `rehabRestEndTime` (ms) — absolute `Date.now()` anchor; remaining time recomputed each tick to survive background throttle
- `rehabRestRemaining` (seconds) — display value

Flow: set timer hits 0 → mark set complete → if more sets remain, set `rehabRestActive = true`, `rehabRestEndTime = Date.now() + 120000`, call `scheduleTimerNotification` → rest interval runs in `render()` → on expiry: advance `rehabActiveSet`, reset `rehabTimerRemaining`, beep, render.

`rehabSkipRest()` cancels the notification, clears the interval, and drops immediately to the next set timer. `rehabTimerSkip()` also clears rest state in case it is called mid-rest. `goRehab()` recalculates `rehabRestRemaining` from `rehabRestEndTime` on re-entry so navigating away mid-rest doesn't reset the clock.

The two rehab interval blocks in `render()` (`rehabTimerActive` and `rehabRestActive`) are mutually exclusive — `render()` always clears `APP.timerInterval` before arming a new one, so only one runs at a time.

## Readiness gate
`v_readiness` returns green / amber / red from the latest check-in.
`v_phase_ready` returns a boolean phase-advance gate.

- **Green:** full progression, normal loads.
- **Amber:** knee-loading progression suppressed only (see `.claude/rules/progression.md`).
- **Red:** regress — apply regression logic before any session.
