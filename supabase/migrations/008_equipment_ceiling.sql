-- Migration 008: generic equipment ceiling
--
-- Ben's adjustable dumbbells max at 80 lbs/hand (he owns one pair). Most exercises
-- are years from that ceiling, so this is generic capping machinery only — no
-- per-exercise progression ladders beyond the ceiling exist (see
-- .claude/rules/progression.md § Equipment ceiling for the runtime behavior).

ALTER TABLE lift.exercises
  ADD COLUMN max_weight NUMERIC DEFAULT 80,           -- NULL = no cap
  ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT true; -- false = excluded from workout generation; history retained

-- Belt-and-suspenders backfill (ADD COLUMN ... DEFAULT already sets existing rows).
UPDATE lift.exercises SET max_weight = 80 WHERE max_weight IS NULL;

-- Terminal progression state: all sets at max_weight AND at the rep ceiling.
-- No auto-swap — the card just flags that the exercise needs a new progression plan.
ALTER TYPE lift.progression_state ADD VALUE 'maxed';
