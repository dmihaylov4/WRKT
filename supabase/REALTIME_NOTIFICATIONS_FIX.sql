-- ============================================================================
-- Real-time Notifications Fix Script
-- Run this AFTER the diagnostic script to fix common issues
-- ============================================================================

-- ============================================================================
-- FIX 1: Set REPLICA IDENTITY to FULL
-- ============================================================================
-- This is CRITICAL for real-time filters to work!
-- Without FULL, Supabase can't broadcast all column values needed for filtering

ALTER TABLE notifications REPLICA IDENTITY FULL;
ALTER TABLE friendships REPLICA IDENTITY FULL;
ALTER TABLE posts REPLICA IDENTITY FULL;
ALTER TABLE post_likes REPLICA IDENTITY FULL;
ALTER TABLE post_comments REPLICA IDENTITY FULL;

-- Verify it worked
SELECT
    c.relname as table_name,
    CASE c.relreplident
        WHEN 'd' THEN 'default (primary key)'
        WHEN 'n' THEN 'nothing'
        WHEN 'f' THEN 'FULL ✅'
        WHEN 'i' THEN 'index'
    END as replica_identity
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relname IN ('notifications', 'friendships', 'posts', 'post_likes', 'post_comments')
AND n.nspname = 'public';

-- Success message
DO $$
BEGIN
    RAISE NOTICE '✅ REPLICA IDENTITY set to FULL for all realtime tables';
END $$;

-- ============================================================================
-- FIX 2: Add tables to supabase_realtime publication
-- ============================================================================

-- Remove tables first (if they exist) to avoid "already exists" errors
DO $$
BEGIN
    -- Notifications
    BEGIN
        ALTER PUBLICATION supabase_realtime DROP TABLE notifications;
    EXCEPTION WHEN undefined_object THEN NULL;
    END;

    -- Friendships
    BEGIN
        ALTER PUBLICATION supabase_realtime DROP TABLE friendships;
    EXCEPTION WHEN undefined_object THEN NULL;
    END;

    -- Posts
    BEGIN
        ALTER PUBLICATION supabase_realtime DROP TABLE posts;
    EXCEPTION WHEN undefined_object THEN NULL;
    END;

    -- Post Likes
    BEGIN
        ALTER PUBLICATION supabase_realtime DROP TABLE post_likes;
    EXCEPTION WHEN undefined_object THEN NULL;
    END;

    -- Post Comments
    BEGIN
        ALTER PUBLICATION supabase_realtime DROP TABLE post_comments;
    EXCEPTION WHEN undefined_object THEN NULL;
    END;
END $$;

-- Add tables to publication
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE friendships;
ALTER PUBLICATION supabase_realtime ADD TABLE posts;
ALTER PUBLICATION supabase_realtime ADD TABLE post_likes;
ALTER PUBLICATION supabase_realtime ADD TABLE post_comments;

-- Verify it worked
SELECT
    schemaname,
    tablename,
    '✅' as status
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
AND tablename IN ('notifications', 'friendships', 'posts', 'post_likes', 'post_comments');

-- Success message
DO $$
BEGIN
    RAISE NOTICE '✅ All tables added to supabase_realtime publication';
END $$;

-- ============================================================================
-- FIX 3: Ensure RLS policies are correct
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

-- Service role needs to insert (for triggers)
CREATE POLICY "Service role can insert notifications"
ON notifications FOR INSERT
TO service_role
WITH CHECK (true);

-- Success message
DO $$
BEGIN
    RAISE NOTICE '✅ RLS policies recreated for notifications table';
END $$;

-- ============================================================================
-- FIX 4: Verify notification triggers are working
-- ============================================================================

-- Check if triggers exist
SELECT
    trigger_name,
    event_manipulation,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE event_object_table IN ('friendships', 'post_likes', 'post_comments')
AND trigger_name LIKE '%notification%'
ORDER BY event_object_table, trigger_name;

-- ============================================================================
-- FIX 5: Test real-time with a notification insert
-- ============================================================================

DO $$
DECLARE
    test_user_id UUID := '070b2df2-d640-47f5-bbd0-f6ba655681a5'; -- REPLACE WITH YOUR USER ID
    test_actor_id UUID := '912b6179-70db-418e-858d-3a259889de07'; -- REPLACE WITH ANOTHER USER ID
    inserted_id UUID;
BEGIN
    -- Delete any existing test notifications
    DELETE FROM notifications
    WHERE user_id = test_user_id
    AND type = 'friend_request'
    AND actor_id = test_actor_id;

    -- Wait a moment
    PERFORM pg_sleep(0.5);

    -- Insert new test notification
    INSERT INTO notifications (user_id, type, actor_id, read)
    VALUES (test_user_id, 'friend_request', test_actor_id, false)
    RETURNING id INTO inserted_id;

    RAISE NOTICE '=================================================';
    RAISE NOTICE 'TEST NOTIFICATION INSERTED';
    RAISE NOTICE '=================================================';
    RAISE NOTICE 'Notification ID: %', inserted_id;
    RAISE NOTICE 'User ID: %', test_user_id;
    RAISE NOTICE 'Actor ID: %', test_actor_id;
    RAISE NOTICE '';
    RAISE NOTICE 'NOW CHECK YOUR APP LOGS FOR:';
    RAISE NOTICE '  1. "📨 RAW REALTIME EVENT RECEIVED:"';
    RAISE NOTICE '  2. "✉️ Decoded notification from realtime: type=friend_request"';
    RAISE NOTICE '';
    RAISE NOTICE 'If you see these logs within 1-2 seconds, realtime is working!';
    RAISE NOTICE 'If not, check:';
    RAISE NOTICE '  - App is in foreground and subscribed';
    RAISE NOTICE '  - Correct user is logged in (070b2df2-d640-47f5-bbd0-f6ba655681a5)';
    RAISE NOTICE '  - Supabase Dashboard → Database → Replication for errors';
END $$;

-- ============================================================================
-- COMPLETION MESSAGE
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '=================================================';
    RAISE NOTICE 'REAL-TIME FIX COMPLETE';
    RAISE NOTICE '=================================================';
    RAISE NOTICE 'Changes applied:';
    RAISE NOTICE '  ✅ REPLICA IDENTITY set to FULL';
    RAISE NOTICE '  ✅ Tables added to supabase_realtime publication';
    RAISE NOTICE '  ✅ RLS policies recreated';
    RAISE NOTICE '  ✅ Test notification inserted';
    RAISE NOTICE '';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '  1. Restart your app (to reconnect subscriptions)';
    RAISE NOTICE '  2. Make sure you are logged in as user: 070b2df2-d640-47f5-bbd0-f6ba655681a5';
    RAISE NOTICE '  3. Watch app logs for realtime events';
    RAISE NOTICE '  4. Send a friend request or insert a test notification';
    RAISE NOTICE '';
    RAISE NOTICE 'If still not working:';
    RAISE NOTICE '  - Check Supabase Dashboard → Database → Replication';
    RAISE NOTICE '  - Enable real-time in Supabase Dashboard → Database → Replication → Tables';
    RAISE NOTICE '  - Verify notifications table has real-time enabled with checkmark';
END $$;
