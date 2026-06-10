---
name: rehab-engine
description: Rehab cursor advance, flare/deload state machine, readiness gate semantics
metadata:
  type: project
---

# Rehab & Flare Engine

## Non-lift day advance (`maybeWriteNonLiftAdvance`)
Non-lift days (is_lift_day = false) never call `finishSession`, so they need their own path to write `lift_advance_pending`. `maybeWriteNonLiftAdvance()` is called from `toggleRun`, `toggleRehab`, and `rehabMarkComplete` — it fires once both `run_completed` and `rehab_completed` are true. On non-lift days, `nextGymDay` = `current_gym_day` (unchanged); only `current_cycle_day` advances.

## Rehab cursor (`advanceCycleDay`)
Advances **one cycle-day per completed session**, NOT by calendar.
Plan lookup: `day_number = (current_phase - 1) * 8 + current_cycle_day`

On the 8→1 roll, evaluate the cycle:
- **Clean** (no flare, ≤ max rest days from `plan_config`): increment `clean_cycles_completed`; advance phase when threshold reached.
- **Not clean**: reset `clean_cycles_completed` to 0.

`current_gym_day` cycles 1→2→3→1 forever, independent of phase changes or regressions.

## Flare definition (`evaluateFlare`, `markNiggleFlare`)
A flare is triggered by **any** of:
- Morning pain ≥ threshold (from `plan_config`)
- `joint_fullness` (swelling) flag
- A niggle-skip
- `run_outcome = 'flagged'`

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
- `v_phase_ready` uses `current_phase < 7` as the advance gate.
- Phase advance logic in `index.html` (`advanceCycleDay`): `ps.current_phase < 7` — **do not change back to 3**.
- Phases 4–7 semantics shift from ROM-gated rehab to training-load stages; clean-cycle advancement (2 consecutive clean cycles) applies identically.

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
