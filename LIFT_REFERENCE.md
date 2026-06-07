# Lift App — Living Reference Document

> **For use in external AI projects / productivity OS.**
> Sections 1–5 describe the stable system. Section 6 (`## Current Status`) is the only section that should be overwritten periodically as your state changes.

---

## 1. Database Schema Summary

All tables live in the `lift` schema on a shared Supabase instance (project: `copzqbnjoakvcrvmedev`). The `public` schema is untouched.

### `exercises` — Static exercise library
Defines each exercise. Weights and progression state are stored separately.

| Column | Type | Purpose |
|---|---|---|
| `id` | uuid | PK |
| `name` | text | Exercise name |
| `gym_day` | 1/2/3 | Which of the 3-day split this belongs to |
| `day_order` | smallint | Order within the day (supersets share the same value) |
| `goal_reps` | smallint | Target reps per set |
| `increment_lbs` | smallint | Weight step (always 5 lbs) |
| `rest_short_seconds` | smallint | Rest after set 1 (default 60s) |
| `rest_long_seconds` | smallint | Rest after set 2 (default 180s) |
| `is_bodyweight` | bool | No weight tracked if true |
| `is_optional` | bool | Finisher — skippable, never feeds stall/deload logic |
| `superset_group_id` | uuid | Groups superset exercises; anchor drives weight |
| `is_superset_anchor` | bool | True on the exercise that controls the superset weight |
| `progression_hold_until_phase` | smallint | Suppress all advances while `current_phase` < this value (null = always progress) |

**🔑 Rehab relevance:** `progression_hold_until_phase` is the ROM gate — front squats and single-leg bench squats are locked to phase 3 because hitting goal reps at partial ROM (phases 1–2) is not a true progression signal.

---

### `exercise_state` — Per-exercise progression state
One row per exercise. Updated when progression is confirmed.

| Column | Type | Purpose |
|---|---|---|
| `exercise_id` | uuid | FK → exercises |
| `set1_weight`, `set2_weight`, `set3_weight` | smallint | Current working weights (null for bodyweight) |
| `progression_state` | enum | `ready` / `catch_up_set2` / `catch_up_set1` |
| `consecutive_failures` | smallint | Sets under rep floor in a row; triggers deload at 2 |

---

