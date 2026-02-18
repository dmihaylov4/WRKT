-- ================================================================
-- FIX COMMENTS COUNT TRIGGER
-- ================================================================
-- Automatically update comments_count when comments are added/deleted
-- This ensures the count on posts stays in sync with actual comments

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS update_comments_count_on_insert ON post_comments;
DROP TRIGGER IF EXISTS update_comments_count_on_delete ON post_comments;
DROP FUNCTION IF EXISTS increment_comments_count();
DROP FUNCTION IF EXISTS decrement_comments_count();

-- Function to increment comments count when comment is added
CREATE OR REPLACE FUNCTION increment_comments_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE workout_posts
    SET comments_count = comments_count + 1
    WHERE id = NEW.post_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to decrement comments count when comment is deleted
CREATE OR REPLACE FUNCTION decrement_comments_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE workout_posts
    SET comments_count = GREATEST(comments_count - 1, 0)
    WHERE id = OLD.post_id;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for insert
CREATE TRIGGER update_comments_count_on_insert
    AFTER INSERT ON post_comments
    FOR EACH ROW
    EXECUTE FUNCTION increment_comments_count();

-- Create trigger for delete
CREATE TRIGGER update_comments_count_on_delete
    AFTER DELETE ON post_comments
    FOR EACH ROW
    EXECUTE FUNCTION decrement_comments_count();

-- Add comments
COMMENT ON FUNCTION increment_comments_count() IS 'Increments comments_count on workout_posts when a comment is added';
COMMENT ON FUNCTION decrement_comments_count() IS 'Decrements comments_count on workout_posts when a comment is deleted';

-- ================================================================
-- FIX EXISTING DATA - Recalculate all comment counts
-- ================================================================

UPDATE workout_posts wp
SET comments_count = (
    SELECT COUNT(*)
    FROM post_comments pc
    WHERE pc.post_id = wp.id
);

-- Verify the fix
DO $$
DECLARE
    mismatch_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO mismatch_count
    FROM workout_posts wp
    WHERE wp.comments_count != (
        SELECT COUNT(*)
        FROM post_comments pc
        WHERE pc.post_id = wp.id
    );

    IF mismatch_count > 0 THEN
        RAISE WARNING 'Found % posts with mismatched comment counts after fix', mismatch_count;
    ELSE
        RAISE NOTICE 'All comment counts are now correct!';
    END IF;
END $$;
