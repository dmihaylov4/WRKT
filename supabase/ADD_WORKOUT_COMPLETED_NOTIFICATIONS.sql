-- ============================================================================
-- Workout Completed Notifications with Workout Type Metadata
--
-- Creates a workoutCompleted notification for every accepted friend when
-- a workout post is inserted. Metadata carries:
--   workout_type  → e.g. "Running", "Cycling"  (absent for strength)
--   distance_km   → e.g. "5.12"                (absent when unknown / strength)
--
-- Safe to re-run: trigger and function are replaced if they already exist.
-- ============================================================================

-- Add metadata column if the table was created before it was added
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS metadata JSONB;

-- Drop old trigger/function so we can replace cleanly
DROP TRIGGER IF EXISTS on_workout_post_created ON workout_posts;
DROP FUNCTION IF EXISTS create_workout_completed_notifications() CASCADE;

-- ============================================================================
-- Function
-- ============================================================================

CREATE OR REPLACE FUNCTION create_workout_completed_notifications()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    notification_metadata JSONB;
    workout_type          TEXT;
    distance_m            NUMERIC;
BEGIN
    -- Private posts don't notify friends
    IF NEW.visibility = 'private' THEN
        RETURN NEW;
    END IF;

    -- Extract cardio workout type (NULL for strength workouts)
    workout_type := NEW.workout_data->>'cardioWorkoutType';

    -- Build metadata
    notification_metadata := '{}'::JSONB;

    IF workout_type IS NOT NULL THEN
        notification_metadata := notification_metadata
            || jsonb_build_object('workout_type', workout_type);

        -- matchedHealthKitDistance is stored in metres; convert to km
        IF NEW.workout_data->>'matchedHealthKitDistance' IS NOT NULL THEN
            distance_m := (NEW.workout_data->>'matchedHealthKitDistance')::NUMERIC;
            IF distance_m > 0 THEN
                notification_metadata := notification_metadata
                    || jsonb_build_object('distance_km',
                           ROUND(distance_m / 1000.0, 2)::TEXT);
            END IF;
        END IF;
    END IF;

    -- Insert one notification per accepted friend
    INSERT INTO notifications (user_id, type, actor_id, target_id, read, metadata)
    SELECT
        CASE
            WHEN f.user_id = NEW.user_id THEN f.friend_id
            ELSE f.user_id
        END,
        'workout_completed',
        NEW.user_id,
        NEW.id,
        false,
        notification_metadata
    FROM friendships f
    WHERE (f.user_id = NEW.user_id OR f.friend_id = NEW.user_id)
      AND f.status = 'accepted';

    RETURN NEW;
END;
$$;

-- ============================================================================
-- Trigger
-- ============================================================================

CREATE TRIGGER on_workout_post_created
    AFTER INSERT ON workout_posts
    FOR EACH ROW
    EXECUTE FUNCTION create_workout_completed_notifications();

-- ============================================================================
-- Verify
-- ============================================================================

SELECT
    trigger_name,
    event_manipulation,
    event_object_table,
    action_timing
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND trigger_name = 'on_workout_post_created';
