-- Migration: Nested Comments and User Mentions (Safe Version)
-- Description: Add support for 1-level comment replies and @mentions with notifications
-- Date: 2025-12-18
-- This version checks if components exist before creating them

-- ============================================================================
-- PART 1: Add parent_comment_id to post_comments (if not exists)
-- ============================================================================

-- Add parent_comment_id column to post_comments table (if it doesn't exist)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'post_comments' AND column_name = 'parent_comment_id'
  ) THEN
    ALTER TABLE post_comments
    ADD COLUMN parent_comment_id UUID REFERENCES post_comments(id) ON DELETE CASCADE;
  END IF;
END $$;

-- Create index for faster reply lookups (if it doesn't exist)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_post_comments_parent') THEN
    CREATE INDEX idx_post_comments_parent ON post_comments(parent_comment_id);
  END IF;
END $$;

-- Function to prevent nesting beyond 1 level
CREATE OR REPLACE FUNCTION check_comment_nesting()
RETURNS TRIGGER AS $$
BEGIN
  -- If this comment has a parent, check that parent doesn't have a parent
  IF NEW.parent_comment_id IS NOT NULL THEN
    -- Check if the parent comment itself has a parent (is a reply)
    IF EXISTS (
      SELECT 1 FROM post_comments
      WHERE id = NEW.parent_comment_id
      AND parent_comment_id IS NOT NULL
    ) THEN
      RAISE EXCEPTION 'Cannot reply to a reply - only 1 level of nesting allowed';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to enforce nesting depth (drop if exists, then create)
DROP TRIGGER IF EXISTS trigger_check_comment_nesting ON post_comments;
CREATE TRIGGER trigger_check_comment_nesting
BEFORE INSERT OR UPDATE ON post_comments
FOR EACH ROW
EXECUTE FUNCTION check_comment_nesting();

-- ============================================================================
-- PART 2: Create comment_mentions table (if not exists)
-- ============================================================================

CREATE TABLE IF NOT EXISTS comment_mentions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  comment_id UUID NOT NULL REFERENCES post_comments(id) ON DELETE CASCADE,
  mentioned_user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE(comment_id, mentioned_user_id)
);

-- Create indexes for faster lookups (if they don't exist)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_comment_mentions_comment') THEN
    CREATE INDEX idx_comment_mentions_comment ON comment_mentions(comment_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_comment_mentions_user') THEN
    CREATE INDEX idx_comment_mentions_user ON comment_mentions(mentioned_user_id);
  END IF;
END $$;

-- Enable RLS
ALTER TABLE comment_mentions ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Anyone can read mentions (drop if exists, then create)
DROP POLICY IF EXISTS "Anyone can read comment mentions" ON comment_mentions;
CREATE POLICY "Anyone can read comment mentions"
  ON comment_mentions FOR SELECT
  USING (true);

-- RLS Policy: Users can create mentions (drop if exists, then create)
DROP POLICY IF EXISTS "Users can create mentions" ON comment_mentions;
CREATE POLICY "Users can create mentions"
  ON comment_mentions FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

-- ============================================================================
-- PART 3: Database triggers for notifications
-- ============================================================================

-- Trigger function to notify mentioned users
CREATE OR REPLACE FUNCTION notify_mentioned_users()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO notifications (user_id, type, actor_id, comment_id, created_at)
  SELECT
    cm.mentioned_user_id,
    'comment_mention',
    (SELECT user_id FROM post_comments WHERE id = cm.comment_id),
    cm.comment_id,
    NOW()
  FROM comment_mentions cm
  WHERE cm.id = NEW.id
  AND cm.mentioned_user_id != (SELECT user_id FROM post_comments WHERE id = cm.comment_id);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for mention notifications (drop if exists, then create)
DROP TRIGGER IF EXISTS trigger_notify_mentions ON comment_mentions;
CREATE TRIGGER trigger_notify_mentions
AFTER INSERT ON comment_mentions
FOR EACH ROW
EXECUTE FUNCTION notify_mentioned_users();

-- Trigger function for comment replies
CREATE OR REPLACE FUNCTION notify_comment_reply()
RETURNS TRIGGER AS $$
BEGIN
  -- Only create notification if replying to someone else's comment
  IF NEW.parent_comment_id IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, actor_id, comment_id, created_at)
    SELECT
      pc.user_id,
      'comment_reply',
      NEW.user_id,
      NEW.id,
      NOW()
    FROM post_comments pc
    WHERE pc.id = NEW.parent_comment_id
    AND pc.user_id != NEW.user_id; -- Don't notify if replying to yourself
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for reply notifications (drop if exists, then create)
DROP TRIGGER IF EXISTS trigger_notify_reply ON post_comments;
CREATE TRIGGER trigger_notify_reply
AFTER INSERT ON post_comments
FOR EACH ROW
EXECUTE FUNCTION notify_comment_reply();

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Verify tables exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'comment_mentions') THEN
    RAISE EXCEPTION 'comment_mentions table was not created';
  END IF;
END $$;

-- Verify column exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'post_comments' AND column_name = 'parent_comment_id'
  ) THEN
    RAISE EXCEPTION 'parent_comment_id column was not added to post_comments';
  END IF;
END $$;

-- ============================================================================
-- SUCCESS MESSAGE
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE 'Migration completed successfully!';
  RAISE NOTICE 'Added: parent_comment_id column, comment_mentions table, triggers and indexes';
END $$;
