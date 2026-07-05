-- Migration 005b: Extend daily_log.plan_phase CHECK to match plan_state (1–7)
-- The original schema capped at 3; migration 003 extended plan_state to 7 phases
-- but missed this constraint. Without the fix, phases 4-7 daily_log writes fail.
ALTER TABLE lift.daily_log DROP CONSTRAINT IF EXISTS daily_log_plan_phase_check;
ALTER TABLE lift.daily_log ADD CONSTRAINT daily_log_plan_phase_check
  CHECK (plan_phase BETWEEN 1 AND 7);
