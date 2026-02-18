-- ================================================
-- INSTANT NOTIFICATION TESTING COMMANDS
-- ================================================
-- Your user ID (receiving notifications): 070b2df2-d640-47f5-bbd0-f6ba655681a5
-- Other user ID (sending notifications): 912b6179-70db-418e-858d-3a259889de07

-- ================================================
-- TEST 1: Battle Invite Notification
-- ================================================
-- This creates a battle invite from the other user to you
-- You should see this notification appear instantly in your app!

INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
VALUES (
    '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid,  -- You (receiving)
    'battle_invite',
    '912b6179-70db-418e-858d-3a259889de07'::uuid,  -- Other user (challenger)
    gen_random_uuid(),  -- Random battle ID
    false,
    '{"battle_type": "volume", "duration": "7"}'::jsonb
);

-- ================================================
-- TEST 2: Battle Lead Lost Notification
-- ================================================
-- Simulates you losing the lead in a battle

INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
VALUES (
    '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid,
    'battle_lead_lost',
    '912b6179-70db-418e-858d-3a259889de07'::uuid,
    gen_random_uuid(),
    false,
    '{"your_score": "3500", "opponent_score": "4200"}'::jsonb
);

-- ================================================
-- TEST 3: Battle Victory Notification
-- ================================================
-- Simulates winning a battle

INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
VALUES (
    '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid,
    'battle_victory',
    '912b6179-70db-418e-858d-3a259889de07'::uuid,
    gen_random_uuid(),
    false,
    '{"final_score": "8500", "opponent_score": "7200", "battle_type": "volume"}'::jsonb
);

-- ================================================
-- TEST 4: Challenge Milestone Notification
-- ================================================
-- Simulates hitting 50% progress in a challenge

INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
VALUES (
    '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid,
    'challenge_milestone',
    '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid,  -- Self notification
    gen_random_uuid(),
    false,
    '{"milestone": "50", "progress": "50000", "goal": "100000", "challenge_title": "100K Club"}'::jsonb
);

-- ================================================
-- TEST 5: Challenge Leaderboard Change
-- ================================================
-- Simulates moving up to position #5

INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
VALUES (
    '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid,
    'challenge_leaderboard_change',
    '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid,
    gen_random_uuid(),
    false,
    '{"position": "5", "old_position": "12", "challenge_title": "Push-Up Hero"}'::jsonb
);

-- ================================================
-- TEST 6: Battle Opponent Activity
-- ================================================
-- Simulates opponent logging a workout

INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
VALUES (
    '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid,
    'battle_opponent_activity',
    '912b6179-70db-418e-858d-3a259889de07'::uuid,
    gen_random_uuid(),
    false,
    '{}'::jsonb
);

-- ================================================
-- VERIFY: Check Your Notifications
-- ================================================
-- Run this to see all notifications you just created

SELECT
    n.type,
    p.username as from_user,
    n.created_at,
    n.read,
    n.metadata
FROM notifications n
JOIN profiles p ON n.actor_id = p.id
WHERE n.user_id = '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid
ORDER BY n.created_at DESC
LIMIT 10;

-- ================================================
-- CLEANUP: Delete Test Notifications
-- ================================================
-- Run this when you want to clear the test notifications

DELETE FROM notifications
WHERE user_id = '070b2df2-d640-47f5-bbd0-f6ba655681a5'::uuid
  AND created_at > NOW() - INTERVAL '5 minutes';

-- ================================================
-- INSTRUCTIONS
-- ================================================
-- 1. Copy any INSERT command above
-- 2. Paste into Supabase SQL Editor
-- 3. Run it
-- 4. Check your app - notification should appear INSTANTLY!
-- 5. Check notification bell badge increments
-- 6. Tap notification to see it navigate (placeholder view)
-- 7. Run VERIFY query to see in database
-- 8. Run CLEANUP when done testing
