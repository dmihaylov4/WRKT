-- Fix Storage Bucket RLS Policies
-- Run this in Supabase Dashboard → SQL Editor

-- First, check if RLS is enabled on the bucket
-- You may need to disable RLS or add proper policies

-- Option 1: Disable RLS on the storage bucket (easier, but less secure)
-- This makes the bucket public for uploads
-- UPDATE storage.buckets
-- SET public = true
-- WHERE name = 'user-images';

-- Option 2: Add proper RLS policies for the storage bucket (more secure)
-- Drop existing policies if any
DROP POLICY IF EXISTS "Allow authenticated users to upload their own images" ON storage.objects;
DROP POLICY IF EXISTS "Allow public to read all images" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to update their own images" ON storage.objects;
DROP POLICY IF EXISTS "Allow users to delete their own images" ON storage.objects;

-- Policy 1: Allow authenticated users to upload images to their own folder
CREATE POLICY "Allow authenticated users to upload their own images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'user-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Policy 2: Allow anyone to read all images (for public viewing)
CREATE POLICY "Allow public to read all images"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'user-images');

-- Policy 3: Allow users to update their own images (for upsert)
CREATE POLICY "Allow users to update their own images"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'user-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'user-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Policy 4: Allow users to delete their own images
CREATE POLICY "Allow users to delete their own images"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'user-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Verify the policies were created
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'storage' AND tablename = 'objects';
