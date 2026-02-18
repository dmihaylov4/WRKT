-- P0 fixes for virtual runs:
-- 1. Enable Realtime on virtual_runs (for invite detection)
-- 2. Concurrent active run guard (partial unique indexes)
-- 3. Server-side run completion RPC (correct winner calculation)
-- 4. Drop lat/lon from snapshots (strip location)
-- 5. DELETE deny policy on snapshots

-- =============================================================
-- 1a. Enable Realtime on virtual_runs table
-- =============================================================
ALTER PUBLICATION supabase_realtime ADD TABLE virtual_runs;
ALTER TABLE virtual_runs REPLICA IDENTITY FULL;

-- =============================================================
-- 1b. Concurrent active run guard (partial unique indexes)
-- =============================================================
CREATE UNIQUE INDEX idx_unique_active_inviter
  ON virtual_runs (inviter_id) WHERE status = 'active';
CREATE UNIQUE INDEX idx_unique_active_invitee
  ON virtual_runs (invitee_id) WHERE status = 'active';

-- =============================================================
-- 1c. Server-side run completion RPC function
-- =============================================================
CREATE OR REPLACE FUNCTION complete_virtual_run(
  p_run_id UUID,
  p_user_id UUID,
  p_distance_m DOUBLE PRECISION,
  p_duration_s INTEGER,
  p_avg_pace_sec_per_km INTEGER DEFAULT NULL,
  p_avg_heart_rate INTEGER DEFAULT NULL
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_run virtual_runs;
  v_is_inviter BOOLEAN;
  v_inviter_dist DOUBLE PRECISION;
  v_invitee_dist DOUBLE PRECISION;
  v_winner UUID;
BEGIN
  -- Lock the row to prevent race conditions
  SELECT * INTO v_run FROM virtual_runs WHERE id = p_run_id FOR UPDATE;

  IF v_run IS NULL THEN
    RAISE EXCEPTION 'Run not found';
  END IF;

  IF v_run.status != 'active' THEN
    RAISE EXCEPTION 'Run is not active (status: %)', v_run.status;
  END IF;

  -- Determine if caller is inviter or invitee
  v_is_inviter := (p_user_id = v_run.inviter_id);

  -- Update the caller's stats
  IF v_is_inviter THEN
    UPDATE virtual_runs SET
      inviter_distance_m = p_distance_m,
      inviter_duration_s = p_duration_s,
      inviter_avg_pace_sec_per_km = p_avg_pace_sec_per_km,
      inviter_avg_heart_rate = p_avg_heart_rate
    WHERE id = p_run_id;
  ELSE
    UPDATE virtual_runs SET
      invitee_distance_m = p_distance_m,
      invitee_duration_s = p_duration_s,
      invitee_avg_pace_sec_per_km = p_avg_pace_sec_per_km,
      invitee_avg_heart_rate = p_avg_heart_rate
    WHERE id = p_run_id;
  END IF;

  -- Fill in partner stats from their latest snapshot (if not already set)
  IF v_is_inviter THEN
    UPDATE virtual_runs SET
      invitee_distance_m = COALESCE(invitee_distance_m,
        (SELECT distance_m FROM virtual_run_snapshots WHERE virtual_run_id = p_run_id AND user_id = v_run.invitee_id)),
      invitee_duration_s = COALESCE(invitee_duration_s,
        (SELECT duration_s FROM virtual_run_snapshots WHERE virtual_run_id = p_run_id AND user_id = v_run.invitee_id)),
      invitee_avg_pace_sec_per_km = COALESCE(invitee_avg_pace_sec_per_km,
        (SELECT current_pace_sec_per_km FROM virtual_run_snapshots WHERE virtual_run_id = p_run_id AND user_id = v_run.invitee_id)),
      invitee_avg_heart_rate = COALESCE(invitee_avg_heart_rate,
        (SELECT heart_rate FROM virtual_run_snapshots WHERE virtual_run_id = p_run_id AND user_id = v_run.invitee_id))
    WHERE id = p_run_id;
  ELSE
    UPDATE virtual_runs SET
      inviter_distance_m = COALESCE(inviter_distance_m,
        (SELECT distance_m FROM virtual_run_snapshots WHERE virtual_run_id = p_run_id AND user_id = v_run.inviter_id)),
      inviter_duration_s = COALESCE(inviter_duration_s,
        (SELECT duration_s FROM virtual_run_snapshots WHERE virtual_run_id = p_run_id AND user_id = v_run.inviter_id)),
      inviter_avg_pace_sec_per_km = COALESCE(inviter_avg_pace_sec_per_km,
        (SELECT current_pace_sec_per_km FROM virtual_run_snapshots WHERE virtual_run_id = p_run_id AND user_id = v_run.inviter_id)),
      inviter_avg_heart_rate = COALESCE(inviter_avg_heart_rate,
        (SELECT heart_rate FROM virtual_run_snapshots WHERE virtual_run_id = p_run_id AND user_id = v_run.inviter_id))
    WHERE id = p_run_id;
  END IF;

  -- Re-read updated row for winner calculation
  SELECT * INTO v_run FROM virtual_runs WHERE id = p_run_id;

  -- Determine winner by distance (higher distance wins)
  v_inviter_dist := COALESCE(v_run.inviter_distance_m, 0);
  v_invitee_dist := COALESCE(v_run.invitee_distance_m, 0);

  IF v_inviter_dist > v_invitee_dist THEN
    v_winner := v_run.inviter_id;
  ELSIF v_invitee_dist > v_inviter_dist THEN
    v_winner := v_run.invitee_id;
  ELSE
    v_winner := NULL; -- tie
  END IF;

  -- Finalize the run
  UPDATE virtual_runs SET
    status = 'completed',
    ended_at = NOW(),
    winner_id = v_winner
  WHERE id = p_run_id;

  -- Return the completed run as JSON
  RETURN (SELECT row_to_json(r) FROM (
    SELECT * FROM virtual_runs WHERE id = p_run_id
  ) r);
END;
$$;

-- =============================================================
-- 1d. Drop lat/lon columns from snapshots (strip location)
-- =============================================================
ALTER TABLE virtual_run_snapshots DROP COLUMN IF EXISTS latitude;
ALTER TABLE virtual_run_snapshots DROP COLUMN IF EXISTS longitude;

-- =============================================================
-- 1e. Explicit DELETE deny on snapshots
-- =============================================================
CREATE POLICY "No deleting snapshots"
  ON virtual_run_snapshots FOR DELETE
  USING (false);
