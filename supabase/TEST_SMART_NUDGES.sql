-- ============================================================================
-- QUICK SMART NUDGE TEST SETUP
-- ============================================================================
-- This creates only the minimum needed to test smart nudges
-- Run this if you're getting errors with the full migration
-- ============================================================================

-- Check if workout_posts exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'workout_posts') THEN
        -- Create workout_posts table
        CREATE TABLE workout_posts (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
            caption TEXT,
            workout_data JSONB NOT NULL,
            image_urls TEXT[],
            visibility TEXT NOT NULL DEFAULT 'friends' CHECK (visibility IN ('public', 'friends', 'private')),
            likes_count INTEGER DEFAULT 0,
            comments_count INTEGER DEFAULT 0,
            created_at TIMESTAMPTZ DEFAULT NOW(),
            updated_at TIMESTAMPTZ DEFAULT NOW()
        );

        -- Enable RLS
        ALTER TABLE workout_posts ENABLE ROW LEVEL SECURITY;

        -- Basic RLS policies
        CREATE POLICY "Public posts viewable by all"
            ON workout_posts FOR SELECT
            USING (visibility = 'public');

        CREATE POLICY "Friends posts viewable by friends"
            ON workout_posts FOR SELECT
            USING (
                visibility = 'friends' AND (
                    user_id = auth.uid() OR
                    EXISTS (
                        SELECT 1 FROM friendships
                        WHERE status = 'accepted'
                        AND ((user_id = auth.uid() AND friend_id = workout_posts.user_id)
                             OR (friend_id = auth.uid() AND user_id = workout_posts.user_id))
                    )
                )
            );

        CREATE POLICY "Users can create own posts"
            ON workout_posts FOR INSERT
            WITH CHECK (auth.uid() = user_id);

        RAISE NOTICE 'workout_posts table created successfully';
    ELSE
        RAISE NOTICE 'workout_posts table already exists, skipping creation';
    END IF;
END $$;

-- ============================================================================
-- TEST DATA INSERTION
-- ============================================================================
-- Replace the UUIDs below with your actual user IDs

-- Step 1: Find your friends
-- Run this first to get friend IDs:
/*
SELECT
    f.friend_id,
    p.username,
    p.display_name
FROM friendships f
JOIN profiles p ON p.id = f.friend_id
WHERE f.user_id = auth.uid()  -- This gets YOUR user ID automatically
    AND f.status = 'accepted'
LIMIT 5;
*/

-- Step 2: Insert test workout post
-- Replace 'FRIEND_USER_ID_HERE' with actual UUID from Step 1
/*
INSERT INTO workout_posts (
    user_id,
    caption,
    workout_data,
    visibility,
    created_at
) VALUES (
    'FRIEND_USER_ID_HERE'::uuid,  -- Replace with friend's UUID
    'Leg day complete! 💪',
    jsonb_build_object(
        'workoutName', 'Leg Day',
        'startedAt', (NOW() - INTERVAL '1 hour')::text,
        'exercises', jsonb_build_array(
            jsonb_build_object(
                'name', 'Squat',
                'sets', jsonb_build_array(
                    jsonb_build_object('reps', 10, 'weight', 100)
                )
            ),
            jsonb_build_object(
                'name', 'Leg Press',
                'sets', jsonb_build_array(
                    jsonb_build_object('reps', 12, 'weight', 200)
                )
            )
        )
    ),
    'friends',
    NOW() - INTERVAL '30 minutes'
) RETURNING id, user_id, caption, created_at;
*/

-- Step 3: Verify the post was created
/*
SELECT
    wp.id,
    wp.caption,
    wp.created_at,
    p.username as author,
    wp.workout_data->>'workoutName' as workout_name
FROM workout_posts wp
JOIN profiles p ON p.id = wp.user_id
WHERE wp.created_at > NOW() - INTERVAL '1 day'
ORDER BY wp.created_at DESC
LIMIT 5;
*/

-- ============================================================================
-- CLEANUP (run this to remove test data)
-- ============================================================================
/*
DELETE FROM workout_posts
WHERE caption = 'Leg day complete! 💪'
AND created_at > NOW() - INTERVAL '1 day';
*/
