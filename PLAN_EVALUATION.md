# Lift + PFPS Rehab Plan — Sports-Science Evaluation

Review of the updated `Strength_Tracking_Ramping_Sets.xlsx` and `Cycle Through Days.xlsx` against `seed.sql`/`schema.sql`, before re-seeding Supabase. Goal: flag what's sound, what to change, and what belongs in the app vs. what's really planning guidance.

---

## 1. The strength plan

### What's good
- **Exercise selection is genuinely well-targeted for PFPS + proximal hamstring.** Single-leg RDL (hamstring tendon loading without snapping), single-leg bench squat and front squats (closed-chain quad/glute with upright torso to reduce patellofemoral shear), glute bridge (offloads the high hamstring), and the band walks/step-downs in the cycle (glute-med) cover the right chain. No notes needed — this is a coherent knee/hip program.
- **Form cues are excellent** and worth keeping verbatim in the app. They're the kind of internal/external focus prompts that actually change movement quality.
- **The catch-up progression logic is working as designed.** The places where the "Next" column diverges from the logged Set columns (Renegade set 3 → 30, Front squat set 2, Glute bridge set 1, Tricep set 2, curl "15,15/13") are exactly the catch-up / ready-to-advance states the state machine predicts. That's a good sign the logic survives contact with real data.

### Where the science suggests a change

**1. The ascending ramp (~80/90/100%) under-loads the working sets for tendon rehab.**
With only three sets and each ramping up, just the top set is truly heavy. For tendon healing (proximal hamstring, patellar) the evidence base — Heavy Slow Resistance (Kongsgaard, Beyer) — points to *heavy* loads held under *slow tempo* (≈3 s up / 3 s down), 6–15RM, 3×/week, where most sets are challenging. Your scheme is fine as a strength-builder, but if tendon remodeling is the priority, consider either (a) tightening the ramp (e.g. 90/95/100%) so sets 1–2 aren't junk volume, or (b) adding a tempo prescription. **Recommendation:** capture a `tempo` field per exercise and a flag for which lifts are "tendon-rehab" (slow tempo enforced) vs. general.

**2. Some session-to-session jumps are large.** Single-leg RDL moved 45/50/60 → 60/70/75 and Front squats 35/40/45 → 55/60/70 versus the old seed. If those reflect *current actual* lifting, great. If they're targets, note that they exceed your own stall/deload logic's implied ~10% step. Worth confirming these are real working weights before seeding, since the progression engine assumes the seed reflects reality.

**3. Rep targets are mixed (8/10/12/15) across lifts.** That's fine and intentional, but it means "goal_reps" alone drives the rep-ladder math differently per lift. No change needed — just confirming the floor/ceiling formulas (`ceil(goal×0.8)` / `goal+5`) behave sensibly at goal=8 (floor 7, ceiling 13) which they do.

### Recomputed progression states (from the new logged weights)
Using your documented rule (5/set3 > 20% → rep-ladder/ready; else classic catch-up):

| Exercise | Sets (1/2/3) | State |
|---|---|---|
| Single-leg RDL | 60/70/75 | ready |
| Bench press | 45/50/55 | ready |
| Renegade rows | 20/25/25 | ready (set3 ready to advance → 30) |
| Russian twists | 25/30/30 | ready |
| Single-leg bench squat | 20/25/30 | **catch_up_set2** |
| DB push press | 45/50/55 | ready |
| Lateral raise (anchor) | 10/10/15 | ready (rep-ladder) |
| Curl | 10/10/15 | ready (rep-ladder) |
| Front squats | 55/60/70 | **catch_up_set2** |
| Bent-over rows | 40/40/45 | **catch_up_set2** |
| Glute bridge | 60/70/75 | ready |
| Tricep extension | 40/40/45 | **catch_up_set2** |

