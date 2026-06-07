# Phases 4–7 Design: Base Build Extension

This document captures the design for extending the rehab/run plan beyond Phase 3, building from ~12–14 miles/week to a 35 miles/week training base. It was designed to be implemented as additional rows in `cycle_plan` (days 25–56) with corresponding schema changes.

## Schema Changes Required

- `cycle_plan`: extend `day_number` CHECK to `BETWEEN 1 AND 56`
- `plan_state.current_phase`: relax CHECK from `BETWEEN 1 AND 3` to `BETWEEN 1 AND 7`
- `v_phase_ready`: currently hardcodes `current_phase < 3` — update to `current_phase < 7`
- Phase semantics shift at Phase 4: no longer ROM-gated rehab stages, now training load stages. Clean-cycle advancement logic (2 consecutive clean cycles) still applies unchanged.
- `deload_run_mile_cap` (currently 2.0 mi) becomes too aggressive for Phases 6–7 where easy days are 4.5+ miles. Consider a per-phase cap or percentage-based cap.

---

## Phase 4 — Consolidation (~22 mi/cycle)

**Goal:** Longer top-end runs, same 5 run days per cycle, prove Phase 3 gains held.

| Day | Miles | Lift | Rehab | Notes |
|-----|-------|------|-------|-------|
| 1 | 5.0 | ✓ | Plyometric warm-up (before run) | |
| 2 | 3.0 | — | Foot core (before run) | consecutive |
| 3 | — | ✓ | Weighted lateral step-downs 3×12 (after lift) | |
| 4 | 5.5 | — | Plyometric warm-up (before run) | |
| 5 | — | ✓ | Copenhagen adduction plank 3×8–10/side (after lift) | new |
| 6 | 4.0 | — | Plyometric warm-up (before run) | |
| 7 | 4.5 | ✓ | Comprehensive lower limb mobility (standalone) | |
| 8 | — | ✓ | Weighted lateral step-downs 3×12 (after lift) | |

**Total: 22 miles**

### Rehab Changes at Phase 4
- **Drop:** Isometric knee pre-load as prescribed exercise. Move to conditional only — re-appears in deload response if symptoms return, not the standard prescription.
- **Drop:** Goblet lateral band walks as primary (replace with Copenhagen).
- **Add:** Single-leg calf raises, eccentric emphasis 3×15 (off a step, slow lowering). Calf/Achilles complex needs to match mileage increase; weak plantarflexors → compensation at the knee.
- **Add:** Copenhagen adduction plank 3×8–10/side. Hip adductors are neglected in PFPS protocols; adductor weakness → pelvic drop on swing → lateral patella loading.
- **Add:** Terminal knee extension (TKE) with band 3×15. Loop band around rack at knee height, stand facing away, band behind knee, flex slightly then fully extend against resistance. Targets VMO in terminal extension — the exact range where patella tracking problems originate. Low fatigue, low risk. Keep as permanent fixture through Phase 7.
- **Keep:** Step-downs, plyometric warm-up, mobility, foot core.

---

## Phase 5 — 6th Run Day (~27 mi/cycle)

**Goal:** Add a 6th run day; introduce 3 consecutive days as a single trial.

| Day | Miles | Lift | Rehab | Notes |
|-----|-------|------|-------|-------|
| 1 | 5.5 | ✓ | Plyometric warm-up (before run) | |
| 2 | 3.5 | — | Foot core (before run) | consecutive |
| 3 | 4.0 | — | Light plyometric warm-up (before run) | consecutive — triple block |
| 4 | — | ✓ | Weighted lateral step-downs 3×12 (after lift) | |
| 5 | 6.0 | — | Plyometric warm-up (before run) | |
| 6 | 3.5 | ✓ | Copenhagen adduction plank 3×8–10/side (after lift) | |
| 7 | — | ✓ | Comprehensive lower limb mobility (standalone) | |
| 8 | 5.0 | — | Foot core (before run) | |

**Total: 27.5 miles**

The triple-consecutive-day block (days 1–3) is the key probe. PFPS load tolerance has been demonstrated in pairs; this is the next stress test.

### Rehab Changes at Phase 5
- **Add:** Soleus-specific calf raise — single-leg, bent-knee, 3×15. The bent-knee position is essential; straight-leg calf raises are mostly gastrocnemius. Soleus is the slow-twitch fatigue muscle hammered on long runs.
- **Add:** Banded hip flexion / psoas march 3×12. Hip flexor weakness (not just tightness) → quad works harder on swing phase → increased patellofemoral contact force. Supine, band around forefoot, bring knee toward chest against resistance.
- **Upgrade:** Step-downs → drop landings. Single-leg box drop, land on one leg, pause 2 sec, absorb fully. Loads deceleration more dynamically. Focuses on landing mechanics rather than eccentric quad load alone.
- **Reduce:** Foot core becomes a 2-minute warm-up drill, not a prescribed rehab session.

---

## Phase 6 — Strides + Quality Intro (~30 mi/cycle)

**Goal:** Longer single run; introduce strides (neuromuscular prep for workouts). No real tempo yet.

