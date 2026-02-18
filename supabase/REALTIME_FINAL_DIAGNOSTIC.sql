-- ============================================================================
-- Final Realtime Diagnostic - Find the exact issue
-- ============================================================================

-- ============================================================================
-- CHECK 1: Verify publication broadcasts INSERT events
-- ============================================================================
SELECT
    pubname,
    pubinsert as "INSERT enabled",
    pubupdate as "UPDATE enabled",
    pubdelete as "DELETE enabled"
FROM pg_publication
WHERE pubname = 'supabase_realtime';

-- Expected: pubinsert should be TRUE
-- If FALSE, INSERT events are NOT being broadcast!

-- ============================================================================
-- CHECK 2: Verify notifications table is in publication
-- ============================================================================
SELECT
    schemaname,
    tablename,
    'In realtime publication ✅' as status
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
AND tablename = 'notifications';

-- Expected: Should show the notifications table
-- If empty, table is not in publication!

-- ============================================================================
-- CHECK 3: Check realtime extension status
-- ============================================================================
SELECT
    extname,
    extversion,
    'Installed ✅' as status
FROM pg_extension
WHERE extname = 'supabase_realtime' OR extname LIKE '%realtime%';

-- This shows if the realtime extension is installed

-- ============================================================================
-- CHECK 4: Check WAL sender processes (shows if replication is active)
-- ============================================================================
SELECT
    pid,
    usename,
    application_name,
    state,
    sync_state
FROM pg_stat_replication;

-- If empty, no replication connections are active
-- Supabase realtime should show at least one connection

-- ============================================================================
-- SUMMARY
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '=================================================';
    RAISE NOTICE 'Run all 4 checks above and look for:';
    RAISE NOTICE '1. pubinsert = TRUE (if FALSE, thats the problem!)';
    RAISE NOTICE '2. notifications table appears in publication';
    RAISE NOTICE '3. Realtime extension installed';
    RAISE NOTICE '4. Active replication connections';
    RAISE NOTICE '=================================================';
END $$;
