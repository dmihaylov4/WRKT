-- ============================================================================
-- Real-time Notifications Fix Script (Simplified)
-- Run this in Supabase SQL Editor to fix notification realtime issues
-- ============================================================================

-- ============================================================================
-- FIX 1: Set REPLICA IDENTITY to FULL for notifications table
-- ============================================================================
-- This is CRITICAL for real-time filters to work!

ALTER TABLE notifications REPLICA IDENTITY FULL;
ALTER TABLE friendships REPLICA IDENTITY FULL;

-- Verify it worked
SELECT
    c.relname as table_name,
    CASE c.relreplident
        WHEN 'd' THEN 'default (primary key) ⚠️ NEEDS FIX'
        WHEN 'n' THEN 'nothing ❌ NEEDS FIX'
        WHEN 'f' THEN 'FULL ✅ CORRECT'
        WHEN 'i' THEN 'index ⚠️ NEEDS FIX'
    END as replica_identity_status
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relname IN ('notifications', 'friendships')
AND n.nspname = 'public';

-- ============================================================================
-- FIX 2: Add tables to supabase_realtime publication
-- ============================================================================

-- Remove from publication first (ignore errors if not present)
DO $$
BEGIN
    BEGIN
        ALTER PUBLICATION supabase_realtime DROP TABLE notifications;
    EXCEPTION WHEN undefined_object THEN NULL;
    END;

    BEGIN
        ALTER PUBLICATION supabase_realtime DROP TABLE friendships;
    EXCEPTION WHEN undefined_object THEN NULL;
    END;
END $$;

-- Add to publication
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE friendships;

-- Verify it worked
SELECT
    schemaname,
    tablename,
    '✅ Enabled for realtime' as status
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
AND tablename IN ('notifications', 'friendships')
ORDER BY tablename;

-- ============================================================================
-- FIX 3: Verify and recreate RLS policies for notifications
-- ============================================================================

-- Drop existing policies (if they exist)
DROP POLICY IF EXISTS "Users can view their own notifications" ON notifications;
DROP POLICY IF EXISTS "Users can update their own notifications" ON notifications;
DROP POLICY IF EXISTS "Users can delete their own notifications" ON notifications;
DROP POLICY IF EXISTS "Allow authenticated inserts" ON notifications;
DROP POLICY IF EXISTS "Service role can insert notifications" ON notifications;

-- Recreate policies
CREATE POLICY "Users can view their own notifications"
ON notifications FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own notifications"
ON notifications FOR UPDATE
USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own notifications"
ON notifications FOR DELETE
USING (auth.uid() = user_id);

CREATE POLICY "Allow authenticated inserts"
ON notifications FOR INSERT
TO authenticated
WITH CHECK (true);

CREATE POLICY "Service role can insert notifications"
ON notifications FOR INSERT
TO service_role
WITH CHECK (true);

-- ============================================================================
-- FIX 4: Insert a test notification
-- ============================================================================

DO $$
DECLARE
    test_user_id UUID := '070b2df2-d640-47f5-bbd0-f6ba655681a5'; -- Your user ID from the query
    test_actor_id UUID := '912b6179-70db-418e-858d-3a259889de07'; -- Another user ID
    inserted_id UUID;
BEGIN
    -- Delete any old test notifications first
    DELETE FROM notifications
    WHERE user_id = test_user_id
    AND type = 'friend_request'
    AND actor_id = test_actor_id;

    -- Insert new test notification
    INSERT INTO notifications (user_id, type, actor_id, read)
    VALUES (test_user_id, 'friend_request', test_actor_id, false)
    RETURNING id INTO inserted_id;

    RAISE NOTICE '=================================================';
    RAISE NOTICE '✅ TEST NOTIFICATION INSERTED';
    RAISE NOTICE '=================================================';
    RAISE NOTICE 'Notification ID: %', inserted_id;
    RAISE NOTICE 'User ID: %', test_user_id;
    RAISE NOTICE 'Actor ID: %', test_actor_id;
    RAISE NOTICE '';
    RAISE NOTICE '📱 NOW CHECK YOUR APP LOGS';
    RAISE NOTICE 'You should see within 1-2 seconds:';
    RAISE NOTICE '  1. "📨 RAW REALTIME EVENT RECEIVED:"';
    RAISE NOTICE '  2. "✉️ Decoded notification from realtime: type=friend_request"';
    RAISE NOTICE '';
    RAISE NOTICE 'If you DO see these logs → REALTIME IS WORKING! ✅';
    RAISE NOTICE 'If you DO NOT see these logs → Continue troubleshooting below ⬇️';
END $$;

-- ============================================================================
-- FINAL STATUS CHECK
-- ============================================================================

DO $$
DECLARE
    replica_identity_count INT;
    publication_count INT;
    trigger_count INT;
BEGIN
    -- Check replica identity
    SELECT COUNT(*) INTO replica_identity_count
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = 'notifications'
    AND n.nspname = 'public'
    AND c.relreplident = 'f'; -- FULL

    -- Check publication
    SELECT COUNT(*) INTO publication_count
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
    AND tablename = 'notifications';

    -- Check triggers
    SELECT COUNT(*) INTO trigger_count
    FROM information_schema.triggers
    WHERE event_object_table = 'friendships'
    AND trigger_name LIKE '%notification%';

    RAISE NOTICE '=================================================';
    RAISE NOTICE 'CONFIGURATION STATUS';
    RAISE NOTICE '=================================================';

    IF replica_identity_count > 0 THEN
        RAISE NOTICE '✅ REPLICA IDENTITY: FULL (correct)';
    ELSE
        RAISE NOTICE '❌ REPLICA IDENTITY: Not FULL (CRITICAL ISSUE!)';
    END IF;

    IF publication_count > 0 THEN
        RAISE NOTICE '✅ PUBLICATION: notifications in supabase_realtime';
    ELSE
        RAISE NOTICE '❌ PUBLICATION: notifications NOT in publication (CRITICAL ISSUE!)';
    END IF;

    IF trigger_count > 0 THEN
        RAISE NOTICE '✅ TRIGGERS: Friend request trigger exists';
    ELSE
        RAISE NOTICE '⚠️  TRIGGERS: No friend request trigger found';
    END IF;

    RAISE NOTICE '';
    RAISE NOTICE '=================================================';
    RAISE NOTICE 'NEXT STEPS';
    RAISE NOTICE '=================================================';
    RAISE NOTICE '1. Restart your iOS app completely';
    RAISE NOTICE '2. Make sure you are logged in as: 070b2df2-d640-47f5-bbd0-f6ba655681a5';
    RAISE NOTICE '3. Check app logs for the messages mentioned above';
    RAISE NOTICE '4. If still not working, check Supabase Dashboard:';
    RAISE NOTICE '   → Database → Replication → notifications (should have checkmark)';
    RAISE NOTICE '';

    IF replica_identity_count = 0 OR publication_count = 0 THEN
        RAISE NOTICE '❌ CRITICAL: Fix the issues marked above first!';
    ELSE
        RAISE NOTICE '✅ Database configuration looks correct!';
        RAISE NOTICE 'If realtime still not working, the issue is likely:';
        RAISE NOTICE '  - App not properly subscribed (check app logs for "📡 Subscribing")';
        RAISE NOTICE '  - Different user logged in';
        RAISE NOTICE '  - Supabase realtime not enabled in dashboard';
    END IF;
END $$;
