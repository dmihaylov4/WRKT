-- ============================================================================
-- Fix Notification Trigger Functions to Bypass RLS
-- Problem: Triggers fail with "violates row-level security policy"
-- Solution: Make trigger functions SECURITY DEFINER
-- ============================================================================

-- ============================================================================
-- FIX 1: Friend Request Notification Trigger
-- ============================================================================

-- Drop existing function
DROP FUNCTION IF EXISTS create_friend_request_notification() CASCADE;

-- Recreate with SECURITY DEFINER
CREATE OR REPLACE FUNCTION create_friend_request_notification()
RETURNS TRIGGER
SECURITY DEFINER  -- This makes it run with the privileges of the function owner (bypasses RLS)
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    -- Only create notification for pending friend requests
    IF NEW.status = 'pending' THEN
        INSERT INTO notifications (user_id, type, actor_id, target_id, read)
        VALUES (NEW.friend_id, 'friend_request', NEW.user_id, NEW.id, false);
    END IF;
    RETURN NEW;
END;
$$;

-- Recreate the trigger
DROP TRIGGER IF EXISTS friend_request_notification_trigger ON friendships;
CREATE TRIGGER friend_request_notification_trigger
    AFTER INSERT ON friendships
    FOR EACH ROW
    EXECUTE FUNCTION create_friend_request_notification();

-- ============================================================================
-- FIX 2: Friend Accepted Notification Trigger
-- ============================================================================

-- Drop existing function
DROP FUNCTION IF EXISTS create_friend_accepted_notification() CASCADE;

-- Recreate with SECURITY DEFINER
CREATE OR REPLACE FUNCTION create_friend_accepted_notification()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    -- Only create notification when status changes from pending to accepted
    IF OLD.status = 'pending' AND NEW.status = 'accepted' THEN
        -- Notify the original requester (user_id)
        INSERT INTO notifications (user_id, type, actor_id, target_id, read)
        VALUES (NEW.user_id, 'friend_accepted', NEW.friend_id, NEW.id, false);
    END IF;
    RETURN NEW;
END;
$$;

-- Recreate the trigger
DROP TRIGGER IF EXISTS friend_accepted_notification_trigger ON friendships;
CREATE TRIGGER friend_accepted_notification_trigger
    AFTER UPDATE ON friendships
    FOR EACH ROW
    EXECUTE FUNCTION create_friend_accepted_notification();

-- ============================================================================
-- FIX 3: Post Like Notification Trigger
-- ============================================================================

-- Drop existing function (if it exists)
DROP FUNCTION IF EXISTS create_post_like_notification() CASCADE;

-- Recreate with SECURITY DEFINER
CREATE OR REPLACE FUNCTION create_post_like_notification()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    post_author_id UUID;
BEGIN
    -- Get the post author
    SELECT user_id INTO post_author_id
    FROM posts
    WHERE id = NEW.post_id;

    -- Don't notify if user likes their own post
    IF post_author_id != NEW.user_id THEN
        INSERT INTO notifications (user_id, type, actor_id, target_id, read)
        VALUES (post_author_id, 'post_like', NEW.user_id, NEW.post_id, false);
    END IF;

    RETURN NEW;
END;
$$;

-- Recreate the trigger (if posts table exists)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'posts') THEN
        DROP TRIGGER IF EXISTS post_like_notification_trigger ON post_likes;
        CREATE TRIGGER post_like_notification_trigger
            AFTER INSERT ON post_likes
            FOR EACH ROW
            EXECUTE FUNCTION create_post_like_notification();
    END IF;
END $$;

-- ============================================================================
-- FIX 4: Post Comment Notification Trigger
-- ============================================================================

-- Drop existing function (if it exists)
DROP FUNCTION IF EXISTS create_comment_notification() CASCADE;

-- Recreate with SECURITY DEFINER
CREATE OR REPLACE FUNCTION create_comment_notification()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    post_author_id UUID;
BEGIN
    -- Get the post author
    SELECT user_id INTO post_author_id
    FROM posts
    WHERE id = NEW.post_id;

    -- Don't notify if user comments on their own post
    IF post_author_id != NEW.user_id THEN
        INSERT INTO notifications (user_id, type, actor_id, target_id, read)
        VALUES (post_author_id, 'post_comment', NEW.user_id, NEW.post_id, false);
    END IF;

    RETURN NEW;
END;
$$;

-- Recreate the trigger (if posts table exists)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'posts') THEN
        DROP TRIGGER IF EXISTS comment_notification_trigger ON post_comments;
        CREATE TRIGGER comment_notification_trigger
            AFTER INSERT ON post_comments
            FOR EACH ROW
            EXECUTE FUNCTION create_comment_notification();
    END IF;
END $$;

-- ============================================================================
-- VERIFY TRIGGERS ARE SECURITY DEFINER
-- ============================================================================

SELECT
    p.proname as function_name,
    CASE p.prosecdef
        WHEN true THEN '✅ SECURITY DEFINER (bypasses RLS)'
        WHEN false THEN '❌ NOT SECURITY DEFINER (will fail with RLS)'
    END as security_mode
FROM pg_proc p
WHERE p.proname LIKE '%notification%'
AND p.pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
ORDER BY p.proname;

-- All should show "✅ SECURITY DEFINER"

-- ============================================================================
-- TEST THE FIX
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '=================================================';
    RAISE NOTICE 'TRIGGER FUNCTIONS UPDATED';
    RAISE NOTICE '=================================================';
    RAISE NOTICE 'All notification triggers now run with SECURITY DEFINER';
    RAISE NOTICE 'This allows them to bypass RLS and insert notifications';
    RAISE NOTICE '';
    RAISE NOTICE 'TEST IT NOW:';
    RAISE NOTICE '1. Send a friend request from your app';
    RAISE NOTICE '2. Check Xcode logs for:';
    RAISE NOTICE '   📨 RAW REALTIME INSERT EVENT RECEIVED!';
    RAISE NOTICE '3. Check Postgres logs - should NOT see RLS errors';
    RAISE NOTICE '=================================================';
END $$;
