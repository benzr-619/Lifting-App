# Lift — workout + PFPS rehab tracker

Mobile-first PWA that runs Ben's 3-day lifting split alongside an 84-day patellofemoral-pain-syndrome (PFPS) rehab/run cycle. Replaces a clunky phone spreadsheet: auto-calculated weights, a progression state machine, a daily rehab/run/lift schedule, rest timers, and a symptom-driven deload/regression engine.

## Architecture at a glance

Two layers, nothing in between:

- **Frontend:** a single file, `index.html` (~2000 lines). Vanilla JS, no build step, no framework, no bundler. One global `APP` state object, a string-concatenation render engine, and `db.*` calls straight to Supabase.
- **Backend:** Supabase Postgres. All objects live in the **`lift` schema** (not `public`) because the instance is shared with another app. The DB stores state + tunable thresholds; **all behavioral logic lives in the app**, not in triggers or functions. Two read-only views (`v_readiness`, `v_phase_ready`) expose computed gates.

```
index.html ── supabase-js (schema: 'lift') ──► Postgres (lift.*)
```

There is no server, no API layer, no auth flow. The Supabase anon key is embedded in `index.html` and is public-safe (intended to be protected by row-level security — see Open items).

## File map

- `index.html` — the entire app: config, `APP` state, data layer, progression engine, rehab/flare state machines, render functions, action handlers, utilities. Boots by calling `loadBootData()` at the bottom.
- `supabase/schema.sql` — full schema. **The comments are the spec** — every rule (flare handling, cycle evaluation, deload knobs) is documented inline there in detail. Read it before touching logic.
- `supabase/seed.sql` — 15 exercises with current working weights + computed progression states, the 24-day cycle plan, and the two singleton rows (`plan_state`, `plan_config`). Weight/state math is shown per-row in comments.
- `supabase/migrations/002_run_outcome.sql` — adds `daily_log.run_outcome` and rebuilds `v_readiness`. **Apply this against live Supabase before relying on post-run flagging.**
- `Strength_Tracking_Ramping_Sets.xlsx`, `Cycle Through Days.xlsx` — the source spreadsheets the seed data was derived from. Source of truth for *initial* weights/plan; ask Ben what changed here before regenerating `seed.sql`.
- `NEXT_CHAT_PROMPT.md`, `PLAN_EVALUATION.md` — design/handoff notes.

## Data model (lift schema)

- **`exercises`** — static config per exercise: `gym_day` (1–3), `day_order` (position; supersets share a value), `goal_reps`, increments, rest seconds, `form_cue`, and flags: `is_bodyweight`, `is_optional` (finisher), `superset_group_id` + `is_superset_anchor`, `progression_hold_until_phase`.
- **`exercise_state`** — one row per exercise: `set1/2/3_weight`, `progression_state` enum, `consecutive_failures`.
- **`sessions`** / **`session_sets`** — one row per gym visit; one row per logged set. `target_reps` is **snapshotted at log time** so history stays correct after progression. A set is `completed` (has `actual_reps`) or `skipped` (has `skip_reason`); a CHECK constraint enforces the pairing.
- **`cycle_plan`** — 24 reference rows (3 phases × 8 days): run miles, cadence, rehab exercise + timing, `is_lift_day`.
- **`plan_state`** (singleton) — the rehab cursor: `current_phase`, `current_cycle_day` (1–8), `current_gym_day` (1–3, advances independently), counters, `in_deload`, `deload_started_on`.
- **`plan_config`** (singleton) — all tunable thresholds (pain threshold, clean-cycles-required, rest-day caps, flare/deload knobs). **Read these — never hard-code the numbers.**
- **`daily_log`** — one row per calendar day: pain (1–5), `joint_fullness` (swelling), run/rehab completion, `run_outcome`.
- **Views:** `v_readiness` (green/amber/red from latest check-in), `v_phase_ready` (boolean phase-advance gate).

Singletons are enforced with a `singleton_guard BOOLEAN UNIQUE` column.

## Core logic (all in index.html)

**Progression engine** (`runProgressionEngine`, `progressionVariant`, `classicTargets`, `repFloor`):
- Two modes per exercise, chosen by whether a 5 lb step is >20% of set-3 weight: **rep-ladder** (light loads; progression is rep-based, weight advances manually) vs **classic catch-up** (the state machine).
- Classic catch-up order: set3 advances first, then set2, then set1 (`ready → catch_up_set2 → catch_up_set1 → ready`). Targets: set2 = `ceil(s3·0.9/5)·5`, set1 = `ceil(s3·0.8/5)·5`.
- Rep floor = `ceil(goal·0.8)`; ceiling = `goal+5`. Success = hit ≥ goal on the evaluated set. Stall = 2 consecutive sessions under floor → deload set3 by 10% (round to 5) and re-enter catch-up.
- **5 lb increments only.** Skipped sets, form-holds, and bodyweight/optional exercises never advance progression or count as stalls. Progression is frozen entirely while `in_deload` (if `deload_freezes_progression`).
- `progression_hold_until_phase` (front squats, single-leg bench squat = 3): suppress all advances while `current_phase` < that value — partial-ROM reps in early phases aren't a true progression signal.