### `sessions` — Gym visit log
One row per workout. Use `started_at` (not `created_at` — that column doesn't exist) for date filtering.

| Column | Purpose |
|---|---|
| `gym_day` | Which split day (1/2/3) |
| `started_at` | Timestamp of session start |
| `completed_at` | Null if abandoned/incomplete |

---

### `session_sets` — Individual set log
The atomic workout data. Every set in every session.

| Column | Purpose |
|---|---|
| `set_number` | 1, 2, or 3 |
| `weight_lbs` | Null for bodyweight |
| `target_reps` | Snapshotted at log time (history stays accurate after progression) |
| `actual_reps` | Null when skipped |
| `set_status` | `completed` or `skipped` |
| `skip_reason` | `niggle` / `travel_equipment` / `other` |

**🔑 Rehab relevance:** `skip_reason = 'niggle'` triggers a flare flag. `travel_equipment` is neutral. Skipped sets never advance progression or count toward stalls.

---

### `cycle_plan` — The 24-day rehab blueprint
3 phases × 8 days = 24 rows. This is static reference data — the cursor into it lives in `plan_state`.

| Column | Purpose |
|---|---|
| `day_number` | 1–56 (computed: `(phase-1)*8 + cycle_day`) |
| `run_miles` | Prescribed distance (null = no run) |
| `target_cadence` | Steps/min target on run days |
| `is_lift_day` | Whether a gym session is prescribed |
| `rehab_exercise` | The day's rehab protocol text |
| `rehab_timing` | When to do it: `before_run` / `before_lift` / `after_lift` / `after_run` / `standalone` |

---

### `plan_state` — Rehab cursor (singleton)
One row. The live position in the rehab plan.

| Column | Purpose |
|---|---|
| `current_phase` | 1–7 |
| `current_cycle_day` | 1–8 within the current phase |
| `current_gym_day` | 1–3; advances independently, never resets on phase change |
| `current_cycle_rest_days` | Calendar days without a session this cycle |
| `clean_cycles_completed` | Consecutive clean 8-day cycles; gate for phase advance |
| `current_cycle_clean` | Flips false the moment a flare occurs this cycle |
| `phase_flare_count` | Flares in this phase since the last clean cycle |
| `in_deload` | True during relative rest after a flare |
| `deload_started_on` | Date; enforces minimum deload duration |

---

### `plan_config` — Tunable thresholds (singleton)
Never hard-code these values in logic — always read from this table.

| Column | Default | Meaning |
|---|---|---|
| `pain_dirty_threshold` | 4 | knee_pain_level ≥ this = flare |
| `clean_cycles_required` | 2 | Consecutive clean cycles needed to advance a phase |
| `max_rest_days_per_cycle` | 2 | More than this = incomplete cycle |
| `forgive_travel_skip` | true | Travel skips don't trigger a flare |
| `flares_before_regress` | 2 | Flares before phase regression |
| `flare_min_rest_days` | 2 | Minimum days in deload before exit allowed |
| `deload_run_mile_cap` | 2.0 | Max run distance while deloaded. **Auto-updated on phase advance:** Phase 6 → 4.0 mi, Phase 7 → 4.5 mi. Manually raise in `plan_config` before entering Phase 6 if auto-update hasn't fired. |
| `deload_freezes_progression` | true | Freeze lift weights during deload |
| `deload_suppress_plyo` | true | Replace plyometrics with isometrics during deload |

---

### `daily_log` — Morning check-in + post-run capture
One row per calendar day.

| Column | Purpose |
|---|---|
| `log_date` | The calendar date (always use local date, never `toISOString()`) |
| `plan_phase` / `plan_cycle_day` | Cursor snapshot at check-in time |
| `knee_pain_level` | 1–5 (1–2 = negligible; 3 = felt but settled; 4–5 = changed movement or lingered) |
| `joint_fullness` | Boolean — patellar sweep test positive = swelling present |
| `run_completed` | Whether a run happened |
| `run_actual_miles` | Actual distance logged |
| `run_outcome` | `clean` / `flagged` / null. `flagged` = sharp pain, altered gait, or early abort. Triggers a flare immediately. |
| `rehab_completed` | Whether the rehab exercise was done |

---

### Views

**`lift.v_readiness`** — Most recent check-in → `green` / `amber` / `red`
- Green: pain ≤ 2, no swelling, no flagged run
- Amber: pain = 3
- Red: pain ≥ 4 OR swelling OR `run_outcome = 'flagged'`

**`lift.v_phase_ready`** — Boolean: `clean_cycles_completed >= clean_cycles_required AND current_phase < 7`

---

## 2. Current Rehab / Training State

### Active Issue
**Patellofemoral Pain Syndrome (PFPS)** — knee rehab and structured return-to-run program.

### Rehab Phase
**Phase 1 of 7** — Load introduction. Running at 45° knee ROM, cadence-controlled. Focus on isometric pre-loading before runs, foot core work on lift days. No plyometrics yet.

Phases 1–3 are ROM-gated acute rehab stages. Phases 4–7 shift to training-load stages building from ~22 to ~35.5 miles per 8-session cycle. The same 2-consecutive-clean-cycles gate applies throughout.

### Current Cycle
- Cycle day **3 of 8** within Phase 1
- Plan day = (1-1)×8 + 3 = **plan row 3**
- Clean cycle so far: **yes** (no flares yet)
- Clean cycles banked: **0 of 2** needed to advance to Phase 2

### Full 7-Phase Plan Overview

| Phase | Plan Days | ~Miles/Cycle | Focus | Key Rehab Additions |
|---|---|---|---|---|
| **1** ← *current* | 1–8 | ~13 mi | Load intro, 45° ROM | Isometric pre-load, foot core, lateral band walks |
| 2 | 9–16 | ~15.5 mi | ROM increase to 60° | Plyos added, step-downs introduced |
| 3 | 17–24 | ~17 mi | Full ROM, plyos | Single-leg squat w/ valgus control |
| 4 | 25–32 | ~22 mi | Consolidation | Eccentric calf raises, Copenhagen plank, TKE with band; isometric pre-load dropped as primary |
| 5 | 33–40 | ~27.5 mi | 6th run day, triple consecutive block | Soleus calf raise, banded hip flexion/psoas march, drop landings |
| 6 | 41–48 | ~30 mi | Strides, long run to 7.5 mi | A-skips + high knees drills, tibialis anterior work; step-downs maintenance only |
| 7 | 49–56 | ~35.5 mi | Structured workout (fartlek), long run 10 mi | Pre-run activation routine consolidates all rehab; separate rehab block ends |

### Phase 1 Prescribed 8-Session Cycle (cycle runs per-session not per-calendar)

| Cycle Day | Plan Day | Run | Rehab Exercise | Timing | Lift Day |
|---|---|---|---|---|---|
| 1 | 1 | 3.0 mi @ 180 spm | 5×45s Isometric Knee Pre-Load | Before run | ✓ (gym day rotates) |
| 2 | 2 | — | Foot Core Strengthening | Before lift | ✓ |
| **3** ← *current* | **3** | **3.0 mi @ 180 spm** | **5×45s Isometric Knee Pre-Load** | **Before run** | **✗** |
| 4 | 4 | — | Heavy Goblet Lateral Band Walks (3×15) | After lift | ✓ |
| 5 | 5 | 3.5 mi @ 180 spm | 5×45s Isometric Knee Pre-Load | Before run | ✗ |
| 6 | 6 | — | Foot Core Strengthening | Before lift | ✓ |
| 7 | 7 | 3.5 mi @ 180 spm | 5×45s Isometric Knee Pre-Load | Before run | ✗ |
| 8 | 8 | — | Heavy Goblet Lateral Band Walks (3×15) | After lift | ✓ |

### Rehab Exercise Progression Across Phases

| Phase | Added | Phased Out |
|---|---|---|
| 1–3 | Isometric pre-load, foot core, lateral band walks, step-downs, plyos, mobility | — |
| 4 | Eccentric single-leg calf raise (3×15 off step), Copenhagen adduction plank (3×8–10/side), TKE with band (3×15 — permanent through Phase 7) | Isometric pre-load as primary (conditional deload-only); goblet band walks as primary |
| 5 | Soleus calf raise bent-knee (3×15), banded hip flexion/psoas march (3×12), drop landings | Foot core as dedicated session (becomes 2-min warm-up drill) |
| 6 | A-skips + high knees 2×20m, tibialis anterior (toe walks 2×20m or banded dorsiflexion 3×15) | Step-downs reduced to 1×/cycle maintenance; standalone isometrics gone |
| 7 | Pre-run activation (~8–10 min): mini-band lateral walks 2×15, banded hip march 1×12/side, A-skips 2×20m, single-leg calf raises 1×10/side, short foot 30s/side | Separate rehab block ends entirely |

### Current Exercise Weights & State

**Gym Day 1** (next after Day 2 sessions clear)

| Exercise | Set 1 | Set 2 | Set 3 | Goal Reps | State | Notes |
|---|---|---|---|---|---|---|
| Single-leg RDL | 60 | 70 | 75 | 10 | ready | — |
| Bench press | 45 | 50 | 60 | 12 | catch_up_set2 | Set 2 catching up to set 3 |
| Renegade rows | 20 | 25 | 30 | 10 | catch_up_set2 | — |
| Russian twists | 25 | 30 | 35 | 12 | catch_up_set2 | — |
| Lateral lunge *(optional)* | 30 | 30 | 30 | 12 | ready | — |

**Gym Day 2** ← *next gym session*

| Exercise | Set 1 | Set 2 | Set 3 | Goal Reps | State | Notes |
|---|---|---|---|---|---|---|
| Single-leg bench squat | 20 | 25 | 30 | 10 | catch_up_set2 | **HOLD until Phase 3** (partial ROM) |
| DB push press | 45 | 50 | 55 | 8 | ready | Knee-loading: amber-suppressed |
| Lateral raise | 10 | 10 | 15 | 15 | ready | Superset with Curl |
| Curl | 10 | 10 | 15 | 13 | ready | Superset with Lateral raise |
| Plank w/ shoulder taps | BW | BW | BW | 12 | ready | — |
| Y raise *(optional)* | 5 | 5 | 5 | 15 | ready | — |

**Gym Day 3**

| Exercise | Set 1 | Set 2 | Set 3 | Goal Reps | State | Notes |
|---|---|---|---|---|---|---|
| Front squats | 55 | 65 | 70 | 10 | catch_up_set1 | **HOLD until Phase 3** (partial ROM) |
| Bent-over rows | 40 | 45 | 45 | 10 | catch_up_set1 | — |
| Glute bridge | 65 | 70 | 75 | 15 | catch_up_set2 | — |
| Tricep extension | 40 | 45 | 45 | 15 | catch_up_set1 | — |
| Ab roller *(optional)* | BW | BW | BW | 10 | ready | — |

### Contraindicated / Modified Exercises
- **Front squats** — performed at partial ROM (45° phase 1, 60° phase 2). Weight progression locked until Phase 3 regardless of rep performance. Full progression resumes from Phase 3 onward.
- **Single-leg bench squat** — same hold until Phase 3.
- **Plyometrics** — not prescribed until Phase 3. If `in_deload = true`, plyos are suppressed regardless of phase (replaced by isometric pre-load).
- **Isometric knee pre-load** — primary prescription in Phases 1–3 only. From Phase 4 onward it's conditional: only reappears during a deload response if symptoms return.

### Knee-Loading Exercises (progression suppressed when readiness = amber)
Front squats, Single-leg bench squat, Romanian deadlift, DB push press. On an amber day these exercises are performed but weight does NOT advance even if goal reps are hit and user confirms.

---

## 3. Progression Logic

### Mode Selection (per exercise, per session)
If a 5 lb increment is more than 20% of set-3 weight → **rep-ladder mode** (lightweight exercises; weight advances only on explicit manual decision). Otherwise → **classic catch-up** state machine.

### Classic Catch-Up State Machine
Progression is always set3 first, then set2, then set1.

```
ready → catch_up_set2 → catch_up_set1 → ready → ...
```

- **Set 3 advance:** hit goal reps on set 3 → set3 += 5 lbs, enter `catch_up_set2`
- **Set 2 catch-up target:** `ceil(set3 × 0.9 / 5) × 5`
- **Set 1 catch-up target:** `ceil(set3 × 0.8 / 5) × 5`
- **Rep floor:** `ceil(goal_reps × 0.8)` — going below this is a failure
- **Rep ceiling:** `goal_reps + 5`

### Stall / Deload
- 2 consecutive sessions under rep floor on the evaluated set → auto-deload: set3 -= 10% (rounded to 5 lbs), re-enter `catch_up_set2`
- Counter lives in `exercise_state.consecutive_failures`

### Progression is Opt-In
The engine computes the next weight and displays it, but nothing is written to the DB until the user taps "Confirm progression" on set 3. Stall counting and deload regressions are automatic.

### Gates That Block Progression
1. `in_deload = true` AND `deload_freezes_progression = true` → all advances frozen
2. `progression_hold_until_phase` on the exercise AND `current_phase < that value` → advance suppressed
3. Readiness = amber AND exercise is knee-loading AND goal reps hit → early return, no DB write (not a stall either)
4. Skipped sets and bodyweight/optional exercises → never advance or count as stalls

### Signals to Advance a Phase
- Must complete 2 consecutive clean 8-day cycles (`clean_cycles_required` from `plan_config`)
- A cycle is clean if: no flare occurred AND rest days ≤ 2
- Gate is readable via `v_phase_ready.ready_to_advance`

### Signals to Regress
- 2nd flare in a phase before banking a clean cycle → step back one phase, reset all counters
- Readiness = red at session start → apply regression logic before proceeding

---

## 4. What's Safe to Write vs. Read

### Safe to write (external agent / productivity OS)

| Table | Safe operations | Notes |
|---|---|---|
| `daily_log` | INSERT one row per day | Log morning check-in: `knee_pain_level`, `joint_fullness`, `run_completed`, `run_actual_miles`, `run_outcome`, `rehab_completed`. Always use local date for `log_date`. |
| `sessions` | INSERT a new session row | Set `gym_day` and `started_at`; leave `completed_at` null until done. |
| `session_sets` | INSERT set rows into a session | Provide `set_status`, `weight_lbs`, `target_reps`, `actual_reps` (or `skip_reason`). |
| `sessions.completed_at` | UPDATE after all sets logged | Mark the session complete. |
| `sessions.notes` | UPDATE | Free-text notes on the session. |
| `daily_log.notes` | UPDATE | Add notes to an existing check-in. |

### Read-only (never write directly)

| Table/Object | Why |
|---|---|
| `exercise_state` | Updated by the progression engine only, after user confirmation. Writing weights directly bypasses the state machine and will corrupt progression. |
| `plan_state` | Updated by `advanceCycleDay` and flare logic in `index.html`. External writes will desync the rehab cursor. |
| `plan_config` | Threshold source of truth — only change deliberately via the app or a known migration. |
| `exercises` | Static library — changes are schema migrations, not runtime writes. |
| `cycle_plan` | Static blueprint — do not modify at runtime. |
| `v_readiness`, `v_phase_ready` | Views — read-only by nature. |

### Never touch
- `plan_state.in_deload`, `plan_state.current_phase`, `plan_state.phase_flare_count` — these are computed state managed by flare/deload logic. Writing them externally will break the rehab safety system.

---

## 5. How to Reorder or Substitute a Week

The rehab plan does **not** use calendar dates — it uses a session cursor. There is no "week" in the database; there is only "next session." The full plan is 56 sessions across 7 phases. Reordering is a matter of understanding the cursor and which sessions are pending.

### Finding "this week's" planned sessions

1. Read `plan_state.current_cycle_day` and `plan_state.current_gym_day`
2. Compute the current plan day: `(current_phase - 1) * 8 + current_cycle_day`
3. Look up that row in `cycle_plan` to find: run miles, rehab exercise, and whether it's a lift day
4. If `is_lift_day = true`, the gym session uses `current_gym_day`'s exercises from `lift.exercises`
5. To project the next N sessions, iterate cycle_day forward (wrapping 8→1 per cycle) and gym_day forward (1→2→3→1) independently

### Suggesting a swap or reorder

An agent cannot reorder the cursor itself (that would mean patching `plan_state`, which is unsafe). What it *can* do:

- **Inform**: "Today's plan is a 3.0-mile run with isometric pre-load before it, no lift. Your next gym day is Day 2 exercises."
- **Suggest a rest day**: If readiness is amber or red, suggest logging the day with no run/lift and incrementing `current_cycle_rest_days` awareness (the app handles the counter itself).
- **Flag substitutions**: If travel equipment is limited, note which exercises can be skipped with `skip_reason = 'travel_equipment'` without triggering a flare.
- **Propose a deload run**: If pain is at 3, a run can still happen at capped mileage (≤ 2.0 mi from `deload_run_mile_cap`), just log it and watch the next check-in.

### Logic walk-through: "Can I move today's gym day to tomorrow?"
1. Read `plan_state` — is today a lift day? (`cycle_plan.is_lift_day` for the current cursor)
2. If yes: skipping today adds 1 to `current_cycle_rest_days` — check if that would push it over `max_rest_days_per_cycle` (2). If we're at 1 rest day already, doing it tomorrow is the last safe skip in this cycle.
3. The gym day rotation (`current_gym_day`) doesn't change — day 2's exercises will still be next regardless of when you go.
4. Safe to defer: yes, as long as `current_cycle_rest_days` stays ≤ 2.

---

## Current Status

> **Last updated:** 2026-06-07
> **Update this section** after each morning check-in or whenever training state changes. All other sections are stable.

**Today:** Sunday, June 7, 2026

**Active issue:** PFPS rehab — structured return-to-run and strength program.

**Rehab phase:** Phase 1 of 7 (load introduction, 45° ROM, no plyometrics).

**Cursor position:** Cycle day 3 of 8, Phase 1 of 7. 0 clean cycles banked (need 2 to advance to Phase 2).

**Today's plan (cycle day 3):** Run day — 3.0 miles at 180 spm cadence. Do 5×45s Isometric Knee Pre-Load **before** the run. No gym session today.

**Next gym session:** Gym Day 2 exercises (Single-leg bench squat, DB Push Press, Lateral Raise + Curl superset, Plank w/ shoulder taps). Scheduled for next cycle day that is a lift day (cycle day 4).

**Readiness:** 🟢 GREEN — last check-in 2026-06-06: pain 1/5, no swelling.

**Pain trend (last 3 days):**
- 2026-06-06: 1/5 — green
- 2026-06-05: 3/5 — amber (no run that day)
- 2026-06-04: 1/5 — green

**Active modifications:** None. Not in deload. No flares this phase. All progressions live except ROM-gated holds on front squats and single-leg bench squat (Phase 3 unlock).

**Flags for an AI assistant:**
- Front squats and single-leg bench squat weight will NOT advance regardless of performance until Phase 3.
- DB push press weight suppressed on amber days.
- If pain hits 3 on check-in, readiness flips amber — flag it before recommending a hard session.
- If pain hits 4+, or swelling is present, or a run is flagged — that's a flare. Do not suggest advancing load.
- `deload_run_mile_cap` is currently 2.0 mi. This is appropriate for Phases 1–5. When entering Phase 6, it must be raised to 4.0 mi in `plan_config`. When entering Phase 7, raise to 4.5 mi. The app auto-sets this on phase advance, but verify if entering a phase manually.
