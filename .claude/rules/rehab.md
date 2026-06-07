---
name: rehab-engine
description: Rehab cursor advance, flare/deload state machine, readiness gate semantics
metadata:
  type: project
---

# Rehab & Flare Engine

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

## Readiness gate
`v_readiness` returns green / amber / red from the latest check-in.
`v_phase_ready` returns a boolean phase-advance gate.

- **Green:** full progression, normal loads.
- **Amber:** knee-loading progression suppressed only (see `.claude/rules/progression.md`).
- **Red:** regress — apply regression logic before any session.
