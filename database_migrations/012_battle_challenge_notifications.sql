-- ================================================
-- BATTLE & CHALLENGE NOTIFICATIONS SYSTEM
-- ================================================
-- This migration adds comprehensive notification support for battles and challenges
-- including triggers for invites, status changes, lead changes, and milestones

-- Step 1: Add metadata column to notifications table (if not exists)
-- ================================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'notifications' AND column_name = 'metadata'
    ) THEN
        ALTER TABLE notifications ADD COLUMN metadata JSONB DEFAULT '{}'::jsonb;
        CREATE INDEX IF NOT EXISTS idx_notifications_metadata ON notifications USING gin(metadata);
    END IF;
END $$;

-- Step 2: Battle Invite Notification Trigger
-- ================================================
-- Notifies opponent when they receive a battle challenge
CREATE OR REPLACE FUNCTION notify_battle_invite()
RETURNS TRIGGER AS $$
BEGIN
    -- Only send notification when battle is first created and status is 'pending'
    IF TG_OP = 'INSERT' AND NEW.status = 'pending' THEN
        INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
        VALUES (
            NEW.opponent_id,
            'battle_invite',
            NEW.challenger_id,
            NEW.id,
            false,
            jsonb_build_object(
                'battle_type', NEW.battle_type,
                'duration', EXTRACT(day FROM (NEW.end_date - NEW.start_date))::text
            )
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS battle_invite_trigger ON battles;
CREATE TRIGGER battle_invite_trigger
    AFTER INSERT ON battles
    FOR EACH ROW
    EXECUTE FUNCTION notify_battle_invite();

-- Step 3: Battle Accepted/Declined Notification Trigger
-- ================================================
-- Notifies challenger when opponent accepts or declines
CREATE OR REPLACE FUNCTION notify_battle_status_change()
RETURNS TRIGGER AS $$
BEGIN
    -- Only trigger on status change from 'pending'
    IF TG_OP = 'UPDATE' AND OLD.status = 'pending' AND NEW.status != OLD.status THEN
        IF NEW.status = 'active' THEN
            -- Battle accepted
            INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
            VALUES (
                NEW.challenger_id,
                'battle_accepted',
                NEW.opponent_id,
                NEW.id,
                false,
                jsonb_build_object('battle_type', NEW.battle_type)
            );
        ELSIF NEW.status = 'declined' THEN
            -- Battle declined
            INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
            VALUES (
                NEW.challenger_id,
                'battle_declined',
                NEW.opponent_id,
                NEW.id,
                false,
                jsonb_build_object('battle_type', NEW.battle_type)
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS battle_status_change_trigger ON battles;
CREATE TRIGGER battle_status_change_trigger
    AFTER UPDATE ON battles
    FOR EACH ROW
    EXECUTE FUNCTION notify_battle_status_change();

-- Step 4: Battle Lead Change Notification Trigger
-- ================================================
-- Notifies users when they take/lose the lead in an active battle
CREATE OR REPLACE FUNCTION notify_battle_lead_change()
RETURNS TRIGGER AS $$
DECLARE
    old_leader UUID;
    new_leader UUID;
BEGIN
    -- Only process active battles with score changes
    IF NEW.status = 'active' AND (
        OLD.challenger_score != NEW.challenger_score OR
        OLD.opponent_score != NEW.opponent_score
    ) THEN
        -- Determine old leader
        IF OLD.challenger_score > OLD.opponent_score THEN
            old_leader := NEW.challenger_id;
        ELSIF OLD.opponent_score > OLD.challenger_score THEN
            old_leader := NEW.opponent_id;
        ELSE
            old_leader := NULL;  -- Tie
        END IF;

        -- Determine new leader
        IF NEW.challenger_score > NEW.opponent_score THEN
            new_leader := NEW.challenger_id;
        ELSIF NEW.opponent_score > NEW.challenger_score THEN
            new_leader := NEW.opponent_id;
        ELSE
            new_leader := NULL;  -- Tie
        END IF;

        -- If leader changed, send notifications
        IF old_leader IS DISTINCT FROM new_leader AND new_leader IS NOT NULL THEN
            -- Notify the new leader (they took the lead)
            INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
            VALUES (
                new_leader,
                'battle_lead_taken',
                CASE WHEN new_leader = NEW.challenger_id THEN NEW.opponent_id ELSE NEW.challenger_id END,
                NEW.id,
                false,
                jsonb_build_object(
                    'your_score', CASE WHEN new_leader = NEW.challenger_id THEN NEW.challenger_score::text ELSE NEW.opponent_score::text END,
                    'opponent_score', CASE WHEN new_leader = NEW.challenger_id THEN NEW.opponent_score::text ELSE NEW.challenger_score::text END
                )
            );

            -- Notify the old leader if there was one (they lost the lead)
            IF old_leader IS NOT NULL THEN
                INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
                VALUES (
                    old_leader,
                    'battle_lead_lost',
                    CASE WHEN old_leader = NEW.challenger_id THEN NEW.opponent_id ELSE NEW.challenger_id END,
                    NEW.id,
                    false,
                    jsonb_build_object(
                        'your_score', CASE WHEN old_leader = NEW.challenger_id THEN NEW.challenger_score::text ELSE NEW.opponent_score::text END,
                        'opponent_score', CASE WHEN old_leader = NEW.challenger_id THEN NEW.opponent_score::text ELSE NEW.challenger_score::text END
                    )
                );
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS battle_lead_change_trigger ON battles;
CREATE TRIGGER battle_lead_change_trigger
    AFTER UPDATE ON battles
    FOR EACH ROW
    EXECUTE FUNCTION notify_battle_lead_change();

-- Step 5: Battle Completion Notification Trigger
-- ================================================
-- Notifies both participants when battle ends with winner/loser specific messages
CREATE OR REPLACE FUNCTION notify_battle_completion()
RETURNS TRIGGER AS $$
DECLARE
    winner UUID;
    loser UUID;
BEGIN
    -- Only trigger when status changes to 'completed'
    IF TG_OP = 'UPDATE' AND OLD.status != 'completed' AND NEW.status = 'completed' THEN
        -- Determine winner and loser
        IF NEW.winner_id IS NOT NULL THEN
            winner := NEW.winner_id;
            loser := CASE WHEN NEW.winner_id = NEW.challenger_id THEN NEW.opponent_id ELSE NEW.challenger_id END;

            -- Notify winner
            INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
            VALUES (
                winner,
                'battle_victory',
                loser,
                NEW.id,
                false,
                jsonb_build_object(
                    'final_score', CASE WHEN winner = NEW.challenger_id THEN NEW.challenger_score::text ELSE NEW.opponent_score::text END,
                    'opponent_score', CASE WHEN winner = NEW.challenger_id THEN NEW.opponent_score::text ELSE NEW.challenger_score::text END,
                    'battle_type', NEW.battle_type
                )
            );

            -- Notify loser
            INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
            VALUES (
                loser,
                'battle_defeat',
                winner,
                NEW.id,
                false,
                jsonb_build_object(
                    'final_score', CASE WHEN loser = NEW.challenger_id THEN NEW.challenger_score::text ELSE NEW.opponent_score::text END,
                    'opponent_score', CASE WHEN loser = NEW.challenger_id THEN NEW.opponent_score::text ELSE NEW.challenger_score::text END,
                    'battle_type', NEW.battle_type
                )
            );
        ELSE
            -- Tie - notify both with generic completion
            INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
            VALUES
                (NEW.challenger_id, 'battle_completed', NEW.opponent_id, NEW.id, false, jsonb_build_object('result', 'tie')),
                (NEW.opponent_id, 'battle_completed', NEW.challenger_id, NEW.id, false, jsonb_build_object('result', 'tie'));
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS battle_completion_trigger ON battles;
CREATE TRIGGER battle_completion_trigger
    AFTER UPDATE ON battles
    FOR EACH ROW
    EXECUTE FUNCTION notify_battle_completion();

-- Step 6: Challenge Join Notification
-- ================================================
-- Notifies challenge creator when someone joins their challenge
CREATE OR REPLACE FUNCTION notify_challenge_joined()
RETURNS TRIGGER AS $$
DECLARE
    challenge_record RECORD;
BEGIN
    -- Get challenge details
    SELECT * INTO challenge_record FROM challenges WHERE id = NEW.challenge_id;

    -- Only notify creator if this isn't the creator joining their own challenge
    IF TG_OP = 'INSERT' AND NEW.user_id != challenge_record.creator_id THEN
        INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
        VALUES (
            challenge_record.creator_id,
            'challenge_joined',
            NEW.user_id,
            challenge_record.id,
            false,
            jsonb_build_object(
                'challenge_title', challenge_record.title,
                'participant_count', (
                    SELECT COUNT(*) FROM challenge_participants WHERE challenge_id = challenge_record.id
                )::text
            )
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS challenge_joined_trigger ON challenge_participants;
CREATE TRIGGER challenge_joined_trigger
    AFTER INSERT ON challenge_participants
    FOR EACH ROW
    EXECUTE FUNCTION notify_challenge_joined();

-- Step 7: Challenge Milestone Notification
-- ================================================
-- Notifies user when they hit 25%, 50%, 75%, or 100% progress
CREATE OR REPLACE FUNCTION notify_challenge_milestone()
RETURNS TRIGGER AS $$
DECLARE
    challenge_record RECORD;
    progress_percent NUMERIC;
    milestone INT;
BEGIN
    -- Only process actual progress changes
    IF TG_OP = 'UPDATE' AND OLD.progress != NEW.progress THEN
        -- Get challenge details
        SELECT * INTO challenge_record FROM challenges WHERE id = NEW.challenge_id;

        -- Calculate progress percentage
        IF challenge_record.goal_value > 0 THEN
            progress_percent := (NEW.progress / challenge_record.goal_value) * 100;

            -- Check for milestone achievement
            IF progress_percent >= 100 AND OLD.progress / challenge_record.goal_value * 100 < 100 THEN
                milestone := 100;
            ELSIF progress_percent >= 75 AND OLD.progress / challenge_record.goal_value * 100 < 75 THEN
                milestone := 75;
            ELSIF progress_percent >= 50 AND OLD.progress / challenge_record.goal_value * 100 < 50 THEN
                milestone := 50;
            ELSIF progress_percent >= 25 AND OLD.progress / challenge_record.goal_value * 100 < 25 THEN
                milestone := 25;
            ELSE
                RETURN NEW;  -- No milestone crossed
            END IF;

            -- Send milestone notification
            INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
            VALUES (
                NEW.user_id,
                'challenge_milestone',
                NEW.user_id,  -- Self notification
                challenge_record.id,
                false,
                jsonb_build_object(
                    'milestone', milestone::text,
                    'challenge_title', challenge_record.title,
                    'progress', NEW.progress::text,
                    'goal', challenge_record.goal_value::text
                )
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS challenge_milestone_trigger ON challenge_participants;
CREATE TRIGGER challenge_milestone_trigger
    AFTER UPDATE ON challenge_participants
    FOR EACH ROW
    EXECUTE FUNCTION notify_challenge_milestone();

-- Step 8: Challenge Leaderboard Position Change
-- ================================================
-- Notifies user when they move up in rankings (top 10 only to avoid spam)
CREATE OR REPLACE FUNCTION notify_challenge_leaderboard_change()
RETURNS TRIGGER AS $$
DECLARE
    challenge_record RECORD;
    old_rank INT;
    new_rank INT;
BEGIN
    IF TG_OP = 'UPDATE' AND (OLD.progress != NEW.progress OR OLD.rank != NEW.rank) THEN
        -- Get challenge details
        SELECT * INTO challenge_record FROM challenges WHERE id = NEW.challenge_id;

        old_rank := OLD.rank;
        new_rank := NEW.rank;

        -- Only notify for improvements in top 10
        IF new_rank IS NOT NULL AND new_rank <= 10 AND (old_rank IS NULL OR new_rank < old_rank) THEN
            INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
            VALUES (
                NEW.user_id,
                'challenge_leaderboard_change',
                NEW.user_id,  -- Self notification
                challenge_record.id,
                false,
                jsonb_build_object(
                    'position', new_rank::text,
                    'old_position', COALESCE(old_rank::text, 'unranked'),
                    'challenge_title', challenge_record.title
                )
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS challenge_leaderboard_trigger ON challenge_participants;
CREATE TRIGGER challenge_leaderboard_trigger
    AFTER UPDATE ON challenge_participants
    FOR EACH ROW
    EXECUTE FUNCTION notify_challenge_leaderboard_change();

-- ================================================
-- Grant permissions and enable realtime
-- ================================================

-- Ensure RLS is enabled
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Refresh realtime publication to include new columns
-- Note: notifications table should already be in publication
-- This just ensures the new metadata column is included
DO $$
BEGIN
    -- Check if notifications is already in publication
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'notifications'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
    END IF;
END $$;

COMMENT ON COLUMN notifications.metadata IS 'JSONB metadata for additional notification data (positions, scores, milestones, etc.)';

-- ================================================
-- Summary
-- ================================================
-- ✅ Added metadata column to notifications
-- ✅ Battle invite notifications (on insert)
-- ✅ Battle accept/decline notifications (on status change)
-- ✅ Battle lead change notifications (on score update)
-- ✅ Battle completion notifications (winner/loser/tie)
-- ✅ Challenge join notifications (notify creator)
-- ✅ Challenge milestone notifications (25%, 50%, 75%, 100%)
-- ✅ Challenge leaderboard notifications (top 10 rank improvements)
--
-- Note: Battle ending soon and Challenge ending soon notifications
-- should be handled by a cron job or scheduled cloud function since
-- they are time-based, not event-based triggers.
