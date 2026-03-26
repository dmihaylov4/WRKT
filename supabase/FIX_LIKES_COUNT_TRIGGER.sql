-- FIX_LIKES_COUNT_TRIGGER.sql
-- Adds a trigger to maintain likes_count on the posts table
-- whenever rows are inserted or deleted in post_likes.
--
-- Run this once in the Supabase SQL editor.

-- 1. Create the trigger function
CREATE OR REPLACE FUNCTION update_post_likes_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.workout_posts SET likes_count = likes_count + 1 WHERE id = NEW.post_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.workout_posts SET likes_count = GREATEST(0, likes_count - 1) WHERE id = OLD.post_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 2. Attach the trigger
DROP TRIGGER IF EXISTS trigger_update_post_likes_count ON post_likes;
CREATE TRIGGER trigger_update_post_likes_count
AFTER INSERT OR DELETE ON post_likes
FOR EACH ROW
EXECUTE FUNCTION update_post_likes_count();

-- 3. Fix any existing rows whose counter drifted to 0
UPDATE public.workout_posts p
SET likes_count = (
    SELECT COUNT(*) FROM post_likes pl WHERE pl.post_id = p.id
);