**Rehab cursor** (`advanceCycleDay`): advances **one cycle-day per completed session**, NOT by calendar. Map cursor → plan via `day_number = (current_phase-1)*8 + current_cycle_day`. On the 8→1 roll, evaluate the cycle: clean (no flare, ≤ max rest days) bumps `clean_cycles_completed` and advances phase at the threshold; otherwise the counter resets.

**Flare + deload** (`evaluateFlare`, `markNiggleFlare`): a flare = morning pain ≥ threshold, swelling, a niggle-skip, or `run_outcome='flagged'`. 1st flare in a phase → **deload (relative rest, not full rest)**: cap run mileage, freeze lift progression, suppress plyos, keep isometrics + mobility. Exit when a clean check-in AND ≥ `flare_min_rest_days` have passed; resume the same cycle-day. 2nd flare in a phase (before banking a clean cycle) → regress one phase. These rules were deliberately chosen over forced rest — don't "simplify" them back.

**Readiness gate**: `v_readiness` → green (go) / amber (hold loads flat) / red (regress).

## Frontend conventions

- **State:** one global `var APP = {…}`. Mutate it, then call `render()`. No reactivity — `render()` rebuilds `#screen.innerHTML` from scratch every time.
- **Screens:** `APP.screen` is a string (`today`, `checkin`, `workout`, `log_set`, `rest`, `calendar`, `rehab`); `render()` switches on it to one `r<Screen>()` function that returns an HTML string.
- **Naming:** render functions are `r*` (`rToday`, `rWorkout`, `rRehabCard`…); actions/handlers are plain verbs (`startWorkout`, `doLogSet`, `saveCheckin`); data-layer functions are verbs over Supabase (`loadBootData`, `saveDailyLog`, `updatePlanState`).
- **Style:** ES5-flavored — `var`, `function`, `.map/.forEach`, string concatenation (no template literals, no JSX). `async/await` is used for DB calls. Keep new code in the same idiom for consistency.
- **Styling:** inline styles built from a CSS-variable design-token palette in `:root` (`--color-*`, `--radius-*`), with a full dark-mode override via `prefers-color-scheme`. Always use the tokens, never raw hex. App is width-capped at 430px (phone). Icons are Tabler webfont (`<i class="ti ti-*">`). Large tap targets, default reps pre-filled with +/- adjust, a primary "Done" action — gym-usable one-handed.
- **Timers:** `setInterval` stored on `APP.timerInterval`; `render()` clears it on every call and re-arms it for the `rest`/`rehab` screens. `playTimerDone()` synthesizes beeps via WebAudio.
- **Rehab exercises** are matched to behavior (`timed` / `weighted` / `free`) by substring-matching the plan's `rehab_exercise` text in the `REHAB_EXERCISES` table (`rehabMatchExercise`). Rehab weights persist in `localStorage` per exercise key.

## Important behaviors / gotchas

- **Local date, not UTC:** use `localDateStr()` (`YYYY-MM-DD` from local time) for all `log_date` / day comparisons. Never `toISOString()` for dates — it skews across midnight.
- **Deferred day-advance:** finishing a workout does NOT advance the cursor immediately. It writes `lift_advance_pending` to `localStorage`; `loadBootData()` applies the advance on the next calendar day, so today's dashboard keeps showing today's plan after you finish. Don't "fix" this into an immediate advance.
- **The cursor is per-session, not per-date.** Incidental life rest days are fine and don't break a cycle. `current_gym_day` cycles 1→2→3→1 forever and is never reset by a phase change or regression.
- **`plan_config` is the single source for thresholds.** Read them at runtime.
- **Schema comments are authoritative.** When logic in `index.html` and a schema comment seem to disagree, the comment documents the intended rule — reconcile, don't guess.
- **Settled design decisions exist** (progression math, flare/deload/regression model, ROM-gating, rest timers 60s/180s, superset rules). These were worked out deliberately; don't re-litigate them. Ask Ben when something is genuinely open (e.g. the "coach" UX layer, still undesigned).

## Working on this project

- No build/run step: open `index.html` in a browser, or serve the folder statically. There are no tests, no linter, no package manager.
- To change weights or the plan: edit `seed.sql` (and confirm with Ben against the source spreadsheets first), then re-run it in Supabase.
- To change schema: write a new numbered migration in `supabase/migrations/` rather than editing `schema.sql` against a live DB. Remember `OR REPLACE` can't add columns to a view — DROP + CREATE (see migration 002).
- Git remote: `github.com/benzr-619/Lifting-App`.

## Open / not yet done

- **Migration 002 not yet applied** to live Supabase (adds `run_outcome` + flagged-run flare handling).
- **Row-level security** — the anon key is public; RLS policies are assumed but should be verified before this is genuinely multi-user or exposed.
- **Coach UX** on top of the daily check-in is undesigned. Keep it rules-based (no LLM) unless decided otherwise.
- Future, deferred: LM Studio + Qwen for AI analysis.
