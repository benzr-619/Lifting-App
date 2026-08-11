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

## Weighted rehab rest timer (band walks, step-downs, sl squat box)
Weighted exercises (`type: 'weighted'`) all have `rest_short_seconds: 60` and `rest_long_seconds: 180` in `REHAB_EXERCISES`. `rehabLogSet()` checks for `ex.rest_short_seconds` and starts `APP.rehabRestActive` between sets (60s after set 1, 180s after set 2). The weighted block in `rRehab` renders the rest countdown when `rehabRestActive` is true — identical display to the timed rest screen. `rehabSkipRest()` works for all types.

## Timed rehab rest timer
Timed exercises (type: `timed`, e.g. Spanish squat isometric) have a **2-minute rest between sets** enforced by the app.

State fields on `APP`:
- `rehabRestActive` (bool) — true while inter-set rest is running
- `rehabRestEndTime` (ms) — absolute `Date.now()` anchor; remaining time recomputed each tick to survive background throttle
- `rehabRestRemaining` (seconds) — display value

Flow: set timer hits 0 → mark set complete → if more sets remain, set `rehabRestActive = true`, `rehabRestEndTime = countdownEndTime(120)`, call `scheduleTimerNotification` → rest interval runs in `render()` → on expiry: advance `rehabActiveSet`, reset `rehabTimerRemaining`, beep, render.

`rehabSkipRest()` cancels the notification, clears the interval, and drops immediately to the next set timer. `rehabTimerSkip()` also clears rest state in case it is called mid-rest. `goRehab()` recalculates `rehabRestRemaining` from `rehabRestEndTime` on re-entry so navigating away mid-rest doesn't reset the clock — this recompute now runs unconditionally for every exercise type that uses `rehabRestActive` (`timed`, `weighted`, `reps_no_weight`), not just `timed`.

The two rehab interval blocks in `render()` (`rehabTimerActive` and `rehabRestActive`) are mutually exclusive — `render()` always clears `APP.timerInterval` before arming a new one, so only one runs at a time.

### Absolute-anchor countdown unification (`countdownEndTime`/`countdownRemaining`)
The lift's rest timer (`APP.timerActive`/`timerEndTime`/`timerRemaining`) and the rehab inter-set rest timer (`APP.rehabRestActive`/`rehabRestEndTime`/`rehabRestRemaining`) previously computed their `Date.now()`-anchored start/tick math independently — two near-identical blocks of code that could drift apart under future edits. Both now call the same two shared helpers (defined near `fmt()`):
- `countdownEndTime(durationSeconds)` → `Date.now() + durationSeconds * 1000`
- `countdownRemaining(endTime)` → `Math.max(0, Math.round((endTime - Date.now()) / 1000))`

They deliberately remain **separate state slots**, not one shared variable — a rehab rest can be left running in the background (`goRehab()`'s resume-recompute above) while the user navigates to a lift set and starts the lift's own rest timer, so the two must be able to run concurrently without clobbering each other. What's unified is the tick/anchor arithmetic, not the storage. The isometric hold countdown (`rehabTimerActive`/`rehabTimerRemaining`) is a plain decrementing counter, not anchor-based, and is unaffected by this — it's a genuinely different kind of timer (a fixed-duration hold, not a rest-between-sets clock) and was out of scope for the unification.

## Rehab progression (weighted exercises — band_walk, step_down, sl_squat_box)
Weighted rehab exercises get the same reps-entry + confirm-progression treatment as the lift, but progression math and persistence are entirely separate from the lift's DB-backed system — **by deliberate design, not oversight**. Rehab loading must continue through a lift-side deload (`in_deload`), so rehab progression is NOT gated by `isKneeLoading`, the amber/red readiness gate, or `deload_freezes_progression`. See `.claude/rules/progression.md` for the shared math (`computeProgressionStep`, `classicTargets`, `repFloor`, `repCeiling`) both engines call.

### Rep entry
`rRehab()`'s weighted block shows an inline reps stepper (`rrn` element, `rehabRepsAdj(±1)`), pre-filled to `ex.reps` (the exercise's target) for the set about to be logged — no separate log-set screen, consistent with rehab's existing single-card flow. `rehabLogSet()` records whatever the stepper shows into `APP.rehabLoggedReps[setIdx]`, marks the set complete, and either starts the inter-set rest or (on the last set) calls `finishRehabExercise(ex)`.

### Confirm-progression gate
Mirrors the lift's `APP.progressionReady`/`toggleProgressionReady()`: `APP.rehabProgressionReady`/`toggleRehabProgressionReady()`. The confirm button only renders on the **last set** of the round (`completedCount === ex.sets - 1`), showing `rehabProgressionHint(ex, progress)`. Weight never auto-advances off rep counts alone — `finishRehabExercise` reads `APP.rehabProgressionReady` and passes it through as `progressionConfirmed` to `runRehabProgressionStep`.

