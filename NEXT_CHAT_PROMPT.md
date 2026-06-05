# Continue building the Lift app — index.html implementation

I'm building a mobile-first PWA workout tracker (lifting split + PFPS rehab/run cycle) backed by Supabase. The database layer is finished; this chat is about implementing the app logic in `index.html`.

## Where things stand
- Folder: `/Users/ben/Documents/Vibe-Coding/Lift App/Lifting App/`
- `supabase/schema.sql` and `supabase/seed.sql` are **final and validated** (real working loads, progression states, the 24-day rehab cycle, and all the state/config tables). I have NOT run them in Supabase yet — I'll do that (schema first, then seed) before/when we test.
- `index.html` is a working UI shell (today view, workout view, set logging, rest timer) but does NOT yet implement the progression engine or the rehab state machine.
- Read `schema.sql`, `seed.sql`, and `index.html` first for full context. The schema comments document every rule in detail, and my settled design decisions are in memory (project + feedback notes). Don't burn time re-deriving the logic rules that are already worked out (progression math, the flare/deload/regression model, cycle gating) — treat those as given. But we're still early in a brand-new app, so questions about my intent, preferences, or UX direction are welcome and encouraged — please ask rather than guess when something is genuinely open.

## What to build (app-layer logic — the DB only stores state + tunable knobs in `plan_config`)
1. **Lift progression engine** — the catch-up state machine: rep-ladder vs classic catch-up, rep floor `ceil(goal×0.8)` / ceiling `goal+5`, catch-up order set3→set2→set1 (round up to nearest 5 lb), stall = 2 consecutive sessions under floor → deload set3 10% and re-enter catch-up. 5 lb increments only.
2. **Rehab cycle cursor** — advance one `current_cycle_day` (1–8) per completed session, not by calendar. Map to `cycle_plan` via `day_number = (current_phase-1)*8 + current_cycle_day`.
3. **Daily check-in** — morning: behavioral pain prompt → 1–5, plus patellar-sweep swelling → `joint_fullness`. Feeds the readiness gate and cycle evaluation.
4. **Readiness gate** (`v_readiness`) — show green/amber/red before a run or lift; amber = hold loads/mileage flat, red = regress.
5. **Flare → deload (relative rest, NOT full rest)** — on a flare (morning pain ≥ threshold, swelling, or niggle-skip): enter `in_deload` → cap run at `deload_run_mile_cap`, freeze lift progression, suppress plyometrics, KEEP isometrics + mobility. Exit when a clean morning check-in AND ≥ `flare_min_rest_days` passed; resume same cycle-day. 2nd flare in a phase (before a clean cycle) → regress one phase.
6. **Cycle evaluation at 8→1 roll** — clean (≤ max rest days, no flare) → `clean_cycles_completed +1`, advance phase at `clean_cycles_required`; incomplete (3+ rest days) → counter resets, stay put. See `v_phase_ready`.
7. **Skip-with-reason** — every set can be skipped (`set_status`/`skip_reason`); skips never advance progression or count as stalls. `niggle` skips feed the flare logic; `travel_equipment` skips are neutral.
8. **Finishers** — `is_optional` exercises render in a secondary section, never block session completion.
9. **Rest timers** — 60s (set1→2), 180s (set2→3), per-exercise override; timer shows next set's weight.
10. **Coach UX** — still undesigned. The daily check-in is the capture layer to build on. Let's sketch this together; keep it rules-based (no LLM) unless we decide otherwise.

## Constraints / preferences
- Supabase shared instance, `lift` schema namespace.
- Large tap targets, default reps pre-filled with +/- adjust, quick "Done" primary action.
- All gate thresholds live in `plan_config` — read them, don't hard-code.
- Keep me concise and direct.

Start by reading the three files, then propose an implementation order before writing code.
