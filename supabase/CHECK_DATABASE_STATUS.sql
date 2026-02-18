-- ============================================================================
-- DATABASE STATUS CHECK
-- ============================================================================
-- Run these queries one by one to diagnose the issue
-- ============================================================================

-- 1. Check if you're authenticated
SELECT auth.uid() as your_user_id;
-- If this returns NULL, you're not logged in to Supabase

-- 2. Check if friendships table exists
SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'friendships'
) as friendships_exists;

-- 3. Check if profiles table exists
SELECT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'profiles'
) as profiles_exists;

-- 4. Check all friendships in the database (for debugging)
SELECT
    f.id,
    f.user_id,
    f.friend_id,
    f.status,
    f.created_at
FROM friendships f
LIMIT 10;

-- 5. Check all profiles in the database
SELECT
    id,
    username,
    display_name,
    created_at
FROM profiles
LIMIT 10;

-- 6. Check your specific friendships (replace with your actual UUID)
SELECT
    f.friend_id,
    p.username,
    p.display_name,
    f.status
FROM friendships f
JOIN profiles p ON p.id = f.friend_id
WHERE f.user_id = 'YOUR_USER_ID_HERE'::uuid;  -- Replace with your UUID from query #1

-- 7. Alternative: Get ANY profile ID to use for testing
SELECT
    id,
    username,
    display_name
FROM profiles
WHERE id != auth.uid()  -- Get someone who's not you
LIMIT 1;