### Single-shared-weight adaptation (`runRehabProgressionStep`)
Rehab exercises use **one weight for all sets** (the existing weight adjuster — no per-set set1/set2/set3 weight like the lift). This means there is nothing to "catch up" between sets, so `runRehabProgressionStep` feeds `s1w = s2w = s3w = progress.weight` and `progressionState: 'ready'` into `computeProgressionStep` on every call, and the returned `progressionState` is discarded — rehab **never persists** `catch_up_set2`/`catch_up_set1` (that's a lift-only concept, meaningless with a single weight). Practical effect: the evaluated set is always the last set of the round; classic-mode exercises (heavier weight, `5/weight ≤ 20%`) advance weight on any goal-reps success; rep-ladder-mode exercises (lighter weight, e.g. sl_squat_box at 10 lbs) require hitting the ceiling (`goalReps + 5`) first. The 2-consecutive-under-floor stall/deload (-10%, rounded to nearest 5) is identical to the lift's.

### Persistence (`loadRehabProgress`/`saveRehabProgress`)
Device-local, via the exercise's existing `weightKey` localStorage entry (the same key already used pre-progression for the plain weight number — now carries more state as JSON): `{ weight, consecutiveFailures, lastReps }`. `lastReps` is the reps logged per set on the most recently completed round (e.g. `[10, 10, 8]`), shown as a "Last round: …" line under the weight adjuster. `loadRehabProgress` migrates a legacy plain-number value transparently (pre-progression installs). **This history is device-local and does not survive a reinstall**, unlike the lift's DB-backed `exercise_state` — an accepted tradeoff of keeping rehab decoupled from the lift schema, not a bug.

## Plyo — reps-only, no weight (`type: 'reps_no_weight'`)
Plyo gets set-completion tracking and the same inter-set rest timer as weighted exercises (`rest_short_seconds: 60` / `rest_long_seconds: 180`), but **no weight tracking and no progression** — deliberately excluded per the isometric-preload/deload clinical rules on loaded plyometrics (rapid loading of an already-irritated joint has no analgesic upside the way isometrics do; see Clinical rationale below). `rehabLogPlainSet()` just marks the set complete and starts rest — no reps entry, no confirm gate, no localStorage state. `rRehab()`'s `reps_no_weight` branch renders set-completion chips + the shared rest-timer UI, structurally identical to the weighted block's chips but without the weight adjuster or stepper.

## sl_squat_box — no lock/unlock gate (deliberate, per-user decision)
`sl_squat_box` was converted from `type: 'free'` to `type: 'weighted'` (defaultWeight 10, increment 5) on 2026-08-09, given the same progression treatment as band_walk/step_down. **No unlock mechanism was built** — a lock/unlock gate (weight held at 0 until an explicit unlock action, mirroring the long-press state-panel pattern) was considered and explicitly rejected by Ben: he had already established reliable unweighted valgus control at the time of the change, so the exercise starts loaded at 10 lbs with no gate. If a future regression or phase reset means valgus control needs to be re-verified before loading resumes, that would need a new, explicitly-requested mechanism — none exists today.

## Readiness gate
`v_readiness` returns green / amber / red from the latest check-in.
`v_phase_ready` returns a boolean phase-advance gate.

- **Green:** full progression, normal loads.
- **Amber:** knee-loading progression suppressed only (see `.claude/rules/progression.md`).
- **Red:** regress — apply regression logic before any session.

---

## Clinical rationale ("why" for each major rule)

Rules in this file encode specific clinical decisions. This section ties each to the evidence source so a future agent or engineer knows which rules are evidence-derived vs. engineering choices.

### Relative-rest deload (not full rest)
**Rule:** Flare → relative rest (cap run, freeze knee-loading progression, suppress plyos, keep isometrics + mobility). NOT full rest.
**Evidence:** AAFP-published guideline (2020) states: *"relative rest followed by gradual return is the recommended first intervention"* for PFP caused by acute overexertion or rapid training load increase. Injury-prevention programs do not prevent PFP, but reducing activity followed by **graded re-exposure** can be beneficial. Full rest is not recommended; the loading stimulus is therapeutically necessary.
**Why it matters for the code:** The deload does not zero out all exercises. Non-knee-loading work (bench, rows, curls, plank) continues unchanged. Plyos are suppressed. Isometrics are kept (and substituted when plyos are scheduled) — they have independent analgesic rationale (see Isometric pre-load below).

### ROM stage gate for front squats and single-leg bench squat
**Rule:** `progression_hold_until_phase` value is checked against `rom_stage` (not `current_phase`). Front squats and single-leg bench squat require `rom_stage = 3` (Full ROM) before weight advances.
**Evidence:**
- Powers et al. [2014]: to minimise PFJ stress during weight-bearing exercises, squats should be performed from **0° to 45° of knee flexion**. PFJ stress is highest between 60° and 90°.
- Kernozek et al. [2020]: reducing squat depth by ~6° reduced patellofemoral joint forces by **14.4%**.
- Evidence base guidance: *"As symptoms settle, gradually deepen to 60° over 4–6 weeks, monitoring 24-hour symptom response."*
**Why ROM is decoupled from phase:** The phase cursor advances on clean cycles (run + rehab sessions), which can accumulate faster than a full 28-day ROM stage window. If ROM gating were tied to phase, a patient who banks clean cycles quickly could unlock full-depth front squats before the 4–6 week deepening window has elapsed. The independent 28-day clock (`rom_stage_min_days` from `plan_config`) enforces the symptom-response observation window regardless of how fast phases progress.
**Column name note:** `progression_hold_until_phase` is a legacy name — it now stores the required `rom_stage` value, not a phase number. The code correctly compares `APP.planState.rom_stage < ex.progression_hold_until_phase`.

### Isometric pre-load exercise (5 × 45 s holds) and 2-minute rest
**Rule:** Isometric exercise is type `'timed'` with 5 sets × 45 s. The app enforces a **2-minute inter-set rest** (`rehabRestActive`, 120 s). When plyos are suppressed during a deload, the app substitutes the isometric in their place.
**Evidence (Rio et al., 2015):** Isometric knee extension at ~60° of knee flexion (5 sets × 45 s at ~80% MVIC) produced **immediate analgesia** in patellar tendinopathy — pain reduced from 7.0/10 to 0.17/10 on single-leg decline squat, with effects lasting ≥45 minutes, paralleled by release of cortical inhibition. An in-season RCT confirmed isometric contractions were significantly more analgesic than isotonic contractions over 4 weeks.
**Pearson et al. (2018):** Short-duration holds (24 × 10 s) are equally effective as long-duration holds (6 × 40 s) when total time under tension is equalised. The 5 × 45 s protocol sits within the evidence-supported range.
**Why as deload substitute:** When plyos are suppressed (deload + `deload_suppress_plyo`), isometrics replace them because they provide analgesic pre-loading for tendon pain with **zero joint compression** at the depths used during a flare — unlike plyos which involve rapid loading of an already-irritated joint.

### Hip-focused rehab exercises (band walks, step-downs, RDLs)
**Rule:** The rehab program combines hip-targeted and knee-targeted exercises (band walks with goblet load, lateral step-downs, single-leg RDLs already in the lifting program).
**Evidence:**
- Zhang et al. meta-analysis (2025): **hip strengthening > knee strengthening** for both pain reduction (SMD −1.74 vs −1.30) and functional improvement (SMD 1.21 vs 1.02) in PFP.
- Earl & Hoch (2011): 8-week proximal strengthening program significantly reduced the **knee abduction moment** during running (the key biomechanical variable associated with dynamic valgus), while improving hip abduction and external rotation strength.
- 2018 International PFP Consensus Statement: recommends the **combination of hip-focused and knee-focused exercises** (not hip-only or knee-only).
- AAFP guideline: single-leg squats, step-downs, and hip resistance-band exercises with **high-volume protocols** (3 sets × 30+ reps, 3×/week) are most effective.
**Why weighted band walks (goblet position):** Converting monster walks to weighted goblet-held band walks increases neuromuscular demand and gluteus medius recruitment — the low-load version (body-weight monster walks) failed to produce meaningful biomechanical changes in experienced athletes (consistent with the literature's finding that higher-intensity, task-specific loading is needed).

### Run + rehab cycle-advance gate (not run + lift)
**Rule:** `maybeWriteCycleDayAdvance()` fires on any day type once `rehab_completed` (and `run_completed` when a run is scheduled) are true. Missing a lift does NOT stall the cycle cursor.
**Evidence:** The evidence base frames running progression and HSR (heavy slow resistance) as **two independently-dosed therapeutic tracks**, not a single compound intervention:
- Running progression manages patellofemoral load via volume, cadence, and frequency, with its own symptom-response monitoring criteria (24-hour pain return to baseline).
- HSR addresses quadriceps tendinopathy and tissue capacity via mechanical loading, with its own frequency prescription (3×/week, specific intensity targets).
Missing a lift on a given day withholds that session's HSR stimulus but does not negate the therapeutic value of a completed run+rehab day. Stalling the run program because a lift was missed would delay the graded running re-exposure that is central to the treatment. The decoupling reflects clinical reality: a patient on a 12-hour shift can still run+rehab and should be credited for it.

### Cadence target (180 spm) — **displayed, not tracked (gap)**
**Rule:** `cycle_plan.target_cadence` is populated (180 spm for all run days) and displayed on the run card in the UI as "180 spm target". Actual cadence achieved is NOT logged.
**Evidence (highest-yield gait intervention):**
- Bramah et al. (2019): single-session cadence retraining using a metronome produced significant reductions in peak contralateral pelvic drop (3.1°), hip adduction (4.0°), and running pain, maintained at 3 months, with a mean increase in longest pain-free run of **6.8 km**.
- 2025 systematic review and meta-analysis: increased step rate significantly reduces patellofemoral joint contact force (PFCF) and patellofemoral joint stress (PFJS).
- Biomechanical modeling: a 10% step-rate increase reduces peak patellofemoral joint force by **~14%**, primarily by decreasing peak stance-phase knee flexion.
**Gap:** The target is shown but there is no mechanism to log actual cadence achieved, or to flag sessions where cadence was not reached. This is noted in Open Items. A future redesign should consider adding a post-run cadence field to `daily_log`.
