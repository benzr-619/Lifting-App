-- Adds stance-based progression type for exercises like Plank with shoulder taps.
-- Stance codes stored in set1/2/3_weight: 1 = shoulder width, 2 = feet together.
-- progression_type = 'stance' gates the stance engine in runProgressionEngine.

ALTER TABLE lift.exercises
  ADD COLUMN IF NOT EXISTS progression_type TEXT NOT NULL DEFAULT 'weight';

UPDATE lift.exercises
  SET progression_type = 'stance'
  WHERE name = 'Plank with shoulder taps';

-- Set initial stance state: sets 1+2 at shoulder width (1), set 3 at feet together (2).
-- catch_up_set2 = set 2 is next to advance to feet together.
UPDATE lift.exercise_state
  SET set1_weight      = 1,
      set2_weight      = 1,
      set3_weight      = 2,
      progression_state = 'catch_up_set2'
  WHERE exercise_id = 'a2000005-0000-0000-0000-000000000000';
