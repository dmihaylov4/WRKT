-- 030: Add pause state to snapshots + invite expiration to virtual_runs
--
-- C1: The is_paused column allows the CDC fallback path to convey pause state
--     after reconnection. Without it, a paused partner appears disconnected
--     when the client falls back to DB-persisted snapshots.
--
-- C3: The expires_at column enables server-side auto-cancellation of stale
--     pending invites. Without it, unanswered invites accumulate indefinitely
--     and count toward the 5-invite rate limit.

-- C1: Add is_paused to virtual_run_snapshots
ALTER TABLE virtual_run_snapshots
    ADD COLUMN IF NOT EXISTS is_paused BOOLEAN DEFAULT FALSE;

-- C3: Add expires_at to virtual_runs (5-minute default for new invites)
ALTER TABLE virtual_runs
    ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

-- Backfill: set expires_at for any currently pending invites (expire them now)
UPDATE virtual_runs
SET expires_at = created_at + INTERVAL '5 minutes'
WHERE status = 'pending' AND expires_at IS NULL;

-- Auto-set expires_at on new inserts when status is 'pending'
CREATE OR REPLACE FUNCTION set_virtual_run_expiry()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'pending' AND NEW.expires_at IS NULL THEN
        NEW.expires_at := NOW() + INTERVAL '5 minutes';
    END IF;
    -- Clear expires_at when invite is accepted (status changes from pending)
    IF OLD.status = 'pending' AND NEW.status != 'pending' THEN
        NEW.expires_at := NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for INSERT (set expiry on new invites)
DROP TRIGGER IF EXISTS trg_set_virtual_run_expiry_insert ON virtual_runs;
CREATE TRIGGER trg_set_virtual_run_expiry_insert
    BEFORE INSERT ON virtual_runs
    FOR EACH ROW
    EXECUTE FUNCTION set_virtual_run_expiry();

-- Trigger for UPDATE (clear expiry when accepted)
DROP TRIGGER IF EXISTS trg_set_virtual_run_expiry_update ON virtual_runs;
CREATE TRIGGER trg_set_virtual_run_expiry_update
    BEFORE UPDATE ON virtual_runs
    FOR EACH ROW
    EXECUTE FUNCTION set_virtual_run_expiry();

-- Auto-cancel expired pending invites (runs every minute via pg_cron)
-- NOTE: pg_cron must be enabled in your Supabase project (Database > Extensions > pg_cron)
-- Run this manually in the SQL editor after enabling pg_cron:
--
-- SELECT cron.schedule(
--     'cancel-expired-virtual-run-invites',
--     '* * * * *',  -- every minute
--     $$UPDATE virtual_runs SET status = 'cancelled' WHERE status = 'pending' AND expires_at < NOW()$$
-- );
