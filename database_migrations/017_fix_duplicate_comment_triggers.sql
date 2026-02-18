-- ================================================================
-- FIX DUPLICATE COMMENT COUNT TRIGGERS
-- ================================================================
-- The issue: Both old (from 000_social_schema.sql) and new triggers
-- are running, causing comments_count to increment by 2 instead of 1

-- Drop ALL existing triggers and functions (using correct original names)
DROP TRIGGER IF EXISTS increment_comments_count ON post_comments;
DROP TRIGGER IF EXISTS decrement_comments_count ON post_comments;
DROP TRIGGER IF EXISTS update_comments_count_on_insert ON post_comments;
DROP TRIGGER IF EXISTS update_comments_count_on_delete ON post_comments;

DROP FUNCTION IF EXISTS increment_post_comments_count();
DROP FUNCTION IF EXISTS decrement_post_comments_count();
DROP FUNCTION IF EXISTS increment_comments_count();
DROP FUNCTION IF EXISTS decrement_comments_count();

-- Create clean functions with clear names
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

-- Create single set of triggers
CREATE TRIGGER post_comments_count_insert
    AFTER INSERT ON post_comments
    FOR EACH ROW
    EXECUTE FUNCTION update_post_comments_count_on_insert();

CREATE TRIGGER post_comments_count_delete
    AFTER DELETE ON post_comments
    FOR EACH ROW
    EXECUTE FUNCTION update_post_comments_count_on_delete();

-- ================================================================
-- FIX EXISTING DATA - Recalculate all comment counts
-- ================================================================

UPDATE workout_posts wp
SET comments_count = (
    SELECT COUNT(*)
    FROM post_comments pc
    WHERE pc.post_id = wp.id
)
WHERE comments_count != (
    SELECT COUNT(*)
    FROM post_comments pc
    WHERE pc.post_id = wp.id
);

-- Verify the fix
DO $$
DECLARE
    mismatch_count INTEGER;
    total_posts INTEGER;
BEGIN
    SELECT COUNT(*) INTO total_posts FROM workout_posts;

    SELECT COUNT(*) INTO mismatch_count
    FROM workout_posts wp
    WHERE wp.comments_count != (
        SELECT COUNT(*)
        FROM post_comments pc
        WHERE pc.post_id = wp.id
    );

    IF mismatch_count > 0 THEN
        RAISE WARNING 'Found % out of % posts with mismatched comment counts', mismatch_count, total_posts;
    ELSE
        RAISE NOTICE 'All % posts have correct comment counts!', total_posts;
    END IF;
END $$;
