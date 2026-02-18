-- Migration: Fix Real-time Replica Identity
-- Description: Configure tables for proper real-time event broadcasting
-- Date: 2025-12-19

-- ============================================================================
-- PART 1: Set REPLICA IDENTITY to FULL
-- ============================================================================

-- For real-time to broadcast all column values (needed for filters to work),
-- tables must have REPLICA IDENTITY set to FULL

ALTER TABLE notifications REPLICA IDENTITY FULL;
ALTER TABLE friendships REPLICA IDENTITY FULL;

-- ============================================================================
-- PART 2: Verify Real-time Publication Configuration
-- ============================================================================

-- Check if tables are in the publication
SELECT tablename
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime';

-- ============================================================================
-- PART 3: Force WAL Level Check
-- ============================================================================

-- Verify Write-Ahead Logging is set to 'logical' (required for real-time)
-- This is typically already configured by Supabase, but let's verify
SHOW wal_level;

-- ============================================================================
-- PART 4: Test Real-time Events (Optional Debug)
-- ============================================================================

-- After running this migration, test by inserting a notification
-- Uncomment and replace USER_ID with your actual user ID to test:

/*
INSERT INTO notifications (user_id, type, actor_id, target_id, read)
VALUES (
    'YOUR_USER_ID_LOWERCASE',  -- Replace with actual user ID
    'friend_request',
    'SOME_OTHER_USER_ID',
    null,
    false
);

-- You should see this appear in your app within 1-2 seconds via real-time
-- If you don't, check:
-- 1. App logs for "📨 Received realtime event"
-- 2. Supabase Dashboard → Database → Replication for any errors
*/

-- ============================================================================
-- Success Message
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE 'Migration completed successfully!';
  RAISE NOTICE 'REPLICA IDENTITY set to FULL for notifications and friendships';
  RAISE NOTICE 'Real-time events should now broadcast correctly';
END $$;
