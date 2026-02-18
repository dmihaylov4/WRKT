-- ============================================================================
-- QUICK REALTIME DIAGNOSTIC (Returns Results as Tables)
-- Run this entire file in Supabase SQL Editor
-- ============================================================================

-- CHECK 1: Is notifications table in the realtime publication?
SELECT
    '1. Publication Check' as test,
    CASE
        WHEN EXISTS (
            SELECT 1 FROM pg_publication_tables
            WHERE pubname = 'supabase_realtime'
            AND tablename = 'notifications'
        ) THEN '✅ notifications in publication'
        ELSE '❌ CRITICAL: notifications NOT in publication'
    END as notifications_status,
    CASE
        WHEN EXISTS (
            SELECT 1 FROM pg_publication_tables
            WHERE pubname = 'supabase_realtime'
            AND tablename = 'friendships'
        ) THEN '✅ friendships in publication'
        ELSE '❌ CRITICAL: friendships NOT in publication'
    END as friendships_status;

-- CHECK 2: REPLICA IDENTITY status
SELECT
    '2. Replica Identity' as test,
    c.relname as table_name,
    CASE c.relreplident
        WHEN 'f' THEN '✅ FULL (correct)'
        WHEN 'd' THEN '❌ DEFAULT (needs FULL)'
        WHEN 'n' THEN '❌ NOTHING (needs FULL)'
        ELSE '⚠️ ' || c.relreplident::text
    END as status
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relname IN ('notifications', 'friendships')
AND n.nspname = 'public'
ORDER BY c.relname;

-- CHECK 3: Database triggers exist?
SELECT
    '3. Triggers' as test,
    trigger_name,
    event_object_table as "table",
    CASE
        WHEN trigger_name = 'on_friend_request_created' THEN '✅ Friend request trigger'
        WHEN trigger_name = 'on_friend_request_accepted' THEN '✅ Friend accepted trigger'
        ELSE '✅ Other trigger'
    END as status
FROM information_schema.triggers
WHERE event_object_schema = 'public'
AND trigger_name IN ('on_friend_request_created', 'on_friend_request_accepted')
ORDER BY trigger_name;

-- CHECK 4: RLS Policies for notifications
SELECT
    '4. RLS Policies' as test,
    policyname,
    cmd as operation,
    CASE
        WHEN cmd = 'INSERT' AND policyname LIKE '%System%' THEN '✅ System can insert'
        WHEN cmd = 'SELECT' THEN '✅ Users can view'
        WHEN cmd = 'UPDATE' THEN '✅ Users can update'
        WHEN cmd = 'DELETE' THEN '✅ Users can delete'
        ELSE '⚠️ ' || policyname
    END as status
FROM pg_policies
WHERE tablename = 'notifications'
ORDER BY cmd;

-- CHECK 5: Recent notifications exist?
SELECT
    '5. Recent Notifications' as test,
    type,
    COUNT(*) as count,
    MAX(created_at) as most_recent
FROM notifications
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY type
ORDER BY count DESC;

-- FINAL SUMMARY
SELECT
    'SUMMARY' as "═══ FINAL RESULT ═══",
    CASE
        WHEN (
            EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'notifications')
            AND EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'friendships')
            AND EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relname = 'notifications' AND n.nspname = 'public' AND c.relreplident = 'f')
            AND EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relname = 'friendships' AND n.nspname = 'public' AND c.relreplident = 'f')
            AND EXISTS (SELECT 1 FROM information_schema.triggers WHERE trigger_name = 'on_friend_request_created')
        )
        THEN '✅ DATABASE CONFIG CORRECT - Check Supabase Dashboard Replication next'
        ELSE '❌ DATABASE CONFIG HAS ISSUES - See results above'
    END as status;
