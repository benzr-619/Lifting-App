-- Migration 006: Add activity_type to daily_log
-- Tracks what was actually done in place of a scheduled run (e.g. tennis).
-- DEFAULT 'run' is backward-compatible; existing rows get 'run'.
-- run_completed semantics are unchanged — all entries here count as run_completed=true
-- for the purposes of the rehab cursor, readiness gate, and niggle-skip exemption.
ALTER TABLE lift.daily_log
  ADD COLUMN IF NOT EXISTS activity_type TEXT DEFAULT 'run'
  CHECK (activity_type IN ('run', 'tennis'));
