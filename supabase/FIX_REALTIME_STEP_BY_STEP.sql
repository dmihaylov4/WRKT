-- ============================================================================
-- STEP-BY-STEP REALTIME FIX
-- Run each query ONE AT A TIME and check the result
-- ============================================================================

-- ============================================================================
-- STEP 1: Check if notifications is in publication
-- ============================================================================
-- Run this first:

SELECT tablename
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
AND tablename IN ('notifications', 'friendships')
ORDER BY tablename;

-- EXPECTED: You should see TWO rows:
--   friendships
--   notifications
--
-- If you see LESS than 2 rows, continue to STEP 1 FIX below
-- If you see 2 rows, SKIP to STEP 2

-- ============================================================================
-- STEP 1 FIX: Add tables to publication (only if they're missing)
-- ============================================================================
-- Only run this if STEP 1 showed less than 2 rows:

ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE friendships;

-- Then re-run STEP 1 to verify - you should now see 2 rows

-- ============================================================================
-- STEP 2: Check REPLICA IDENTITY
-- ============================================================================
-- Run this:

SELECT
    c.relname as table_name,
    CASE c.relreplident
        WHEN 'f' THEN 'FULL ✅'
        WHEN 'd' THEN 'DEFAULT ❌'
        WHEN 'n' THEN 'NOTHING ❌'
        ELSE c.relreplident::text
    END as replica_identity
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relname IN ('notifications', 'friendships')
AND n.nspname = 'public'
ORDER BY c.relname;

-- EXPECTED: Both rows should show "FULL ✅"
--   friendships    | FULL ✅
--   notifications  | FULL ✅
--
-- If either shows DEFAULT or NOTHING, continue to STEP 2 FIX
-- If both show FULL, SKIP to STEP 3

-- ============================================================================
-- STEP 2 FIX: Set REPLICA IDENTITY to FULL
-- ============================================================================
-- Only run this if STEP 2 showed DEFAULT or NOTHING:

ALTER TABLE notifications REPLICA IDENTITY FULL;
ALTER TABLE friendships REPLICA IDENTITY FULL;

-- IMPORTANT: After changing REPLICA IDENTITY, refresh the publication:
ALTER PUBLICATION supabase_realtime DROP TABLE notifications;
ALTER PUBLICATION supabase_realtime DROP TABLE friendships;

SELECT pg_sleep(1);

ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE friendships;

-- Then re-run STEP 2 to verify - both should now show "FULL ✅"

-- ============================================================================
-- STEP 3: Check triggers exist
-- ============================================================================
-- Run this:

SELECT
    trigger_name,
    event_object_table,
    event_manipulation
FROM information_schema.triggers
WHERE event_object_schema = 'public'
AND event_object_table = 'friendships'
AND trigger_name IN ('on_friend_request_created', 'on_friend_request_accepted')
ORDER BY trigger_name;

-- EXPECTED: You should see TWO rows:
--   on_friend_request_accepted  | friendships | UPDATE
--   on_friend_request_created   | friendships | INSERT
--
-- If you see LESS than 2 rows, continue to STEP 3 FIX
-- If you see 2 rows, SKIP to STEP 4

-- ============================================================================
-- STEP 3 FIX: Create triggers (only if missing)
-- ============================================================================
-- Only run this if STEP 3 showed less than 2 rows:

-- First, create the trigger functions
CREATE OR REPLACE FUNCTION create_friend_request_notification()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'pending' THEN
        INSERT INTO notifications (user_id, type, actor_id, target_id)
        VALUES (NEW.friend_id, 'friend_request', NEW.user_id, NEW.id);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION create_friend_accepted_notification()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status = 'pending' AND NEW.status = 'accepted' THEN
        INSERT INTO notifications (user_id, type, actor_id, target_id)
        VALUES (NEW.user_id, 'friend_accepted', NEW.friend_id, NEW.id);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Then create the triggers
DROP TRIGGER IF EXISTS on_friend_request_created ON friendships;
CREATE TRIGGER on_friend_request_created
    AFTER INSERT ON friendships
    FOR EACH ROW
    EXECUTE FUNCTION create_friend_request_notification();

DROP TRIGGER IF EXISTS on_friend_request_accepted ON friendships;
CREATE TRIGGER on_friend_request_accepted
    AFTER UPDATE ON friendships
    FOR EACH ROW
    EXECUTE FUNCTION create_friend_accepted_notification();

-- Then re-run STEP 3 to verify - you should now see 2 rows

-- ============================================================================
-- STEP 4: Check RLS policies
-- ============================================================================
-- Run this:

SELECT policyname, cmd
FROM pg_policies
WHERE tablename = 'notifications'
AND cmd = 'INSERT'
ORDER BY policyname;

-- EXPECTED: You should see at least ONE row for INSERT policy
-- The policy should allow system inserts (SECURITY DEFINER functions)
--
-- If you see ZERO rows, continue to STEP 4 FIX
-- If you see at least 1 row, you're good!

-- ============================================================================
-- STEP 4 FIX: Create INSERT policy (only if missing)
-- ============================================================================
-- Only run this if STEP 4 showed zero rows:

CREATE POLICY "System can insert notifications"
ON notifications FOR INSERT
WITH CHECK (true);

-- Then re-run STEP 4 to verify

-- ============================================================================
-- STEP 5: FINAL VERIFICATION
-- ============================================================================
-- Run this to verify everything is configured:

SELECT
    CASE
        WHEN (
            -- Check publication
            EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'notifications')
            AND EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'friendships')
            -- Check replica identity
            AND EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relname = 'notifications' AND n.nspname = 'public' AND c.relreplident = 'f')
            AND EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relname = 'friendships' AND n.nspname = 'public' AND c.relreplident = 'f')
            -- Check triggers
            AND EXISTS (SELECT 1 FROM information_schema.triggers WHERE trigger_name = 'on_friend_request_created')
            AND EXISTS (SELECT 1 FROM information_schema.triggers WHERE trigger_name = 'on_friend_request_accepted')
        )
        THEN '✅ ALL DATABASE CHECKS PASSED!'
        ELSE '❌ Still has issues - re-run steps above'
    END as final_status;

-- ============================================================================
-- STEP 6: TEST WITH REAL DATA
-- ============================================================================
-- After STEP 5 shows ✅, test the complete flow:
-- Replace the UUIDs below with your actual user IDs

/*
-- IMPORTANT: Before running this test:
-- 1. Open your app and log in as the RECEIVER user
-- 2. Navigate to the Social tab
-- 3. Keep the app in the foreground
-- 4. Then run this SQL:

INSERT INTO friendships (user_id, friend_id, status)
VALUES (
    '912b6179-70db-418e-858d-3a259889de07',  -- SENDER (dmihaylov13 from your CSV)
    'e7801497-5937-4f27-9a25-e277fdbb366c',  -- RECEIVER (markyza from your CSV)
    'pending'
);

-- Within 1-2 seconds, the RECEIVER's app should:
-- - Show a toast notification
-- - Show logs: "📨 RAW REALTIME INSERT EVENT RECEIVED!"
-- - Badge count increases

-- If this works, your database is fully configured!
-- If not, the issue is in Supabase Dashboard Replication settings
*/
