-- 034_add_resting_hr_to_profiles.sql
-- Stores each user's resting heart rate so virtual run partners can compute
-- accurate personalised HR zones using the Karvonen method.

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS resting_hr INT;

COMMENT ON COLUMN profiles.resting_hr IS
  'Resting heart rate in BPM (from HealthKit). Used for Karvonen HR zone calculation.';
