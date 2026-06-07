# Build Prompt: Implement Phases 4–7

Read CLAUDE.md, .claude/rules/rehab.md, .claude/rules/frontend.md, .claude/rules/progression.md, and PHASES_4_7_DESIGN.md before doing anything else. PHASES_4_7_DESIGN.md is the source of truth for the new content.

The Supabase MCP is connected (project_id in CLAUDE.md). Use it throughout: inspect the live schema before writing SQL, apply the migration directly, and verify with queries after. Do not ask Ben to run SQL manually.

## Task

The app currently supports 3 rehab phases (`cycle_plan` days 1–24). Extend it to 7 phases (days 1–56), adding 4 new 8-day cycles that build run mileage from ~12–14 mi/week to a 35 mi/week training base.

---

## 1. Inspect before writing

Before drafting any SQL, use the Supabase MCP to confirm current live state:
- `list_migrations` — confirm which migrations have been applied and what the next number should be
- `execute_sql` on `lift.cycle_plan` — verify days 1–24 exist and the current CHECK constraint name
- `execute_sql` on `lift.plan_state` — confirm the current_phase CHECK constraint name
- `execute_sql` on `lift.v_phase_ready` — read the current view definition

Constraint names in the schema may differ from what's in schema.sql if earlier migrations renamed them. Use what you observe in the live DB, not what the file says.

---

## 2. New migration file

Create `supabase/migrations/003_phases_4_7.sql`, then apply it via the Supabase MCP `apply_migration` tool.

### Schema changes

**a. Extend `cycle_plan.day_number` CHECK** (use the constraint name confirmed above):
```sql
ALTER TABLE lift.cycle_plan DROP CONSTRAINT <confirmed_constraint_name>;
ALTER TABLE lift.cycle_plan ADD CONSTRAINT cycle_plan_day_number_check
  CHECK (day_number BETWEEN 1 AND 56);
```

**b. Extend `plan_state.current_phase` CHECK** (same — confirm name from live DB):
```sql
ALTER TABLE lift.plan_state DROP CONSTRAINT <confirmed_constraint_name>;
ALTER TABLE lift.plan_state ADD CONSTRAINT plan_state_current_phase_check
  CHECK (current_phase BETWEEN 1 AND 7);
```

**c. Rebuild `v_phase_ready`** — use DROP + CREATE, not OR REPLACE (adding a column, see migration 002 for pattern). Change `current_phase < 3` to `current_phase < 7`.

### Seed rows

Insert 32 new rows into `lift.cycle_plan` (days 25–56). The full day-by-day tables are in PHASES_4_7_DESIGN.md. Match the existing seed.sql INSERT format exactly.

Field notes:
- `run_notes`: consecutive-day markers, workout descriptions (e.g. `'fartlek: 6×3 min on / 2 min off'`), or NULL
- `target_cadence`: 180 on all run days, NULL on non-run days
- `rehab_exercise`: copy description strings verbatim from the design doc
- `rehab_timing`: check each row in the design doc — most run days use `'before_run'`, lift-only days use `'after_lift'` or `'standalone'`

---

## 3. Verify via Supabase MCP after applying

Run these queries before touching index.html:
```sql
-- Confirm all 56 rows present
SELECT count(*) FROM lift.cycle_plan;

-- Spot-check phase boundaries
SELECT day_number, run_miles, is_lift_day, rehab_exercise
FROM lift.cycle_plan
WHERE day_number IN (24, 25, 32, 33, 40, 41, 48, 49, 56)
ORDER BY day_number;

-- Confirm phase ceiling works
SELECT ready_to_advance FROM lift.v_phase_ready;
-- (manually test: update plan_state set current_phase=7, re-query, should be false, then restore)
```

---

## 4. Frontend changes (index.html)

Audit for hardcoded phase ceilings. Search for `< 3`, `=== 3`, `== 3`, `maxPhase`, and any UI strings implying Phase 3 is final.

- Update any phase ceiling references from 3 to 7
- `deload_run_mile_cap` is read from `plan_config` at runtime (not hardcoded) — no code change needed, but add a comment that it should be raised in the DB for later phases (2.0 mi is too aggressive when easy runs are 4–5 miles)

---

## What does NOT change

- The 3-day lift split (1→2→3→1) cycles independently of the rehab phase — unchanged
- Clean-cycle advancement logic (2 consecutive clean cycles to advance) applies identically to Phases 4–7
- Flare/deload/regression logic — unchanged, see `.claude/rules/rehab.md`
- `plan_config` thresholds — unchanged
- `is_lift_day` continues to mark prescribed lift days; Phases 4–7 prescribe 4–5 lift days per cycle, consistent with Phases 1–3
