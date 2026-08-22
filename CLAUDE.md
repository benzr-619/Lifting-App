# Lift — workout + PFPS rehab tracker

## [AUTOMATIC MAINTENANCE]
New area-specific detail is appended directly to a targeted `.claude/rules/<area>.md` with a one-line pointer here — no rewrite of this file. Changing behavior already documented here requires confirmation first. Keep CLAUDE.md under a ~15 KB soft cap; history goes to CHANGELOG.md.

**After every session where a bug was fixed, a schema fact was discovered, or a gotcha was identified: update the relevant `.claude/rules/<area>.md` file immediately — do not wait to be asked.** If no rules file fits, create `.claude/rules/data.md`. This is mandatory, not optional.

---

Mobile-first PWA: Ben's 3-day lifting split + 84-day PFPS rehab/run cycle. Auto-calculated weights, a progression state machine, a daily schedule, rest timers, and a symptom-driven deload/regression engine.

## Architecture

Two layers, nothing in between:

- **Frontend:** `index.html` (~2300 lines). Vanilla JS, no build step, no framework. One global `APP` state object, string-concatenation render engine, `db.*` calls straight to Supabase.
- **Backend:** Supabase Postgres, **`lift` schema** (not `public` — shared instance). DB stores state + thresholds; **all behavioral logic lives in `index.html`**, not triggers/functions. Views `v_readiness` and `v_phase_ready` expose computed gates.

```
index.html ── supabase-js (schema: 'lift') ──► Postgres (lift.*)
```

No server, no API layer, no auth flow. Anon key is embedded and public-safe (RLS assumed — see Open items).

## Supabase MCP access

Supabase MCP is connected. Use it for migrations, schema inspection, and data queries instead of asking Ben to run SQL manually.

- **Project:** Grind and Flow — `project_id: copzqbnjoakvcrvmedev`
- **Schema:** `lift` (all 8 tables visible)
- **To apply migrations:** use `mcp__899b7744-54a6-47e1-a735-2678d4cff41e__apply_migration` with this project ID.
- **To inspect/query:** use `execute_sql` or `list_tables` with `schemas: ["lift"]`.

## Files

| File | Purpose |
|---|---|
| `index.html` | Entire app. Boots via `loadBootData()` at bottom. |
| `sw.js` | Service worker: rest-timer background alerts. Must be served from same root as `index.html`. |
| `supabase/schema.sql` | Full schema. **Comments are the spec** — read before touching logic. |
| `supabase/seed.sql` | 15 exercises, 24-day cycle plan, singleton rows. Weight math in comments. |
| `supabase/migrations/002_run_outcome.sql` | Adds `daily_log.run_outcome`, rebuilds `v_readiness`. Applied to live DB (column confirmed 2026-07-15). |
| `Strength_Tracking_Ramping_Sets.xlsx`, `Cycle Through Days.xlsx` | Source of truth for initial weights/plan. Confirm with Ben before regenerating seed. |
| `NEXT_CHAT_PROMPT.md`, `PLAN_EVALUATION.md` | Design/handoff notes. |

## Data model (`lift` schema)

- **`exercises`** — static config: `gym_day` (1–3), `day_order`, `goal_reps`, increments, rest seconds, `form_cue`, flags (`is_bodyweight`, `is_optional`, `superset_group_id`, `is_superset_anchor`, `progression_hold_until_phase`, `max_weight` — equipment ceiling, default 80, nullable = no cap, see `.claude/rules/progression.md` § Equipment ceiling — `is_active` — false excludes from workout generation but retains history, used for retiring an exercise without deleting/renaming it).
- **`exercise_state`** — per exercise: `set1/2/3_weight`, `progression_state` enum (incl. terminal `'maxed'`), `consecutive_failures`.
- **`sessions`** / **`session_sets`** — per gym visit / per set. `target_reps` snapshotted at log time. A set is `completed` (has `actual_reps`) or `skipped` (has `skip_reason`); CHECK constraint enforces the pairing.
- **`cycle_plan`** — 56 rows (7 phases × 8 days): run miles, `target_cadence`, rehab exercise + timing, `is_lift_day`. Cadence targets (180 spm) are displayed in the UI on run-day cards but actual cadence is not logged — see Open Items.
- **`plan_state`** (singleton) — rehab cursor: `current_phase`, `current_cycle_day` (1–8), `current_gym_day` (1–3), counters, `in_deload`, `deload_started_on`, `last_cycle_outcome` ('clean'/'neutral'/'dirty'); plus `rom_stage` (1–3: 45°/60°/Full ROM) and `rom_stage_started_on` — **ROM stage is an independent clock**, not tied to phase transitions.
- **`plan_config`** (singleton) — all tunable thresholds. **Read at runtime — never hard-code.**
- **`daily_log`** — per calendar day: pain (1–5), `joint_fullness`, run/rehab completion, `run_outcome`.
- **`v_readiness`** → green/amber/red. **`v_phase_ready`** → boolean.