| Day | Miles | Lift | Rehab | Notes |
|-----|-------|------|-------|-------|
| 1 | 6.0 | ✓ | Plyometric warm-up (before run) | 6×20s strides at end of run |
| 2 | 4.0 | — | Foot core drill (before run) | easy consecutive |
| 3 | — | ✓ | Weighted step-downs 1×/cycle maintenance (after lift) | reduced frequency |
| 4 | 7.5 | — | Plyometric warm-up (before run) | long run |
| 5 | — | ✓ | Copenhagen adduction plank (after lift) | |
| 6 | 5.0 | — | A-skips + high knees 2×20m (before run) | strides |
| 7 | 4.5 | ✓ | Comprehensive lower limb mobility (standalone) | easy |
| 8 | 3.0 | — | Foot core drill (before run) | easy |

**Total: 30 miles**

### Rehab Changes at Phase 6
- **Add:** Running drills — A-skips + high knees 2×20m each. Dual purpose: neuromuscular running prep and continuation of plyometric work from Phase 3. "Rehab exercise" and "pre-run warm-up" are now the same thing.
- **Add:** Tibialis anterior strengthening — toe walks 2×20m or banded dorsiflexion 3×15. Shin splint prevention as mileage approaches 30 miles. Improves foot strike quality.
- **Reduce:** Step-downs to once per cycle (maintenance only).
- **Reduce:** Stand-alone isometric work entirely gone from prescription.

---

## Phase 7 — Workout Introduction (~35 mi/cycle)

**Goal:** One structured workout per cycle (fartlek). Long run reaches 10 miles. This is the 35 mi/week equivalent.

| Day | Miles | Lift | Rehab | Notes |
|-----|-------|------|-------|-------|
| 1 | 6.0 | ✓ | Pre-run activation (before run) | easy |
| 2 | 4.5 | — | Pre-run activation (before run) | easy consecutive |
| 3 | — | ✓ | Copenhagen adduction plank (after lift) | |
| 4 | 7.0 | — | Pre-run activation (before run) | fartlek: 6×3 min on / 2 min off |
| 5 | 4.5 | ✓ | Lateral band walks maintenance (after lift) | |
| 6 | — | ✓ | Comprehensive lower limb mobility (standalone) | |
| 7 | 10.0 | — | Pre-run activation (before run) | long run |
| 8 | 3.5 | ✓ | Pre-run activation (before run) | shake-out |

**Total: 35.5 miles**

### Rehab Changes at Phase 7
- **The "rehab slot" is now a pre-run activation routine (~8–10 min):** mini-band lateral walks 2×15, banded hip flexion march 1×12 each side, A-skips 2×20m, single-leg calf raises 1×10 each, short foot 30 sec each side. No longer treatment — this is what a trained runner does before a workout.
- The PFPS-specific content (VMO loading, valgus control) has been internalized into neuromuscular patterns by this point.
- Keep TKE in the activation routine permanently as a 1-set maintenance item.

---

## Rehab Exercise Progression Summary

| Phase | Added | Phased Out |
|-------|-------|------------|
| 1–3 | Isometric pre-load, foot core, lateral band walks, step-downs, plyos, mobility | — |
| 4 | Eccentric single-leg calf raise, Copenhagen adduction plank, TKE with band | Isometric pre-load (conditional only), goblet band walks as primary |
| 5 | Soleus calf raise (bent-knee), banded hip flexion/psoas march, drop landings | Foot core as dedicated session (becomes warm-up drill) |
| 6 | A-skips + high knees, tibialis anterior strengthening | Step-downs reduced to 1×/cycle; standalone isometrics gone |
| 7 | Pre-run activation routine (all consolidated) | Separate rehab block ends entirely |

---

## Lift-Awareness Design Note (deferred feature)

As mileage builds in Phases 4+, the 3-day lift cycle (1→2→3→1) can remain intact but the app should add context-aware hints rather than hard scheduling.

**Key insight:** the three gym days are not equally knee-loading:
- **Day 1** (single-leg RDL, bench, renegade rows, Russian twists) — low PFJ load. Available almost any day.
- **Day 2** (single-leg bench squat) — high PFJ load. Needs buffer from hard runs.
- **Day 3** (front squats) — high PFJ load. Needs buffer from hard runs.

**Proposed progression:**
- Phase 4: Day 1 available any day; Days 2/3 stay scheduled.
- Phase 5: Days 2/3 get soft-constraint treatment on easy run days only. Buffer maintained around long run + workout days.
- Phase 6–7: Only rule — heavy knee-dominant lifting (Days 2/3) should not precede the long run or the workout run.

**UX model:** Hint text, not blocking. "Day 3 includes front squats — your long run is tomorrow, consider waiting a day." The cycle still advances normally; the user makes the call.

**Important:** 3 sets of front squats or single-leg bench squats produces minimal muscle fatigue signal but meaningful PFJ load. Users (and this user specifically) may not feel overtaxed even when accumulating joint stress. Leg heaviness is a muscle signal, not a cartilage/synovium signal. The hint text should reflect this: frame it as joint load, not muscle fatigue.

**Not yet implementing:** Full context-aware reshuffling of runs around lift days. This requires a coupled optimization (lift availability ↔ run placement) that is significantly more complex and would risk breaking the clean cycle-plan progression. Deferred.

---

## What Comes After Phase 7

Phase 7 establishes the 35 mi/week base. The next design question (not answered here) is the transition from base-building into actual training — 2–3 run workouts per week, a long run of 12+ miles, and periodization. That's a separate planning conversation once Phase 7 is complete.
