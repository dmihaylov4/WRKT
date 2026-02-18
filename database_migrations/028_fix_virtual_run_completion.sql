-- 028: Fix virtual run two-phase completion
--
-- Problem: The old RPC marked runs as 'completed' when the FIRST user called it.
-- This meant the second user's RPC failed ("Run is not active"), their final stats
-- were never saved, and partner stats came from stale snapshot data.
--
-- Fix: Allow both users to submit stats independently. Only mark 'completed'
-- when BOTH users have submitted their final stats via the RPC.

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
  v_both_submitted BOOLEAN;
BEGIN
  -- Lock the row to prevent race conditions
  SELECT * INTO v_run FROM virtual_runs WHERE id = p_run_id FOR UPDATE;

  IF v_run IS NULL THEN
    RAISE EXCEPTION 'Run not found';
  END IF;

  -- Allow 'active' (normal) or 'completed' (second user submitting after first)
  IF v_run.status NOT IN ('active', 'completed') THEN
    RAISE EXCEPTION 'Run is not active (status: %)', v_run.status;
  END IF;

  -- Determine if caller is inviter or invitee
  v_is_inviter := (p_user_id = v_run.inviter_id);

  -- Save the caller's final stats (always overwrite — these are authoritative from Watch)
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

  -- Re-read the row to check if both sides have submitted
  SELECT * INTO v_run FROM virtual_runs WHERE id = p_run_id;

  -- Both submitted = both have non-null duration (duration is always > 0 from Watch)
  v_both_submitted := (v_run.inviter_duration_s IS NOT NULL AND v_run.invitee_duration_s IS NOT NULL);

  IF v_both_submitted THEN
    -- Determine winner by distance
    v_inviter_dist := COALESCE(v_run.inviter_distance_m, 0);
    v_invitee_dist := COALESCE(v_run.invitee_distance_m, 0);

    IF v_inviter_dist > v_invitee_dist THEN
      v_winner := v_run.inviter_id;
    ELSIF v_invitee_dist > v_inviter_dist THEN
      v_winner := v_run.invitee_id;
    ELSE
      v_winner := NULL; -- tie
    END IF;

    -- Mark completed with accurate stats from both users
    UPDATE virtual_runs SET
      status = 'completed',
      ended_at = COALESCE(ended_at, NOW()),
      winner_id = v_winner
    WHERE id = p_run_id;
  END IF;
  -- If only one user submitted, status stays 'active' — waiting for the other

  -- Return the current run state as JSON
  RETURN (SELECT row_to_json(r) FROM (
    SELECT * FROM virtual_runs WHERE id = p_run_id
  ) r);
END;
$$;
