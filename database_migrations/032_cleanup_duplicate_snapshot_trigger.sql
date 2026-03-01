-- 032: Clean up duplicate snapshot rate-limit trigger
--
-- Migration 024 created trigger `enforce_snapshot_rate_limit` on virtual_run_snapshots.
-- Migration 026 replaced it with `trg_check_snapshot_plausibility` but only dropped
-- `trg_check_snapshot_rate_limit` (wrong name), leaving the 024 trigger active.
-- This causes double validation on snapshot updates.

DROP TRIGGER IF EXISTS enforce_snapshot_rate_limit ON virtual_run_snapshots;
DROP FUNCTION IF EXISTS check_snapshot_rate_limit();
