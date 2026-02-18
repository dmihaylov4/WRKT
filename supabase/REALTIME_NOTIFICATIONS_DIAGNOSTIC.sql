-- ============================================================================
-- Real-time Notifications Diagnostic
-- Run this in Supabase SQL Editor to diagnose notification issues
-- ============================================================================

-- ============================================================================
-- CHECK 1: Verify REPLICA IDENTITY is set to FULL
-- ============================================================================
-- CRITICAL: Without REPLICA IDENTITY FULL, filters won't work!
SELECT
    n.nspname as schema_name,
    c.relname as table_name,
    CASE c.relreplident
        WHEN 'd' THEN 'default (primary key) ⚠️'
        WHEN 'n' THEN 'nothing ❌'
        WHEN 'f' THEN 'FULL ✅'
        WHEN 'i' THEN 'index ⚠️'
    END as replica_identity
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relname IN ('notifications', 'friendships')
AND n.nspname = 'public';

-- Expected: Both tables should show "FULL ✅"
-- If not FULL, real-time filters WILL NOT WORK

-- ============================================================================
-- CHECK 2: Verify tables are in supabase_realtime publication
-- ============================================================================
SELECT
    schemaname,
    tablename,
    '✅ In realtime publication' as status
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
AND tablename IN ('notifications', 'friendships', 'posts', 'post_likes', 'post_comments');

-- Expected: Should see notifications and friendships listed
-- If missing, real-time events WILL NOT BE BROADCAST

-- ============================================================================
-- CHECK 3: Verify WAL level is set to logical
-- ============================================================================
SHOW wal_level;
-- Expected: 'logical' (Supabase sets this automatically)

-- ============================================================================
-- CHECK 4: Check notification table structure
-- ============================================================================
SELECT
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_name = 'notifications'
AND table_schema = 'public'
ORDER BY ordinal_position;

-- ============================================================================
-- CHECK 5: Verify RLS policies on notifications
-- ============================================================================
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'notifications';

-- Expected policies:
-- - SELECT: Users can view their own (qual: auth.uid() = user_id)
-- - INSERT: Authenticated users can insert
-- - UPDATE: Users can update their own
-- - DELETE: Users can delete their own

-- ============================================================================
-- CHECK 6: Test notification insert with your actual user ID
-- ============================================================================
-- Replace these UUIDs with your actual user IDs:
DO $$
DECLARE
    test_user_id UUID := '070b2df2-d640-47f5-bbd0-f6ba655681a5'; -- REPLACE WITH YOUR USER ID
    test_actor_id UUID := '912b6179-70db-418e-858d-3a259889de07'; -- REPLACE WITH ANOTHER USER ID
    inserted_notification_id UUID;
BEGIN
    -- Insert test notification
    INSERT INTO notifications (user_id, type, actor_id, read)
    VALUES (test_user_id, 'friend_request', test_actor_id, false)
    RETURNING id INTO inserted_notification_id;

    RAISE NOTICE 'Test notification inserted with ID: %', inserted_notification_id;
    RAISE NOTICE 'Check your app logs for:';
    RAISE NOTICE '  - "📨 RAW REALTIME EVENT RECEIVED:"';
    RAISE NOTICE '  - "✉️ Decoded notification from realtime:"';
    RAISE NOTICE 'If you dont see these logs, realtime is NOT working';
END $$;

-- ============================================================================
-- CHECK 7: Verify user_id format (lowercase vs uppercase)
-- ============================================================================
-- Check if your notifications have lowercase or uppercase UUIDs
SELECT
    id,
    user_id,
    CASE
        WHEN user_id::text = LOWER(user_id::text) THEN 'lowercase ✅'
        WHEN user_id::text = UPPER(user_id::text) THEN 'UPPERCASE ⚠️'
        ELSE 'mixed case ⚠️'
    END as uuid_format,
    type,
    created_at
FROM notifications
ORDER BY created_at DESC
LIMIT 10;

-- Note: Your Swift code uses .lowercased() for filters
-- PostgreSQL UUIDs are case-insensitive, but realtime filters are case-sensitive!

-- ============================================================================
-- DIAGNOSTIC SUMMARY
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '=================================================';
    RAISE NOTICE 'DIAGNOSTIC COMPLETE';
    RAISE NOTICE '=================================================';
    RAISE NOTICE 'Review the results above:';
    RAISE NOTICE '1. REPLICA IDENTITY must be FULL';
    RAISE NOTICE '2. Tables must be in supabase_realtime publication';
    RAISE NOTICE '3. RLS policies must allow SELECT for auth.uid()';
    RAISE NOTICE '4. Test notification should trigger app logs';
    RAISE NOTICE '';
    RAISE NOTICE 'If any check fails, run the FIX script next.';
END $$;
