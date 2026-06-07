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
| `supabase/migrations/002_run_outcome.sql` | Adds `daily_log.run_outcome`, rebuilds `v_readiness`. **Not yet applied to live DB.** |
| `Strength_Tracking_Ramping_Sets.xlsx`, `Cycle Through Days.xlsx` | Source of truth for initial weights/plan. Confirm with Ben before regenerating seed. |
| `NEXT_CHAT_PROMPT.md`, `PLAN_EVALUATION.md` | Design/handoff notes. |

## Data model (`lift` schema)

- **`exercises`** — static config: `gym_day` (1–3), `day_order`, `goal_reps`, increments, rest seconds, `form_cue`, flags (`is_bodyweight`, `is_optional`, `superset_group_id`, `is_superset_anchor`, `progression_hold_until_phase`).
- **`exercise_state`** — per exercise: `set1/2/3_weight`, `progression_state` enum, `consecutive_failures`.
- **`sessions`** / **`session_sets`** — per gym visit / per set. `target_reps` snapshotted at log time. A set is `completed` (has `actual_reps`) or `skipped` (has `skip_reason`); CHECK constraint enforces the pairing.
- **`cycle_plan`** — 24 rows (3 phases × 8 days): run miles, cadence, rehab exercise + timing, `is_lift_day`.
- **`plan_state`** (singleton) — rehab cursor: `current_phase`, `current_cycle_day` (1–8), `current_gym_day` (1–3), counters, `in_deload`, `deload_started_on`.
- **`plan_config`** (singleton) — all tunable thresholds. **Read at runtime — never hard-code.**
- **`daily_log`** — per calendar day: pain (1–5), `joint_fullness`, run/rehab completion, `run_outcome`.
- **`v_readiness`** → green/amber/red. **`v_phase_ready`** → boolean.

Singletons enforced by `singleton_guard BOOLEAN UNIQUE`.

## Core logic contracts

Read `.claude/rules/progression.md` when working on the progression engine, amber suppression, or exercise skipping.
Read `.claude/rules/rehab.md` when working on the rehab cursor, flare handling, or readiness gate.
Read `.claude/rules/frontend.md` when working on JS conventions, render model, timers, or styling.

**Progression engine** (`runProgressionEngine`, `progressionVariant`, `classicTargets`, `repFloor`): two modes (rep-ladder vs classic catch-up); catch-up advances set3→set2→set1; 5 lb increments only; opt-in via user confirmation; stall/deload automatic.

**Rehab cursor** (`advanceCycleDay`): one cycle-day per completed session (not calendar). On day-8 roll, evaluates cycle for cleanliness; clean cycles bank toward phase advance.

**Flare + deload** (`evaluateFlare`, `markNiggleFlare`): flare = pain ≥ threshold, swelling, niggle-skip, or flagged run. 1st flare → relative rest deload. 2nd flare before a clean cycle → regress one phase.

**Readiness gate**: green = go; amber = knee-loading exercises held flat only; red = regress.

## Invariants (never change without confirmation)

- **Local date only:** `localDateStr()` for all `log_date` comparisons. Never `toISOString()`.
- **Deferred day-advance:** finishing a workout writes `lift_advance_pending` to `localStorage`; `loadBootData()` applies it the next calendar day. Do not make this immediate.
- **Cursor is per-session, not per-date.** Rest days don't break cycles. `current_gym_day` never resets.
- **`plan_config` is the single source for thresholds.**
- **Schema comments are authoritative.** When `index.html` logic and a schema comment disagree, the comment wins — reconcile, don't guess.
- **Settled design decisions:** progression math, flare/deload/regression model, ROM-gating, rest timers (60 s / 180 s), superset rules. Don't re-litigate. Ask Ben for genuinely open questions (e.g. coach UX layer).

## Working on this project

- No build step: open `index.html` in a browser or `npx serve .`. No tests, linter, or package manager.
- `sw.js` requires a local server (not `file://`) for service worker registration.
- Schema changes: new numbered migration in `supabase/migrations/` — don't edit `schema.sql` against a live DB. `OR REPLACE` can't add columns to a view — DROP + CREATE (see migration 002).
- Git remote: `github.com/benzr-619/Lifting-App`.

## Open items

- **Migration 002** not yet applied to live Supabase (`run_outcome` + flagged-run flare).
- **RLS** — anon key is public; verify policies before multi-user exposure.
- **Coach UX** on daily check-in is undesigned. Keep rules-based (no LLM) unless decided otherwise.
- Deferred: LM Studio + Qwen for AI analysis.
