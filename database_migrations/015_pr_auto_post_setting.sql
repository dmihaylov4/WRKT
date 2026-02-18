-- ================================================
-- PR AUTO-POST SETTING
-- ================================================
-- Adds user preference for automatically posting PRs to social feed

-- Add auto_post_prs column to profiles table
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS auto_post_prs BOOLEAN DEFAULT true;

-- Add index for quick lookups
CREATE INDEX IF NOT EXISTS idx_profiles_auto_post_prs ON profiles(auto_post_prs);

-- Add comment
COMMENT ON COLUMN profiles.auto_post_prs IS
'User preference: automatically post Personal Records (PRs) to social feed. Default: true (enabled)';

-- Update existing users to have auto-post enabled by default
UPDATE profiles
SET auto_post_prs = true
WHERE auto_post_prs IS NULL;
