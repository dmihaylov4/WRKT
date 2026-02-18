-- ============================================================================
-- SMART NUDGE TEST - SPECIFIC USERS
-- ============================================================================
-- Receiver (will get notification): 070b2df2-d640-47f5-bbd0-f6ba655681a5
-- Friend (who worked out):          912b6179-70db-418e-858d-3a259889de07
-- ============================================================================

-- Step 1: Verify both profiles exist
SELECT
    id,
    username,
    display_name
FROM profiles
WHERE id IN (
    '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid,
    '912b6179-70db-418e-858d-3a259889de07'::uuid
);
-- Expected: Should return 2 rows

-- Step 2: Check if they're friends
SELECT
    user_id,
    friend_id,
    status
FROM friendships
WHERE (
    (user_id = '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid AND friend_id = '912b6179-70db-418e-858d-3a259889de07'::uuid)
    OR
    (user_id = '912b6179-70db-418e-858d-3a259889de07'::uuid AND friend_id = '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid)
);
-- Expected: Should return at least 1 row with status = 'accepted'
-- If returns nothing, they're not friends yet

-- Step 3: If not friends, create friendship (run this only if Step 2 returned nothing)
/*
INSERT INTO friendships (user_id, friend_id, status)
VALUES
    ('070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid, '912b6179-70db-418e-858d-3a259889de07'::uuid, 'accepted'),
    ('912b6179-70db-418e-858d-3a259889de07'::uuid, '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid, 'accepted')
ON CONFLICT DO NOTHING;
*/

-- Step 4: Insert workout post from friend (the one who worked out)
INSERT INTO workout_posts (
    user_id,
    caption,
    workout_data,
    visibility,
    created_at
) VALUES (
    '912b6179-70db-418e-858d-3a259889de07'::uuid,  -- Friend who worked out
    'Just crushed leg day! 💪',
    jsonb_build_object(
        'workoutName', 'Leg Day',
        'startedAt', (NOW() - INTERVAL '1 hour')::text,
        'exercises', jsonb_build_array(
            jsonb_build_object(
                'name', 'Squat',
                'sets', jsonb_build_array(
                    jsonb_build_object('reps', 10, 'weight', 100),
                    jsonb_build_object('reps', 8, 'weight', 110),
                    jsonb_build_object('reps', 6, 'weight', 120)
                )
            ),
            jsonb_build_object(
                'name', 'Leg Press',
                'sets', jsonb_build_array(
                    jsonb_build_object('reps', 12, 'weight', 200),
                    jsonb_build_object('reps', 10, 'weight', 220)
                )
            )
        )
    ),
    'friends',
    NOW() - INTERVAL '25 minutes'  -- 25 minutes ago (within 1 hour threshold)
) RETURNING id, user_id, caption, created_at;

-- Step 5: Verify the post was created
SELECT
    wp.id,
    wp.caption,
    wp.created_at,
    p.username as author,
    wp.workout_data->>'workoutName' as workout_name,
    EXTRACT(EPOCH FROM (NOW() - wp.created_at))/60 as minutes_ago
FROM workout_posts wp
JOIN profiles p ON p.id = wp.user_id
WHERE wp.user_id = '912b6179-70db-418e-858d-3a259889de07'::uuid
ORDER BY wp.created_at DESC
LIMIT 1;

-- ============================================================================
-- TESTING INSTRUCTIONS
-- ============================================================================
-- 1. Run Steps 1-2 to verify profiles and friendship
-- 2. If Step 2 returns nothing, uncomment and run Step 3
-- 3. Run Step 4 to create the workout post
-- 4. On device with account 070b2df2...:
--    a. Open app
--    b. Enable "Smart nudges" in Preferences
--    c. Grant notification permissions
--    d. Go to Home tab
--    e. Wait 3-5 seconds for data to load
--    f. Put app in background (home screen)
--    g. Notification should appear!
--
-- Expected notification:
-- Title: "[Username] just worked out!"
-- Body: "[Username] completed Leg Day. Your turn to crush it!"

-- ============================================================================
-- CLEANUP (run this after testing)
-- ============================================================================
/*
DELETE FROM workout_posts
WHERE user_id = '912b6179-70db-418e-858d-3a259889de07'::uuid
AND caption = 'Just crushed leg day! 💪';
*/
