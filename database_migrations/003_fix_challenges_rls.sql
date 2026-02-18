-- =====================================================
-- FIX INFINITE RECURSION IN CHALLENGE RLS POLICIES
-- =====================================================
-- Problem: Circular dependency between challenges and challenge_participants policies
-- Solution: Use security definer function to break the cycle
-- =====================================================

-- Drop existing problematic policies
DROP POLICY IF EXISTS "Public challenges visible to all" ON challenges;
DROP POLICY IF EXISTS "Users can view challenge participants" ON challenge_participants;

-- =====================================================
-- SECURITY DEFINER FUNCTION
-- =====================================================
-- This function runs with the permissions of the function creator (bypasses RLS)
-- Allowing us to break the circular dependency

CREATE OR REPLACE FUNCTION is_challenge_visible_to_user(challenge_id_param UUID, user_id_param UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  challenge_record RECORD;
BEGIN
  -- Get challenge details
  SELECT is_public, creator_id INTO challenge_record
  FROM challenges
  WHERE id = challenge_id_param;

  -- Challenge doesn't exist
  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  -- Public challenges are visible to everyone
  IF challenge_record.is_public THEN
    RETURN TRUE;
  END IF;

  -- Creator can always see their own challenges
  IF challenge_record.creator_id = user_id_param THEN
    RETURN TRUE;
  END IF;

  -- Check if user is a participant
  RETURN EXISTS (
    SELECT 1 FROM challenge_participants
    WHERE challenge_id = challenge_id_param
    AND user_id = user_id_param
  );
END;
$$;

-- =====================================================
-- NEW POLICIES (without circular dependency)
-- =====================================================

-- Challenges policy (simpler, no subquery)
CREATE POLICY "Users can view accessible challenges" ON challenges
  FOR SELECT USING (
    is_public = true
    OR creator_id = auth.uid()
    -- Don't check participants here to avoid circular dependency
  );

-- Challenge participants policy (uses security definer function)
CREATE POLICY "Users can view challenge participants for accessible challenges" ON challenge_participants
  FOR SELECT USING (
    -- Use security definer function to check visibility
    is_challenge_visible_to_user(challenge_id, auth.uid())
    OR user_id = auth.uid()
  );

-- =====================================================
-- GRANT EXECUTE PERMISSION
-- =====================================================

-- Allow authenticated users to execute the function
GRANT EXECUTE ON FUNCTION is_challenge_visible_to_user(UUID, UUID) TO authenticated;

-- =====================================================
-- SUCCESS MESSAGE
-- =====================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Challenge RLS policies fixed!';
  RAISE NOTICE 'Infinite recursion issue resolved';
  RAISE NOTICE 'Security definer function created: is_challenge_visible_to_user()';
END $$;
