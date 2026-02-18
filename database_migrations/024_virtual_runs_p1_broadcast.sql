-- P1-A: Broadcast-based live sync for virtual runs
-- No schema changes needed — Supabase Broadcast operates over WebSocket channels
-- without database writes for ephemeral live data.
--
-- The app now uses a hybrid approach:
--   Primary: Broadcast channel for low-latency live snapshot sync (~50ms)
--   Secondary: DB UPSERT every ~30s for crash recovery / reconnection
--
-- This migration relaxes the snapshot rate-limit trigger since DB writes
-- now happen less frequently (every 30s instead of every 2s).

-- Drop the old rate-limit trigger (was enforcing 1s minimum between writes)
DROP TRIGGER IF EXISTS enforce_snapshot_rate_limit ON virtual_run_snapshots;
DROP FUNCTION IF EXISTS check_snapshot_rate_limit();

-- Create a relaxed rate-limit function (allow 1 write per 10 seconds since
-- DB writes now only happen every ~30s; this provides a safety margin)
CREATE OR REPLACE FUNCTION check_snapshot_rate_limit()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        -- Always stamp the current server time on update
        -- (DEFAULT NOW() only applies on INSERT, not UPSERT's UPDATE path)
        NEW.server_received_at := NOW();

        IF (NEW.server_received_at - OLD.server_received_at) < INTERVAL '10 seconds' THEN
            RAISE EXCEPTION 'Snapshot rate limit exceeded (min 10s between DB writes)';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER enforce_snapshot_rate_limit
    BEFORE UPDATE ON virtual_run_snapshots
    FOR EACH ROW
    EXECUTE FUNCTION check_snapshot_rate_limit();
