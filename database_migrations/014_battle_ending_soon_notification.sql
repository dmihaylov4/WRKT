-- ================================================
-- BATTLE ENDING SOON NOTIFICATION
-- ================================================
-- Sends notification 24 hours before battle ends
-- Called by app when fetching active battles

-- Add column to track when we last sent ending soon notification
ALTER TABLE battles ADD COLUMN IF NOT EXISTS ending_soon_notified_at TIMESTAMPTZ DEFAULT NULL;

-- Function to check and send ending soon notifications for active battles
CREATE OR REPLACE FUNCTION send_battle_ending_soon_notifications()
RETURNS TABLE(battle_id UUID, notifications_sent INTEGER) AS $$
DECLARE
    battle_rec RECORD;
    notif_count INTEGER := 0;
BEGIN
    -- Find active battles ending in 12-24 hours that haven't been notified yet
    FOR battle_rec IN
        SELECT
            b.id,
            b.challenger_id,
            b.opponent_id,
            b.end_date,
            b.battle_type,
            b.challenger_score,
            b.opponent_score
        FROM battles b
        WHERE
            b.status = 'active'
            AND b.end_date > NOW()
            AND b.end_date <= NOW() + INTERVAL '24 hours'
            AND (b.ending_soon_notified_at IS NULL OR b.ending_soon_notified_at < NOW() - INTERVAL '24 hours')
    LOOP
        -- Send notification to challenger
        INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
        VALUES (
            battle_rec.challenger_id,
            'battle_ending_soon',
            battle_rec.opponent_id,
            battle_rec.id,
            false,
            jsonb_build_object(
                'hours_remaining', EXTRACT(EPOCH FROM (battle_rec.end_date - NOW())) / 3600,
                'your_score', battle_rec.challenger_score::text,
                'opponent_score', battle_rec.opponent_score::text,
                'battle_type', battle_rec.battle_type
            )
        );

        -- Send notification to opponent
        INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
        VALUES (
            battle_rec.opponent_id,
            'battle_ending_soon',
            battle_rec.challenger_id,
            battle_rec.id,
            false,
            jsonb_build_object(
                'hours_remaining', EXTRACT(EPOCH FROM (battle_rec.end_date - NOW())) / 3600,
                'your_score', battle_rec.opponent_score::text,
                'opponent_score', battle_rec.challenger_score::text,
                'battle_type', battle_rec.battle_type
            )
        );

        -- Mark as notified
        UPDATE battles
        SET ending_soon_notified_at = NOW()
        WHERE id = battle_rec.id;

        notif_count := notif_count + 2; -- Two notifications sent (one per participant)
    END LOOP;

    RETURN QUERY SELECT NULL::UUID, notif_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comment
COMMENT ON FUNCTION send_battle_ending_soon_notifications() IS
'Checks for active battles ending in 24 hours and sends notifications to participants. Called by app.';

-- Create index for efficient querying
CREATE INDEX IF NOT EXISTS idx_battles_ending_soon ON battles(status, end_date, ending_soon_notified_at)
WHERE status = 'active';
