-- ============================================================================
-- PROFILE BIRTH YEAR
-- ============================================================================
-- Adds birth_year column to profiles table so partners can calculate
-- each other's max HR for accurate HR zone display during virtual runs.
-- Users set their age locally; the app converts to birth_year and syncs here.
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'profiles' AND column_name = 'birth_year'
    ) THEN
        ALTER TABLE profiles ADD COLUMN birth_year INTEGER;
        COMMENT ON COLUMN profiles.birth_year IS 'User birth year for HR zone calculation (220 - age). Synced from local age setting.';
    END IF;
END $$;
