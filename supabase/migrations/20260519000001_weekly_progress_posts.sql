-- Add post_type and weekly_stats to workout_posts.
-- post_type: 'workout' (default) or 'weekly_progress'
-- weekly_stats: JSONB blob written by the iOS client for weekly_progress posts.
-- Both columns are backward-compatible: existing rows get post_type='workout', weekly_stats=NULL.

ALTER TABLE public.workout_posts
    ADD COLUMN IF NOT EXISTS post_type TEXT NOT NULL DEFAULT 'workout',
    ADD COLUMN IF NOT EXISTS weekly_stats JSONB;
