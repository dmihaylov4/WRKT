-- ================================================================
-- FIX ACTIVE_BATTLES VIEW SECURITY
-- ================================================================
-- Problem: The active_battles view doesn't respect RLS policies
-- Solution: Drop the view and let app-side queries handle filtering

-- Drop the insecure view
DROP VIEW IF EXISTS active_battles;

-- Instead of a view, we'll use a SECURITY INVOKER function
-- This runs with the permissions of the CALLING user, not the creator
-- This ensures RLS policies are properly enforced

CREATE OR REPLACE FUNCTION get_active_battles()
RETURNS TABLE (
    id UUID,
    challenger_id UUID,
    opponent_id UUID,
    battle_type TEXT,
    target_metric TEXT,
    start_date TIMESTAMP,
    end_date TIMESTAMP,
    status TEXT,
    challenger_score NUMERIC,
    opponent_score NUMERIC,
    winner_id UUID,
    custom_rules TEXT,
    trash_talk_enabled BOOLEAN,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    challenger_username TEXT,
    opponent_username TEXT,
    hours_remaining NUMERIC
)
LANGUAGE sql
SECURITY INVOKER  -- Runs with caller's permissions (respects RLS)
STABLE
AS $$
    SELECT
        b.id,
        b.challenger_id,
        b.opponent_id,
        b.battle_type,
        b.target_metric,
        b.start_date,
        b.end_date,
        b.status,
        b.challenger_score,
        b.opponent_score,
        b.winner_id,
        b.custom_rules,
        b.trash_talk_enabled,
        b.created_at,
        b.updated_at,
        c.username as challenger_username,
        o.username as opponent_username,
        EXTRACT(EPOCH FROM (b.end_date - CURRENT_TIMESTAMP)) / 3600 as hours_remaining
    FROM battles b
    JOIN profiles c ON b.challenger_id = c.id
    JOIN profiles o ON b.opponent_id = o.id
    WHERE b.status = 'active'
    AND b.end_date > CURRENT_TIMESTAMP
    ORDER BY b.end_date ASC;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_active_battles() TO authenticated;

-- Add comment
COMMENT ON FUNCTION get_active_battles() IS
'Returns active battles with participant usernames. Respects RLS policies by using SECURITY INVOKER.';

-- ================================================================
-- USAGE
-- ================================================================
-- Instead of: SELECT * FROM active_battles
-- Use: SELECT * FROM get_active_battles()
