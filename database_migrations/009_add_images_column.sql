-- Migration: Add images column to workout_posts
-- This adds support for the new PostImage format with privacy settings

-- Add images column (JSONB array of PostImage objects)
-- Nullable to support backward compatibility with existing posts
ALTER TABLE workout_posts
ADD COLUMN IF NOT EXISTS images JSONB;

-- Add comment for documentation
COMMENT ON COLUMN workout_posts.images IS 'Array of PostImage objects with storage paths and privacy settings';

-- Note: image_urls column will remain for backward compatibility
-- New posts will use images, old posts will continue to work with image_urls
