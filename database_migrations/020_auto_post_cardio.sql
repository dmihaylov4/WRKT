-- ============================================================================
-- AUTO-POST CARDIO SETTING
-- ============================================================================
-- This migration adds the auto_post_cardio column to profiles table
-- for automatically sharing cardio workouts (runs > 1km) to the social feed
-- ============================================================================

-- Add auto_post_cardio column to profiles table
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'profiles' AND column_name = 'auto_post_cardio'
    ) THEN
        ALTER TABLE profiles ADD COLUMN auto_post_cardio BOOLEAN DEFAULT true;
        COMMENT ON COLUMN profiles.auto_post_cardio IS 'When true, cardio workouts over 1km are automatically shared to social feed';
    END IF;
END $$;
