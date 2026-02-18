-- RLS Friendship Feed Debug
-- This query helps diagnose why friend posts aren't showing in the feed

-- Step 1: Check what auth.uid() returns
SELECT
    'Current auth.uid()' as check_type,
    auth.uid() as user_id;

-- Step 2: Check friendships for user 070b2df2-d640-47f5-bbd0-f6ba655681a5
SELECT
    'Friendships for user' as check_type,
    f.id,
    f.user_id,
    f.friend_id,
    f.status,
    'User initiated' as direction
FROM friendships f
WHERE f.user_id = '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid
  AND f.status = 'accepted'

UNION ALL

SELECT
    'Friendships for user' as check_type,
    f.id,
    f.user_id,
    f.friend_id,
    f.status,
    'Friend initiated' as direction
FROM friendships f
WHERE f.friend_id = '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid
  AND f.status = 'accepted';

-- Step 3: Check workout_posts with explicit friendship join
SELECT
    'Posts that should be visible' as check_type,
    wp.id,
    wp.user_id,
    wp.caption,
    wp.visibility,
    wp.created_at
FROM workout_posts wp
WHERE wp.user_id != '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid
  AND (
    -- Public posts (always visible)
    wp.visibility = 'public'
    OR
    -- Friends posts where friendship exists in either direction
    (
      wp.visibility = 'friends'
      AND EXISTS (
        SELECT 1
        FROM friendships f
        WHERE f.status = 'accepted'
          AND (
            (f.user_id = '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid AND f.friend_id = wp.user_id)
            OR
            (f.friend_id = '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid AND f.user_id = wp.user_id)
          )
      )
    )
  )
ORDER BY wp.created_at DESC
LIMIT 50;

-- Step 4: Test if the RLS policy logic works with a specific post
-- Replace POST_ID with an actual post ID from your database
SELECT
    'RLS policy test' as check_type,
    wp.id,
    wp.user_id,
    wp.visibility,
    -- Check if user owns post
    (wp.user_id = '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid) as is_owner,
    -- Check if post is public
    (wp.visibility = 'public') as is_public,
    -- Check if friendship exists (user_id direction)
    EXISTS (
        SELECT 1
        FROM friendships f
        WHERE f.status = 'accepted'
          AND f.user_id = '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid
          AND f.friend_id = wp.user_id
    ) as friend_via_user_id,
    -- Check if friendship exists (friend_id direction)
    EXISTS (
        SELECT 1
        FROM friendships f
        WHERE f.status = 'accepted'
          AND f.friend_id = '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid
          AND f.user_id = wp.user_id
    ) as friend_via_friend_id
FROM workout_posts wp
WHERE wp.user_id != '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid
LIMIT 10;

-- Step 5: Check the actual RLS policies on workout_posts
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual as using_expression,
    with_check as check_expression
FROM pg_policies
WHERE tablename = 'workout_posts'
ORDER BY policyname;
