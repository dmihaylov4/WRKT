-- Migration: Private Images with Storage-Level RLS
-- This enables users to upload progress photos that only they can see

-- ==================================================
-- STEP 1: Create Storage Buckets
-- ==================================================

-- Create public bucket for images visible to everyone
INSERT INTO storage.buckets (id, name, public)
VALUES ('workout-images-public', 'workout-images-public', true)
ON CONFLICT (id) DO NOTHING;

-- Create private bucket for progress photos (RLS protected)
INSERT INTO storage.buckets (id, name, public)
VALUES ('workout-images-private', 'workout-images-private', false)
ON CONFLICT (id) DO NOTHING;

-- ==================================================
-- STEP 2: Storage RLS Policies - Public Bucket
-- ==================================================

-- Anyone can read public images
CREATE POLICY "Public images are viewable by everyone"
ON storage.objects FOR SELECT
USING (bucket_id = 'workout-images-public');

-- Users can upload to their own folder in public bucket
CREATE POLICY "Users can upload public images to own folder"
ON storage.objects FOR INSERT
WITH CHECK (
    bucket_id = 'workout-images-public'
    AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Users can update their own public images
CREATE POLICY "Users can update own public images"
ON storage.objects FOR UPDATE
USING (
    bucket_id = 'workout-images-public'
    AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
    bucket_id = 'workout-images-public'
    AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Users can delete their own public images
CREATE POLICY "Users can delete own public images"
ON storage.objects FOR DELETE
USING (
    bucket_id = 'workout-images-public'
    AND (storage.foldername(name))[1] = auth.uid()::text
);

-- ==================================================
-- STEP 3: Storage RLS Policies - Private Bucket
-- ==================================================

-- Users can only read their own private images
CREATE POLICY "Users can view own private images"
ON storage.objects FOR SELECT
USING (
    bucket_id = 'workout-images-private'
    AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Users can upload to their own folder in private bucket
CREATE POLICY "Users can upload private images to own folder"
ON storage.objects FOR INSERT
WITH CHECK (
    bucket_id = 'workout-images-private'
    AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Users can update their own private images
CREATE POLICY "Users can update own private images"
ON storage.objects FOR UPDATE
USING (
    bucket_id = 'workout-images-private'
    AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
    bucket_id = 'workout-images-private'
    AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Users can delete their own private images
CREATE POLICY "Users can delete own private images"
ON storage.objects FOR DELETE
USING (
    bucket_id = 'workout-images-private'
    AND (storage.foldername(name))[1] = auth.uid()::text
);

-- ==================================================
-- STEP 4: Table for Tracking Image Metadata (Optional)
-- ==================================================
-- Note: We'll store image info directly in workout_posts as JSON
-- This keeps the data model simple and avoids extra joins

-- ==================================================
-- NOTES:
-- ==================================================
-- 1. Public images: Anyone can view, stored in 'workout-images-public'
-- 2. Private images: Only owner can view, stored in 'workout-images-private'
-- 3. Both buckets enforce folder structure: {userId}/{imageId}.jpg
-- 4. Private images require signed URLs (expires in 1 hour)
-- 5. Existing images will need migration (handled separately)
