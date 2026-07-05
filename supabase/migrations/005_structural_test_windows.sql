-- Migration 005: Neutral cycle state for structural test validity
--
-- Adds lift.structural_test_windows — a data-driven registry of back-to-back
-- run blocks that must be executed on consecutive calendar days to count as a
-- valid (clean) cycle pass. Cycles that fail a window with no flare → Neutral:
-- clean_cycles_completed stays unchanged; cycle simply repeats.
--
-- Also adds last_cycle_outcome to plan_state so the UI can display the result
-- of the most recently completed cycle (clean / neutral / dirty).

-- ----------------------------------------------------------
-- 1. Structural test windows table
-- ----------------------------------------------------------
CREATE TABLE lift.structural_test_windows (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  phase            SMALLINT    NOT NULL CHECK (phase BETWEEN 1 AND 7),
  start_cycle_day  SMALLINT    NOT NULL CHECK (start_cycle_day BETWEEN 1 AND 8),
  end_cycle_day    SMALLINT    NOT NULL CHECK (end_cycle_day BETWEEN 1 AND 8),
  description      TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT stw_day_range_check CHECK (end_cycle_day > start_cycle_day)
);

CREATE INDEX ON lift.structural_test_windows (user_id, phase);

-- ----------------------------------------------------------
-- 2. RLS
-- ----------------------------------------------------------
ALTER TABLE lift.structural_test_windows ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own structural_test_windows" ON lift.structural_test_windows;
CREATE POLICY "Users manage own structural_test_windows"
  ON lift.structural_test_windows FOR ALL
  TO authenticated
  USING  (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ----------------------------------------------------------
-- 3. Seed windows for Ben
--    Phase 2, days 1→2 : 4.0 mi then 2.0 mi back-to-back
--    Phase 5, days 1→3 : triple consecutive-day block (5.5→3.5→4.0 mi)
-- ----------------------------------------------------------
INSERT INTO lift.structural_test_windows
  (user_id, phase, start_cycle_day, end_cycle_day, description)
VALUES
  ('1438970f-eff7-4a02-906a-072acd711f86', 2, 1, 2,
   'Day1(4.0mi)->Day2(2.0mi) back-to-back run test'),
  ('1438970f-eff7-4a02-906a-072acd711f86', 5, 1, 3,
   '3-day consecutive run block (5.5->3.5->4.0mi)');

-- ----------------------------------------------------------
-- 4. Track last cycle outcome on plan_state for UI display
-- ----------------------------------------------------------
ALTER TABLE lift.plan_state
  ADD COLUMN IF NOT EXISTS last_cycle_outcome TEXT
    CHECK (last_cycle_outcome IN ('clean', 'neutral', 'dirty'));
