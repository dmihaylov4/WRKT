-- ============================================================================
-- FULL DIAGNOSTIC TEST - Find out exactly what's happening
-- ============================================================================

-- Step 1: Clean up any existing test data
DELETE FROM notifications WHERE actor_id = '912b6179-70db-418e-858d-3a259889de07' AND user_id = '070b2df2-d640-47f5-bbd0-f6ba655681a5';
DELETE FROM friendships WHERE user_id = '912b6179-70db-418e-858d-3a259889de07' AND friend_id = '070b2df2-d640-47f5-bbd0-f6ba655681a5';

-- Step 2: Verify trigger function exists and is SECURITY DEFINER
SELECT
    p.proname as function_name,
    CASE p.prosecdef
        WHEN true THEN 'SECURITY DEFINER ✅'
        WHEN false THEN 'NOT SECURITY DEFINER ❌'
    END as security_mode
FROM pg_proc p
WHERE p.proname = 'create_friend_request_notification';

-- Step 3: Verify trigger exists
SELECT
    tgname as trigger_name,
    tgenabled as enabled,
    CASE tgenabled
        WHEN 'O' THEN 'ENABLED ✅'
        WHEN 'D' THEN 'DISABLED ❌'
        ELSE tgenabled::text
    END as status
FROM pg_trigger
WHERE tgname = 'friend_request_notification_trigger';

-- Step 4: Insert a friendship (should trigger notification)
INSERT INTO friendships (user_id, friend_id, status)
VALUES (
    '912b6179-70db-418e-858d-3a259889de07',  -- Sender
    '070b2df2-d640-47f5-bbd0-f6ba655681a5',  -- Receiver
    'pending'
)
RETURNING *;

-- Step 5: Wait a moment for trigger to complete
SELECT pg_sleep(0.5);

-- Step 6: Check if notification was created
SELECT
    'NOTIFICATION CREATED ✅' as result,
    id,
    user_id,
    type,
    actor_id,
    created_at
FROM notifications
WHERE user_id = '070b2df2-d640-47f5-bbd0-f6ba655681a5'
AND actor_id = '912b6179-70db-418e-858d-3a259889de07'
AND type = 'friend_request'
ORDER BY created_at DESC
LIMIT 1;

-- If no rows returned above, notification was NOT created (trigger failed)

-- Step 7: Check realtime publication
SELECT
    'REALTIME PUBLICATION STATUS' as check_name,
    CASE
        WHEN EXISTS (
            SELECT 1 FROM pg_publication_tables
            WHERE pubname = 'supabase_realtime'
            AND tablename = 'notifications'
        ) THEN 'notifications in publication ✅'
        ELSE 'notifications NOT in publication ❌'
    END as status;

-- Step 8: Check if realtime is broadcasting INSERT events
SELECT
    'REALTIME BROADCAST SETTINGS' as check_name,
    pubinsert as "INSERT events enabled",
    pubupdate as "UPDATE events enabled",
    pubdelete as "DELETE events enabled"
FROM pg_publication
WHERE pubname = 'supabase_realtime';

-- ============================================================================
-- EXPECTED RESULTS
-- ============================================================================
-- You should see:
-- 1. Function: SECURITY DEFINER ✅
-- 2. Trigger: ENABLED ✅
-- 3. Friendship row inserted
-- 4. Notification row with "NOTIFICATION CREATED ✅"
-- 5. "notifications in publication ✅"
-- 6. All broadcast settings: TRUE

-- ============================================================================
-- WHAT TO CHECK IN YOUR APP
-- ============================================================================
-- After running this, check Xcode logs for:
-- 📨 RAW REALTIME INSERT EVENT RECEIVED!
--
-- If you see the notification in database but NOT in app:
--   → Realtime is disabled at Supabase project level
--   → Need to enable in Dashboard
--
-- If you DON'T see the notification in database:
--   → Trigger is not firing
--   → RLS is blocking it
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '=================================================';
    RAISE NOTICE 'DIAGNOSTIC COMPLETE';
    RAISE NOTICE '=================================================';
    RAISE NOTICE 'Check the query results above:';
    RAISE NOTICE '1. Was notification created? Look for "NOTIFICATION CREATED ✅"';
    RAISE NOTICE '2. Is trigger SECURITY DEFINER? Should show "SECURITY DEFINER ✅"';
    RAISE NOTICE '3. Is trigger enabled? Should show "ENABLED ✅"';
    RAISE NOTICE '4. Is realtime configured? All should be TRUE';
    RAISE NOTICE '';
    RAISE NOTICE 'NOW CHECK YOUR XCODE LOGS:';
    RAISE NOTICE 'If notification was created in DB but you dont see it in app:';
    RAISE NOTICE '  → Realtime is disabled in Supabase Dashboard';
    RAISE NOTICE '  → Go to Settings → API → Enable Realtime';
    RAISE NOTICE '';
    RAISE NOTICE 'If notification was NOT created in DB:';
    RAISE NOTICE '  → Trigger is not firing or RLS is blocking';
    RAISE NOTICE '  → Check Postgres logs for errors';
    RAISE NOTICE '=================================================';
END $$;