Singletons enforced by `singleton_guard BOOLEAN UNIQUE`.

## Core logic contracts

Read `.claude/rules/progression.md` when working on the progression engine, amber suppression, or exercise skipping.
Read `.claude/rules/rehab.md` when working on the rehab cursor, flare handling, or readiness gate.
Read `.claude/rules/frontend.md` when working on JS conventions, render model, timers, or styling.

**Progression engine** (`runProgressionEngine`, `progressionVariant`, `classicTargets`, `repFloor`): two modes (rep-ladder vs classic catch-up); catch-up advances set3→set2→set1; 5 lb increments only; opt-in via user confirmation; stall/deload automatic. Deload freeze applies to **knee-loading exercises only** (`isKneeLoading`), not blanket. ROM depth gate (`progression_hold_until_phase`) keys off `rom_stage`, not `current_phase` — front squats and single-leg bench squat require `rom_stage = 3` (Full ROM), independent of phase advance.

**Rehab cursor** (`advanceCycleDay`): **fully decoupled from lift completion** — one cycle-day per completed rehab+run session. Deferred via `lift_cycle_day_pending`; applied next morning independently of `lift_gym_day_pending`. `current_gym_day` advances only on actual lift completion. Day-8 roll: dirty/neutral/clean three-state evaluation; clean cycles bank toward phase advance (up to phase 7).

**Flare + deload** (`evaluateFlare`, `applyFlareConsequences`): *full flare* = pain ≥ threshold, swelling, or `run_outcome = 'flagged'` → 1st flare triggers relative-rest deload (freeze knee-loading progression, cap run, suppress plyos; non-knee-loading work continues). 2nd flare before a clean cycle → regress one phase. *Niggle-skip* (`markNiggleFlare`) marks cycle dirty only — does NOT trigger deload or regression.

**Readiness gate**: green = full progression; amber = knee-loading exercises held flat, non-knee-loading exercises progress normally; red = regress.

## Invariants (never change without confirmation)

- **Local date only:** `localDateStr()` for all `log_date` comparisons. Never `toISOString()`.
- **Two independent deferred advances:** `lift_cycle_day_pending` (written by `maybeWriteCycleDayAdvance` when rehab+run done; triggers `advanceCycleDay()` next morning) and `lift_gym_day_pending` (written by `finishSession` when lift completes; triggers `current_gym_day` cursor update next morning). They are independent — the cycle can advance without a lift having happened. Do not conflate or re-merge them.
- **Cycle cursor is per-rehab+run session, not per-date and not per-lift.** Missing a lift does not stall the run program. `current_gym_day` advances only on actual lift completion.
- **`current_gym_day` never resets.** It can lag behind the cycle cursor by any number of days.
- **`plan_config` is the single source for thresholds.**
- **Schema comments are authoritative.** When `index.html` logic and a schema comment disagree, the comment wins — reconcile, don't guess.
- **Settled design decisions:** progression math, flare/deload/regression model, ROM-gating, rest timers (60 s / 180 s), superset rules. Don't re-litigate. Ask Ben for genuinely open questions (e.g. coach UX layer).

## Working on this project

- No build step: open `index.html` in a browser or `npx serve .`. No tests, linter, or package manager.
- `sw.js` requires a local server (not `file://`) for service worker registration.
- Schema changes: new numbered migration in `supabase/migrations/` — don't edit `schema.sql` against a live DB. `OR REPLACE` can't add columns to a view — DROP + CREATE (see migration 002).
- Git remote: `github.com/benzr-619/Lifting-App`.

## Open items

- **RLS** — anon key is public; verify policies before multi-user exposure.
- **Coach UX** on daily check-in is undesigned. Keep rules-based (no LLM) unless decided otherwise.
- **Cadence tracking gap** — `target_cadence` (180 spm) is stored in `cycle_plan` and displayed on the run card as advisory info, but actual cadence achieved is not logged anywhere. Evidence base rates cadence retraining as the single highest-yield gait intervention (Bramah et al., 2025 meta-analysis). Consider adding a post-run cadence log field.
- Deferred: LM Studio + Qwen for AI analysis.
