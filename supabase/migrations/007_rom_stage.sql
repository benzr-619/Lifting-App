-- Migration 007: independent ROM stage cursor
-- rom_stage advances on time elapsed (not phase), resets clock on any flare.
-- Front squats and single-leg bench squat hold weight progression until rom_stage = 3.

ALTER TABLE lift.plan_state
  ADD COLUMN rom_stage SMALLINT NOT NULL DEFAULT 1 CHECK (rom_stage BETWEEN 1 AND 3),
  ADD COLUMN rom_stage_started_on DATE;

ALTER TABLE lift.plan_config
  ADD COLUMN rom_stage_min_days SMALLINT NOT NULL DEFAULT 28;

-- Seed: PFPS program started 2026-06-04 (earliest daily_log row, matches plan_started_at)
UPDATE lift.plan_state SET rom_stage = 1, rom_stage_started_on = '2026-06-04';
UPDATE lift.plan_config SET rom_stage_min_days = 28;