(These differ from the current `seed.sql`, which used the old, lighter weights. I have not written them yet — that's the re-seed step once you confirm.)

---

## 2. The finishers / optional exercises

The sheet now includes **Lateral Lunge, Y-raise, and Ab roller** as "Optional," but the schema has no concept of an optional/finisher exercise — `gym_day` is `CHECK (1,2,3)` and every row is treated as a core lift.

**Recommendation (app):** add an `is_optional BOOLEAN` (or `slot TEXT` = 'core' | 'finisher') to `lift.exercises`. Render finishers in a collapsed/secondary section so they don't block session completion and don't feed the stall logic. Map them: Lateral Lunge → Day 1, Y-raise → Day 2, Ab roller → Day 3.

---

## 3. The 84-day rehab/run cycle

### What's good
- **Cadence work (180 BPM)** is a legitimate, well-supported PFPS intervention — raising step rate reduces patellofemoral joint stress. One nuance: 180 is a heuristic; the evidence is really "+5–10% over your *self-selected* cadence." If 180 isn't ~5–10% above your natural rate, the target should be personalized. Consider storing a `target_cadence` rather than hard-coding 180 in labels.
- **Isometric knee pre-load (5×45s)** before runs/lifts is sound — isometrics give short-term analgesia and activation. Good as a warm-up primer.
- **Periodization is thoughtful:** load builds 3.0→4.5 mi, consecutive-day tolerance trials appear in phase 2 (day 9→10), and plyometrics (single-leg hops, bounding) are correctly deferred to phase 3 as return-to-run prep. The arc is clinically reasonable.
- **The new Before/After rehab timing is physiologically correct.** Pre-load isometrics *before* activity; heavy band walks and step-downs *after* the main session so you're not pre-fatiguing stabilizers. Keep it.

### Where the science suggests a change or a flag

**1. You removed the ROM-restriction notes — confirm that's intentional.** The old `seed.sql` carried "Restricted 0–45° ROM" early, then progressively opened depth (60° → full depth ~80% 1RM by phase 3). That graded-ROM progression is a *core* PFPS principle (limit deep knee flexion early to cap patellofemoral stress, then earn depth). The updated sheet drops it. If you intend to drop ROM limiting, that's a real clinical change worth a second thought; if you just didn't want it as a *day label*, keep it as exercise-level guidance instead. **Recommendation:** keep ROM progression as a `gym_notes`/phase field rather than deleting it.

**2. Effusion / "joint fullness" checks (days 10, 18) are the most important safety signal and currently have nowhere to live.** Swelling 24 h post-load is the classic "you overdid it" marker. `daily_log` tracks `knee_pain_level (1–5)` but not swelling. **Recommendation (app):** add `joint_fullness BOOLEAN` (or a 1–5 effusion scale) to `daily_log`, and prompt for it on the days the plan flags.

**3. Make progression pain-gated, not just calendar-gated.** PFPS rehab should follow a "traffic light" rule (pain during/after ≤ ~3/10 and settling by next day = OK to progress; higher = hold/regress). Right now the plan advances on schedule and the weight engine advances on reps — neither consults `knee_pain_level`. You don't need full automation, but the app should at minimum *surface* recent pain/swelling before suggesting a mileage bump, and ideally hold the run progression if pain is trending up. This is the single highest-value rule to add.

**4. Weekly mileage ramp — sanity-check against ~10%/week.** Across each 8-day block the running volume rises reasonably, but the phase-2/3 jumps (e.g. introducing 4.5 mi plus consecutive days) compress load. Not necessarily wrong post-rehab, but worth tracking actual vs. prescribed weekly miles (which `daily_log.run_actual_miles` already supports) and watching for spikes.

---

## 4. App vs. planning — what goes where

**Capture in the app (structured data):**
- Per-exercise: weights, goal reps, progression state, **tempo**, **is_optional/finisher flag**, form cue (keep).
- Cycle day: run miles, gym day, rehab exercise, **rehab timing (before/after)**, **ROM/phase note**, **target cadence**.
- Daily log: pain (have it), **swelling/joint-fullness (add)**, run completed + actual miles (have it), rehab done (have it).

**Keep as worded guidance, not rigid app logic:**
- The "180 BPM" target → store a personalized cadence number; treat 180 as a default, not a law.
- "Consecutive-day trial / monitor for 24-hr fullness" → these are *decision rules*, best surfaced as a prompt ("how did yesterday feel?") rather than auto-advancing.
- ROM progression → guidance text tied to phase, reviewed by feel, not a hard gate.

**Reword for clarity:**
- "Active Recovery (No Lifting)" is doing two jobs (it's both "no gym today" and "go easy"). In the app, `gym_day = NULL` already means no lifting; the *label* should just say "Active recovery" so it's not redundant.
- Curl set 3 "15,15/13" — the curl can't match the lateral raise's rep target. Since the schema stores `goal_reps` per exercise, set the curl's goal honestly (e.g. 13) rather than carrying the "/13" annotation as the anchor's note.

---

## Suggested next steps
1. Confirm the larger weight jumps are real working loads (not targets).
2. Decide whether ROM progression stays (I'd keep it as phase guidance).
3. Approve the small schema additions: `tempo`, `is_optional`, `joint_fullness`, `target_cadence`/personalized cadence, ROM/phase note.
4. Then I'll regenerate `seed.sql` with the new weights + recomputed states and patch `schema.sql` accordingly.

*Note: this evaluation reflects general sports-science and PFPS rehab principles, not individualized medical advice — worth a sanity-check with your PT, especially on dropping the ROM limits.*
