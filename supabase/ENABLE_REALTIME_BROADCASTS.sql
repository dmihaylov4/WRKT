-- ============================================================================
-- Enable Realtime Broadcasts for Notifications Table
-- This ensures events are actually broadcast, not just recorded
-- ============================================================================

-- Check current publication configuration
SELECT
    pubname,
    pubinsert as "Broadcasts INSERT",
    pubupdate as "Broadcasts UPDATE",
    pubdelete as "Broadcasts DELETE",
    pubtruncate as "Broadcasts TRUNCATE"
FROM pg_publication
WHERE pubname = 'supabase_realtime';

-- The above should show TRUE for insert/update/delete
-- If any are FALSE, run this:

-- ALTER PUBLICATION supabase_realtime SET (publish = 'insert, update, delete');

-- ============================================================================
-- Verify table is in publication with all columns
-- ============================================================================
SELECT DISTINCT
    schemaname,
    tablename,
    COUNT(*) as column_count
FROM pg_publication_tables pt
LEFT JOIN pg_attribute a ON a.attrelid = (pt.schemaname || '.' || pt.tablename)::regclass
WHERE pubname = 'supabase_realtime'
AND tablename = 'notifications'
AND attnum > 0
AND NOT attisdropped
GROUP BY schemaname, tablename;

-- Should show 7+ columns (6 data columns + system columns)

-- ============================================================================
-- Check if table has REPLICA IDENTITY FULL (required for filters)
-- ============================================================================
SELECT
    c.relname as table_name,
    CASE c.relreplident
        WHEN 'f' THEN 'FULL ✅'
        WHEN 'd' THEN 'DEFAULT (might not work with filters) ⚠️'
        WHEN 'n' THEN 'NOTHING (will not work) ❌'
        ELSE c.relreplident::text
    END as replica_identity
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relname = 'notifications'
AND n.nspname = 'public';

-- Must be FULL for realtime to work

-- ============================================================================
-- Force a refresh of the publication
-- ============================================================================

-- Sometimes Supabase needs the publication to be refreshed
-- This removes and re-adds the table to force a refresh

DO $$
BEGIN
    -- Remove table from publication
    BEGIN
        ALTER PUBLICATION supabase_realtime DROP TABLE notifications;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    -- Wait a moment
    PERFORM pg_sleep(0.5);

    -- Add it back
    ALTER PUBLICATION supabase_realtime ADD TABLE notifications;

    RAISE NOTICE '✅ Publication refreshed - try your app again';
END $$;

-- ============================================================================
-- Final verification
-- ============================================================================

SELECT
    'notifications' as table_name,
    CASE
        WHEN EXISTS (
            SELECT 1 FROM pg_publication_tables
            WHERE pubname = 'supabase_realtime'
            AND tablename = 'notifications'
        ) THEN '✅ In publication'
        ELSE '❌ NOT in publication'
    END as publication_status,
    CASE
        WHEN EXISTS (
            SELECT 1 FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE c.relname = 'notifications'
            AND n.nspname = 'public'
            AND c.relreplident = 'f'
        ) THEN '✅ REPLICA IDENTITY FULL'
        ELSE '❌ REPLICA IDENTITY not FULL'
    END as replica_status;

-- ============================================================================
-- Test with a notification insert
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '=================================================';
    RAISE NOTICE 'Now insert a test notification:';
    RAISE NOTICE '';
    RAISE NOTICE 'INSERT INTO notifications (user_id, type, actor_id, read)';
    RAISE NOTICE 'VALUES (''070b2df2-d640-47f5-bbd0-f6ba655681a5'', ''friend_request'', ''912b6179-70db-418e-858d-3a259889de07'', false);';
    RAISE NOTICE '';
    RAISE NOTICE 'Check your Xcode logs for:';
    RAISE NOTICE '📨 RAW REALTIME EVENT RECEIVED (NO FILTER TEST)';
    RAISE NOTICE '';
    RAISE NOTICE 'If you see it → Realtime is working!';
    RAISE NOTICE 'If you dont see it → Check Supabase Dashboard';
    RAISE NOTICE '=================================================';
END $$;
