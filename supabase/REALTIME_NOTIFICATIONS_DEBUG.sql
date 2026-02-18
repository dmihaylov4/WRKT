-- ============================================================================
-- COMPREHENSIVE REALTIME NOTIFICATIONS DIAGNOSTIC
-- Run this in Supabase SQL Editor to diagnose all potential issues
-- ============================================================================

-- ============================================================================
-- TEST 1: Check if Realtime is enabled in Supabase
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== TEST 1: REALTIME DATABASE EXTENSION ===';
END $$;

-- Check if realtime extension exists
SELECT
    CASE
        WHEN COUNT(*) > 0 THEN '✅ Realtime extension is installed'
        ELSE '❌ Realtime extension NOT installed'
    END as status
FROM pg_extension
WHERE extname = 'pg_stat_statements' OR extname LIKE '%realtime%';

-- ============================================================================
-- TEST 2: Check publication configuration
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== TEST 2: PUBLICATION CONFIGURATION ===';
END $$;

-- Check if supabase_realtime publication exists
SELECT
    pubname,
    pubinsert as "INSERT enabled",
    pubupdate as "UPDATE enabled",
    pubdelete as "DELETE enabled"
FROM pg_publication
WHERE pubname = 'supabase_realtime';

-- Expected: All should be TRUE
-- If publication doesn't exist, realtime won't work AT ALL

-- ============================================================================
-- TEST 3: Check if tables are in publication
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== TEST 3: TABLES IN PUBLICATION ===';
END $$;

SELECT
    tablename,
    CASE
        WHEN tablename IN ('notifications', 'friendships') THEN '✅ Required table'
        ELSE 'ℹ️  Optional table'
    END as importance
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
ORDER BY tablename;

-- Expected: notifications and friendships should both be listed
-- If they're missing, run:
-- ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
-- ALTER PUBLICATION supabase_realtime ADD TABLE friendships;

-- ============================================================================
-- TEST 4: Check REPLICA IDENTITY (CRITICAL for filters)
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== TEST 4: REPLICA IDENTITY ===';
END $$;

SELECT
    c.relname as table_name,
    CASE c.relreplident
        WHEN 'f' THEN '✅ FULL (correct)'
        WHEN 'd' THEN '⚠️  DEFAULT (filters may not work)'
        WHEN 'n' THEN '❌ NOTHING (realtime will fail)'
        WHEN 'i' THEN 'ℹ️  INDEX'
        ELSE c.relreplident::text
    END as replica_identity,
    CASE c.relreplident
        WHEN 'f' THEN 'All good!'
        ELSE 'Run: ALTER TABLE ' || c.relname || ' REPLICA IDENTITY FULL;'
    END as fix
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relname IN ('notifications', 'friendships')
AND n.nspname = 'public'
ORDER BY c.relname;

-- Expected: Both should show FULL
-- If not, REPLICA IDENTITY must be FULL for realtime to broadcast events properly

-- ============================================================================
-- TEST 5: Check RLS policies
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== TEST 5: ROW LEVEL SECURITY POLICIES ===';
END $$;

SELECT
    schemaname,
    tablename,
    policyname,
    cmd as operation,
    CASE
        WHEN roles = '{public}' THEN 'Public'
        ELSE array_to_string(roles, ', ')
    END as applies_to
FROM pg_policies
WHERE tablename IN ('notifications', 'friendships')
ORDER BY tablename, cmd;

-- Look for:
-- - notifications should have INSERT policy that allows system inserts (WITH CHECK true)
-- - If INSERT policy is too restrictive, triggers may fail

-- ============================================================================
-- TEST 6: Check triggers exist and are enabled
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== TEST 6: DATABASE TRIGGERS ===';
END $$;

SELECT
    trigger_name,
    event_object_table as "table",
    action_timing as "timing",
    event_manipulation as "event",
    action_statement as "function",
    CASE
        WHEN trigger_name LIKE '%friend%' THEN '✅ Friend notification trigger'
        ELSE 'ℹ️  Other trigger'
    END as purpose
FROM information_schema.triggers
WHERE event_object_schema = 'public'
AND event_object_table IN ('friendships', 'post_likes', 'post_comments')
ORDER BY event_object_table, trigger_name;

-- Expected:
-- - on_friend_request_created (friendships, AFTER INSERT)
-- - on_friend_request_accepted (friendships, AFTER UPDATE)

-- ============================================================================
-- TEST 7: Test trigger functions manually
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== TEST 7: TRIGGER FUNCTION EXISTENCE ===';
END $$;

SELECT
    routine_name as function_name,
    CASE
        WHEN routine_name LIKE '%friend%' THEN '✅ Friend notification function'
        ELSE 'ℹ️  Other function'
    END as purpose
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name LIKE '%notification%'
ORDER BY routine_name;

-- Expected:
-- - create_friend_request_notification
-- - create_friend_accepted_notification

-- ============================================================================
-- TEST 8: Check for existing notifications
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== TEST 8: SAMPLE NOTIFICATIONS ===';
END $$;

