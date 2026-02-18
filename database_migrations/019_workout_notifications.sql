-- ============================================================================
-- WORKOUT COMPLETION NOTIFICATIONS & MUTED NOTIFICATIONS
-- ============================================================================
-- This migration adds:
-- 1. workout_completed notification type to the notifications table
-- 2. muted_notifications column to friendships table
-- 3. Trigger to notify friends when a workout post is created
-- ============================================================================

-- Step 1: Add muted_notifications column to friendships table
-- ============================================================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'friendships' AND column_name = 'muted_notifications'
    ) THEN
        ALTER TABLE friendships ADD COLUMN muted_notifications BOOLEAN DEFAULT false;
        COMMENT ON COLUMN friendships.muted_notifications IS 'When true, user will not receive notifications from this friend';
    END IF;
END $$;

-- Step 2: Update notifications type CHECK constraint to include workout_completed
-- ============================================================================
-- First, drop the existing constraint and recreate with new type
DO $$
BEGIN
    -- Drop existing constraint if it exists
    ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

    -- Add updated constraint with workout_completed
    ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
        CHECK (type IN (
            'like', 'comment', 'mention', 'friend_request',
            'friend_accepted', 'challenge_invite', 'battle_invite',
            'battle_accepted', 'battle_completed', 'battle_ending_soon',
            'challenge_completed', 'battle_opponent_activity',
            'battle_declined', 'battle_lead_taken', 'battle_lead_lost',
            'battle_victory', 'battle_defeat',
            'post_like', 'post_comment', 'comment_reply', 'comment_mention',
            'challenge_joined', 'challenge_milestone', 'challenge_leaderboard_change',
            'challenge_ending_soon', 'challenge_new_participant',
            'workout_completed'
        ));
END $$;

-- Step 3: Create function to notify friends on workout post creation
-- ============================================================================
CREATE OR REPLACE FUNCTION notify_friends_on_workout_post()
RETURNS TRIGGER AS $$
DECLARE
    friend_record RECORD;
BEGIN
    -- Only notify for posts visible to friends (not private)
    IF NEW.visibility IN ('friends', 'public') THEN
        -- Loop through all accepted friendships where current user is involved
        -- and muted_notifications is false
        FOR friend_record IN
            SELECT
                CASE
                    WHEN f.user_id = NEW.user_id THEN f.friend_id
                    ELSE f.user_id
                END as friend_id,
                f.id as friendship_id
            FROM friendships f
            WHERE f.status = 'accepted'
            AND (f.user_id = NEW.user_id OR f.friend_id = NEW.user_id)
            AND f.muted_notifications = false
        LOOP
            -- Skip if the friend has muted notifications from the other direction
            -- (check if this friend has the poster muted)
            IF NOT EXISTS (
                SELECT 1 FROM friendships f2
                WHERE f2.status = 'accepted'
                AND (
                    (f2.user_id = friend_record.friend_id AND f2.friend_id = NEW.user_id)
                    OR (f2.friend_id = friend_record.friend_id AND f2.user_id = NEW.user_id)
                )
                AND f2.muted_notifications = true
            ) THEN
                -- Check if notification already exists (prevent duplicates)
                IF NOT EXISTS (
                    SELECT 1 FROM notifications n
                    WHERE n.user_id = friend_record.friend_id
                    AND n.type = 'workout_completed'
                    AND n.actor_id = NEW.user_id
                    AND n.target_id = NEW.id
                ) THEN
                    -- Create notification for the friend
                    INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
                    VALUES (
                        friend_record.friend_id,
                        'workout_completed',
                        NEW.user_id,
                        NEW.id,
                        false,
                        jsonb_build_object(
                            'post_id', NEW.id::text,
                            'workout_name', COALESCE(NEW.workout_data->>'workoutName', 'Workout')
                        )
                    );
                END IF;
            END IF;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 4: Create trigger for workout post notifications
-- ============================================================================
DROP TRIGGER IF EXISTS workout_post_notification_trigger ON workout_posts;
CREATE TRIGGER workout_post_notification_trigger
    AFTER INSERT ON workout_posts
    FOR EACH ROW
    EXECUTE FUNCTION notify_friends_on_workout_post();

-- Step 5: Add index for efficient muted_notifications queries
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_friendships_muted_notifications
    ON friendships (muted_notifications)
    WHERE muted_notifications = true;

-- Step 6: Add unique index to prevent duplicate workout_completed notifications
-- ============================================================================
-- This prevents the same notification from being created twice for the same post/user combo
CREATE UNIQUE INDEX IF NOT EXISTS idx_notifications_workout_completed_unique
    ON notifications (user_id, type, actor_id, target_id)
    WHERE type = 'workout_completed';

-- ============================================================================
-- COMMENTS
-- ============================================================================
COMMENT ON FUNCTION notify_friends_on_workout_post() IS
    'Notifies friends when a user creates a workout post, respecting mute settings';
