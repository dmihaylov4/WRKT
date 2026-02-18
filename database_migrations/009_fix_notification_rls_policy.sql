-- Migration: Fix Notification RLS Policy
-- Description: Allow authenticated users to insert notifications (for fallback when triggers don't work)
-- Date: 2025-12-19

-- ============================================================================
-- PART 1: Drop and Recreate the INSERT Policy
-- ============================================================================

-- Drop the existing INSERT policy
DROP POLICY IF EXISTS "System can insert notifications" ON notifications;

-- Create a more permissive INSERT policy
-- Allows both system (via triggers with SECURITY DEFINER) and authenticated users to insert
CREATE POLICY "Allow authenticated inserts"
    ON notifications FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- Also create a policy for the service role (used by triggers)
CREATE POLICY "Service role can insert"
    ON notifications FOR INSERT
    TO service_role
    WITH CHECK (true);

-- ============================================================================
-- PART 2: Verify Policies
-- ============================================================================

-- List all policies on notifications table
SELECT
    polname AS policy_name,
    polcmd AS command,
    polroles::regrole::text AS role,
    qual AS using_expression,
    with_check AS check_expression
FROM pg_policy
WHERE polrelid = 'notifications'::regclass
ORDER BY polname;

-- ============================================================================
-- Success Message
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE 'Migration completed successfully!';
  RAISE NOTICE 'Notification RLS policies updated to allow authenticated inserts';
END $$;