SELECT
    type,
    COUNT(*) as count,
    MAX(created_at) as most_recent
FROM notifications
GROUP BY type
ORDER BY count DESC;

-- This shows if notifications are being created at all

-- ============================================================================
-- TEST 9: Check WAL level (needed for logical replication)
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== TEST 9: WRITE-AHEAD LOGGING LEVEL ===';
END $$;

SHOW wal_level;

-- Expected: 'logical'
-- If not logical, realtime cannot work (this is typically set by Supabase)

-- ============================================================================
-- FINAL SUMMARY
-- ============================================================================
DO $$
DECLARE
    pub_exists BOOLEAN;
    notif_in_pub BOOLEAN;
    friend_in_pub BOOLEAN;
    notif_replica_full BOOLEAN;
    friend_replica_full BOOLEAN;
    trigger_exists BOOLEAN;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== DIAGNOSTIC SUMMARY ===';

    -- Check publication exists
    SELECT EXISTS (
        SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
    ) INTO pub_exists;

    -- Check tables in publication
    SELECT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'notifications'
    ) INTO notif_in_pub;

    SELECT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'friendships'
    ) INTO friend_in_pub;

    -- Check replica identity
    SELECT EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = 'notifications' AND n.nspname = 'public' AND c.relreplident = 'f'
    ) INTO notif_replica_full;

    SELECT EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = 'friendships' AND n.nspname = 'public' AND c.relreplident = 'f'
    ) INTO friend_replica_full;

    -- Check trigger exists
    SELECT EXISTS (
        SELECT 1 FROM information_schema.triggers
        WHERE trigger_name = 'on_friend_request_created'
    ) INTO trigger_exists;

    RAISE NOTICE '';
    RAISE NOTICE 'Publication exists: %', CASE WHEN pub_exists THEN '✅' ELSE '❌ CRITICAL' END;
    RAISE NOTICE 'Notifications in publication: %', CASE WHEN notif_in_pub THEN '✅' ELSE '❌ CRITICAL' END;
    RAISE NOTICE 'Friendships in publication: %', CASE WHEN friend_in_pub THEN '✅' ELSE '❌ CRITICAL' END;
    RAISE NOTICE 'Notifications REPLICA IDENTITY FULL: %', CASE WHEN notif_replica_full THEN '✅' ELSE '❌ CRITICAL' END;
    RAISE NOTICE 'Friendships REPLICA IDENTITY FULL: %', CASE WHEN friend_replica_full THEN '✅' ELSE '❌ CRITICAL' END;
    RAISE NOTICE 'Friend request trigger exists: %', CASE WHEN trigger_exists THEN '✅' ELSE '❌ CRITICAL' END;
    RAISE NOTICE '';

    IF pub_exists AND notif_in_pub AND friend_in_pub AND notif_replica_full AND friend_replica_full AND trigger_exists THEN
        RAISE NOTICE '🎉 ALL CHECKS PASSED - Database configuration is correct!';
        RAISE NOTICE '';
        RAISE NOTICE 'If realtime still does not work, the issue is likely:';
        RAISE NOTICE '1. Supabase Dashboard: Database > Replication > Realtime not enabled';
        RAISE NOTICE '2. WebSocket connection not establishing in your app';
        RAISE NOTICE '3. App not subscribed to the correct channel';
        RAISE NOTICE '';
        RAISE NOTICE 'Run the TEST NOTIFICATION insert below to verify end-to-end.';
    ELSE
        RAISE NOTICE '⚠️  ISSUES FOUND - See failed checks above';
        RAISE NOTICE 'Fix all CRITICAL issues before testing realtime';
    END IF;
END $$;

-- ============================================================================
-- TEST NOTIFICATION INSERT
-- Copy the UUID of a user from your profiles table, then run this:
-- ============================================================================

-- First, show available users:
SELECT
    id,
    username,
    display_name
FROM profiles
ORDER BY created_at DESC
LIMIT 5;

-- Then uncomment and modify this to test (replace UUIDs with actual user IDs):
/*
DO $$
DECLARE
    test_notification_id UUID;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== INSERTING TEST NOTIFICATION ===';

    -- Insert a test friend request notification
    INSERT INTO notifications (user_id, type, actor_id, read)
    VALUES (
        '00000000-0000-0000-0000-000000000000'::UUID,  -- REPLACE: User who will RECEIVE the notification
        'friend_request',
        '11111111-1111-1111-1111-111111111111'::UUID,  -- REPLACE: User who SENT the friend request
        false
    )
    RETURNING id INTO test_notification_id;

    RAISE NOTICE 'Test notification created with ID: %', test_notification_id;
    RAISE NOTICE '';
    RAISE NOTICE 'Now check your app logs for:';
    RAISE NOTICE '  📨 RAW REALTIME INSERT EVENT RECEIVED!';
    RAISE NOTICE '';
    RAISE NOTICE 'If you see it within 2 seconds → Realtime works! 🎉';
    RAISE NOTICE 'If you do NOT see it → Check Supabase Dashboard > Database > Replication';
END $$;
*/
