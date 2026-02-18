-- Add Privacy Settings to Profiles
-- Run this in Supabase Dashboard → SQL Editor

-- Add is_private column to profiles table
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS is_private boolean DEFAULT false NOT NULL;

-- Add index for faster filtering
CREATE INDEX IF NOT EXISTS profiles_is_private_idx ON profiles(is_private);

-- Verify the column was added
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'profiles'
  AND column_name = 'is_private';
