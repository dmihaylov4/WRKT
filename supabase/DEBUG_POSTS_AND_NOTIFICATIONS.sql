-- ============================================================================
-- DEBUG POSTS AND NOTIFICATIONS
-- ============================================================================
-- Receiver ID: 070b2df2-d640-47f5-bbd0-f6ba655681a5
-- Friend ID:   912b6179-70db-418e-858d-3a259889de07
-- ============================================================================

-- 1. Check if the test post actually exists in database
SELECT
    id,
    user_id,
    caption,
    visibility,
    created_at,
    workout_data->>'workoutName' as workout_name
FROM workout_posts
WHERE user_id = '912b6179-70db-418e-858d-3a259889de07'::uuid
ORDER BY created_at DESC
LIMIT 5;

-- 2. Check ALL posts in the database (to see if posts disappeared)
SELECT
    id,
    user_id,
    caption,
    visibility,
    created_at
FROM workout_posts
ORDER BY created_at DESC
LIMIT 10;

-- 3. Check RLS policies on workout_posts
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'workout_posts';

-- 4. Test if you can see posts as user 070b2df2... (simulating app query)
-- This simulates what the app does when fetching feed
SET LOCAL role authenticated;
SET LOCAL request.jwt.claims.sub TO '070b2df2-d640-47f5-bbd0-f6ba655681a5';

SELECT
    wp.id,
    wp.user_id,
    wp.caption,
    wp.visibility,
    wp.created_at,
    p.username,
    p.display_name
FROM workout_posts wp
JOIN profiles p ON p.id = wp.user_id
WHERE wp.created_at > NOW() - INTERVAL '30 days'
ORDER BY wp.created_at DESC
LIMIT 20;

RESET role;

-- 5. Check friendship status (again, to be sure)
SELECT
    f.id,
    f.user_id,
    f.friend_id,
    f.status,
    p1.username as user_username,
    p2.username as friend_username
FROM friendships f
LEFT JOIN profiles p1 ON p1.id = f.user_id
LEFT JOIN profiles p2 ON p2.id = f.friend_id
WHERE f.user_id IN (
    '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid,
    '912b6179-70db-418e-858d-3a259889de07'::uuid
)
OR f.friend_id IN (
    '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid,
    '912b6179-70db-418e-858d-3a259889de07'::uuid
);

-- 6. Check if workout_posts has RLS enabled
SELECT
    schemaname,
    tablename,
    rowsecurity
FROM pg_tables
WHERE tablename = 'workout_posts';

-- 7. Get EXACT query that app uses (to test it)
-- This is what PostRepository.fetchFeed() runs
SELECT
    wp.*,
    p.id as author_id,
    p.username,
    p.display_name,
    p.avatar_url,
    p.bio
FROM workout_posts wp
JOIN profiles p ON p.id = wp.user_id
WHERE (
    -- Own posts
    wp.user_id = '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid
    OR
    -- Friends' posts
    (
        wp.visibility = 'friends' AND
        EXISTS (
            SELECT 1 FROM friendships
            WHERE status = 'accepted'
            AND (
                (user_id = '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid AND friend_id = wp.user_id)
                OR
                (friend_id = '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid AND user_id = wp.user_id)
            )
        )
    )
)
AND wp.created_at >= NOW() - INTERVAL '30 days'
ORDER BY wp.created_at DESC
LIMIT 20;

-- ============================================================================
-- FIXES
-- ============================================================================

-- If RLS is blocking posts, temporarily disable it for testing:
-- (DON'T DO THIS IN PRODUCTION - only for debugging)
/*
ALTER TABLE workout_posts DISABLE ROW LEVEL SECURITY;
*/

-- Better fix: Add a permissive RLS policy
/*
CREATE POLICY "workout_posts_debug_view_all"
    ON workout_posts
    FOR SELECT
    USING (true);
*/

-- Re-enable RLS after testing
/*
ALTER TABLE workout_posts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "workout_posts_debug_view_all" ON workout_posts;
*/
