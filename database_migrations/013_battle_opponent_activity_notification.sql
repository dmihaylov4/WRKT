-- ================================================
-- BATTLE OPPONENT ACTIVITY NOTIFICATION
-- ================================================
-- Notifies user when their opponent logs a workout during an active battle
-- This creates real-time engagement and competitive tension

-- Create trigger function for opponent activity
CREATE OR REPLACE FUNCTION notify_battle_opponent_activity()
RETURNS TRIGGER AS $$
DECLARE
    battle_record RECORD;
    opponent_id UUID;
    score_increase DECIMAL;
BEGIN
    -- Only process score increases in active battles
    IF NEW.status = 'active' AND (
        (OLD.challenger_score != NEW.challenger_score) OR
        (OLD.opponent_score != NEW.opponent_score)
    ) THEN
        -- Determine who just worked out and their opponent
        IF OLD.challenger_score != NEW.challenger_score THEN
            -- Challenger just worked out
            opponent_id := NEW.opponent_id;
            score_increase := NEW.challenger_score - OLD.challenger_score;

            -- Notify opponent
            INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
            VALUES (
                opponent_id,
                'battle_opponent_activity',
                NEW.challenger_id,
                NEW.id,
                false,
                jsonb_build_object(
                    'score_increase', score_increase::text,
                    'new_score', NEW.challenger_score::text,
                    'your_score', NEW.opponent_score::text,
                    'battle_type', NEW.battle_type
                )
            );
        END IF;

        IF OLD.opponent_score != NEW.opponent_score THEN
            -- Opponent just worked out
            opponent_id := NEW.challenger_id;
            score_increase := NEW.opponent_score - OLD.opponent_score;

            -- Notify challenger
            INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
            VALUES (
                opponent_id,
                'battle_opponent_activity',
                NEW.opponent_id,
                NEW.id,
                false,
                jsonb_build_object(
                    'score_increase', score_increase::text,
                    'new_score', NEW.opponent_score::text,
                    'your_score', NEW.challenger_score::text,
                    'battle_type', NEW.battle_type
                )
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS battle_opponent_activity_trigger ON battles;

-- Create trigger
CREATE TRIGGER battle_opponent_activity_trigger
    AFTER UPDATE ON battles
    FOR EACH ROW
    EXECUTE FUNCTION notify_battle_opponent_activity();

-- Add comment
COMMENT ON TRIGGER battle_opponent_activity_trigger ON battles IS
'Sends real-time notification when opponent logs a workout in an active battle';
