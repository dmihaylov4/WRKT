-- FIX_COMMENTS_COUNT_TRIGGER.sql
-- Adds a trigger to maintain comments_count on the posts table
-- whenever rows are inserted or deleted in post_comments.
--
-- Run this once in the Supabase SQL editor.

-- 1. Create the trigger function
CREATE OR REPLACE FUNCTION update_post_comments_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.workout_posts SET comments_count = comments_count + 1 WHERE id = NEW.post_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.workout_posts SET comments_count = GREATEST(0, comments_count - 1) WHERE id = OLD.post_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 2. Attach the trigger
DROP TRIGGER IF EXISTS trigger_update_post_comments_count ON post_comments;
CREATE TRIGGER trigger_update_post_comments_count
AFTER INSERT OR DELETE ON post_comments
FOR EACH ROW
EXECUTE FUNCTION update_post_comments_count();

-- 3. Backfill all existing posts
UPDATE public.workout_posts p
SET comments_count = (
    SELECT COUNT(*) FROM post_comments pc WHERE pc.post_id = p.id
);
