-- Migration 002: add run_outcome to daily_log + update v_readiness
-- Run this against your live Supabase instance (schema already applied).
-- -----------------------------------------------------------------------

-- 1. Add the new column (NULL on existing rows = no run recorded that day)
ALTER TABLE lift.daily_log
  ADD COLUMN run_outcome TEXT
    CHECK (run_outcome IN ('clean', 'flagged'));

-- 2. Rebuild v_readiness to treat run_outcome = 'flagged' as a red signal
-- (DROP + CREATE because OR REPLACE can't add columns to an existing view)
DROP VIEW IF EXISTS lift.v_readiness;
CREATE VIEW lift.v_readiness AS
SELECT
  dl.log_date,
  dl.knee_pain_level,
  dl.joint_fullness,
  dl.run_outcome,
  CASE
    WHEN COALESCE(dl.joint_fullness, false)
      OR dl.knee_pain_level >= 4
      OR dl.run_outcome = 'flagged'                                    THEN 'red'
    WHEN dl.knee_pain_level = 3                                        THEN 'amber'
    ELSE 'green'
  END AS readiness
FROM lift.daily_log dl
ORDER BY dl.log_date DESC
LIMIT 1;
