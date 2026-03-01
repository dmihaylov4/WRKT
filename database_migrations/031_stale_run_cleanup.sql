-- 031: Server-side cleanup for stale virtual runs
--
-- Safety net for runs that get stuck in 'active' status due to:
-- - Both devices dying mid-run
-- - Message delivery failures not caught by guaranteed delivery
-- - Edge cases like iCloud sign-out during an active run
--
-- Requires pg_cron extension to be enabled in Supabase.
-- Run this manually in the SQL editor:

-- Cancel runs that have been 'active' for 6+ hours with no recent snapshot activity
SELECT cron.schedule(
    'cleanup-stale-virtual-runs',
    '0 * * * *',  -- every hour
    $$UPDATE virtual_runs
      SET status = 'cancelled', ended_at = NOW()
      WHERE status = 'active'
        AND started_at < NOW() - INTERVAL '6 hours'
        AND NOT EXISTS (
            SELECT 1 FROM virtual_run_snapshots
            WHERE virtual_run_id = virtual_runs.id
              AND client_recorded_at > NOW() - INTERVAL '1 hour'
        )$$
);
