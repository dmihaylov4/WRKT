-- Migration: Enable Real-time for Notifications Table
-- Description: Adds notifications table to the real-time publication
-- Date: 2025-12-19

-- ============================================================================
-- PART 1: Enable Real-time Replication
-- ============================================================================

-- Remove tables from publication first (in case they're already there)
-- This prevents "relation already exists" errors
DO $$
BEGIN
  -- Try to drop notifications from publication (ignore errors if not present)
  BEGIN
    ALTER PUBLICATION supabase_realtime DROP TABLE notifications;
  EXCEPTION
    WHEN undefined_object THEN NULL;
  END;

  -- Try to drop friendships from publication (ignore errors if not present)
  BEGIN
    ALTER PUBLICATION supabase_realtime DROP TABLE friendships;
  EXCEPTION
    WHEN undefined_object THEN NULL;
  END;
END $$;

-- Add notifications table to the real-time publication
-- This is REQUIRED for real-time subscriptions to work
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;

-- Add friendships table to real-time as well (for friend request updates)
ALTER PUBLICATION supabase_realtime ADD TABLE friendships;

-- ============================================================================
-- PART 2: Verify Configuration
-- ============================================================================

-- Verify notifications table is in the publication
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
    AND tablename = 'notifications'
  ) THEN
    RAISE EXCEPTION 'notifications table is not in supabase_realtime publication';
  END IF;
END $$;

-- ============================================================================
-- PART 3: Test Real-time with a Dummy Notification (Optional)
-- ============================================================================

-- Uncomment and modify this to test real-time delivery
-- Replace 'YOUR_USER_ID' with an actual user ID from your profiles table

/*
-- Test notification insert
INSERT INTO notifications (user_id, type, actor_id, target_id, read)
VALUES
  ('YOUR_USER_ID', 'friend_request', 'YOUR_USER_ID', null, false)
RETURNING *;

-- You should see this notification appear in the app within 1-2 seconds
-- If you don't, check your app logs for subscription errors
*/

-- ============================================================================
-- Success Message
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE 'Migration completed successfully!';
  RAISE NOTICE 'Real-time enabled for notifications and friendships tables';
  RAISE NOTICE 'Test the real-time connection by sending a friend request';
END $$;
