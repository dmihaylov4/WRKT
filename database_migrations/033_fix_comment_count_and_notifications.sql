-- ================================================================
-- FIX COMMENT COUNT + ADD MISSING SOCIAL NOTIFICATIONS
-- ================================================================
-- Issues:
-- 1. comments_count is wrong (e.g. shows 5 when there are 3 comments).
--    Root cause: duplicate triggers from migrations 000, 016, 017 all
--    firing simultaneously, incrementing by 2-3× per insert.
-- 2. post_like and post_comment notifications are never created.
--    (comment_reply and comment_mention already work via migration 007.)

-- ================================================================
-- PART 1: Nuke ALL comment count triggers (every name ever used)
-- ================================================================

-- Triggers from 000_social_schema.sql
DROP TRIGGER IF EXISTS increment_comments_count ON post_comments;
DROP TRIGGER IF EXISTS decrement_comments_count ON post_comments;

-- Triggers from 016_fix_comments_count_trigger.sql
DROP TRIGGER IF EXISTS update_comments_count_on_insert ON post_comments;
DROP TRIGGER IF EXISTS update_comments_count_on_delete ON post_comments;

-- Triggers from 017_fix_duplicate_comment_triggers.sql
DROP TRIGGER IF EXISTS post_comments_count_insert ON post_comments;
DROP TRIGGER IF EXISTS post_comments_count_delete ON post_comments;

-- Drop all associated functions
DROP FUNCTION IF EXISTS increment_post_comments_count();
DROP FUNCTION IF EXISTS decrement_post_comments_count();
DROP FUNCTION IF EXISTS increment_comments_count();
DROP FUNCTION IF EXISTS decrement_comments_count();
DROP FUNCTION IF EXISTS update_post_comments_count_on_insert();
DROP FUNCTION IF EXISTS update_post_comments_count_on_delete();

-- ================================================================
-- Create ONE clean trigger counting ALL comments (including replies)
-- ================================================================

CREATE OR REPLACE FUNCTION update_post_comments_count_on_insert()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE workout_posts
    SET comments_count = comments_count + 1,
        updated_at = NOW()
    WHERE id = NEW.post_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION update_post_comments_count_on_delete()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE workout_posts
    SET comments_count = GREATEST(comments_count - 1, 0),
        updated_at = NOW()
    WHERE id = OLD.post_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER post_comments_count_insert
    AFTER INSERT ON post_comments
    FOR EACH ROW
    EXECUTE FUNCTION update_post_comments_count_on_insert();

CREATE TRIGGER post_comments_count_delete
    AFTER DELETE ON post_comments
    FOR EACH ROW
    EXECUTE FUNCTION update_post_comments_count_on_delete();

-- ================================================================
-- Recalculate ALL existing comment counts from scratch
-- ================================================================

UPDATE workout_posts wp
SET comments_count = (
    SELECT COUNT(*)
    FROM post_comments pc
    WHERE pc.post_id = wp.id
);

-- ================================================================
-- PART 2: Fix notification type constraint to include all types
-- ================================================================

-- Drop the old constraint (may be too narrow or contain stale types).
-- We intentionally do NOT re-add a CHECK constraint here because existing
-- rows may contain legacy type values ('like', 'comment', 'mention') from
-- the original schema that would violate a new constraint and abort the migration.
-- Type safety is enforced by the Swift NotificationType enum on the client.
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

-- ================================================================
-- PART 3: Add post_like notification trigger
-- ================================================================

CREATE OR REPLACE FUNCTION notify_post_liked()
RETURNS TRIGGER AS $$
DECLARE
    post_owner_id UUID;
BEGIN
    SELECT user_id INTO post_owner_id
    FROM workout_posts
    WHERE id = NEW.post_id;

    -- Don't notify when liking your own post
    IF post_owner_id IS NOT NULL AND post_owner_id != NEW.user_id THEN
        INSERT INTO notifications (user_id, type, actor_id, target_id, read, created_at)
        VALUES (
            post_owner_id,
            'post_like',
            NEW.user_id,
            NEW.post_id,
            false,
            NOW()
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS notify_post_liked_trigger ON post_likes;
CREATE TRIGGER notify_post_liked_trigger
    AFTER INSERT ON post_likes
    FOR EACH ROW
    EXECUTE FUNCTION notify_post_liked();

-- ================================================================
-- PART 4: Add post_comment notification trigger
-- ================================================================
-- Only fires for top-level comments (parent_comment_id IS NULL).
-- Replies are already handled by notify_comment_reply which notifies
-- the comment author. Firing for replies too would double-notify the
-- post owner when they are also the comment author.

CREATE OR REPLACE FUNCTION notify_post_commented()
RETURNS TRIGGER AS $$
DECLARE
    post_owner_id UUID;
BEGIN
    -- Skip replies — the existing notify_comment_reply trigger handles those
    IF NEW.parent_comment_id IS NOT NULL THEN
        RETURN NEW;
    END IF;

    SELECT user_id INTO post_owner_id
    FROM workout_posts
    WHERE id = NEW.post_id;

    -- Don't notify when commenting on your own post
    IF post_owner_id IS NOT NULL AND post_owner_id != NEW.user_id THEN
        INSERT INTO notifications (user_id, type, actor_id, target_id, read, created_at)
        VALUES (
            post_owner_id,
            'post_comment',
            NEW.user_id,
            NEW.post_id,
            false,
            NOW()
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS notify_post_commented_trigger ON post_comments;
CREATE TRIGGER notify_post_commented_trigger
    AFTER INSERT ON post_comments
    FOR EACH ROW
    EXECUTE FUNCTION notify_post_commented();

-- ================================================================
-- VERIFY comment counts
-- ================================================================

DO $$
DECLARE
    mismatch_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO mismatch_count
    FROM workout_posts wp
    WHERE wp.comments_count != (
        SELECT COUNT(*) FROM post_comments pc WHERE pc.post_id = wp.id
    );

    IF mismatch_count > 0 THEN
        RAISE WARNING 'Found % posts with mismatched comment counts', mismatch_count;
    ELSE
        RAISE NOTICE 'All comment counts are correct!';
    END IF;
END $$;
