-- Migration: Update Notifications for Comment Replies and Mentions
-- Description: Add new notification types and fix triggers
-- Date: 2025-12-18

-- ============================================================================
-- PART 1: Update notification type constraint
-- ============================================================================

-- Drop old constraint
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

-- Add new constraint with additional types
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
CHECK (type IN (
    'friend_request',
    'friend_accepted',
    'post_like',
    'post_comment',
    'comment_reply',
    'comment_mention'
));

-- ============================================================================
-- PART 2: Update triggers to use target_id instead of comment_id
-- ============================================================================

-- Update mention notification trigger
CREATE OR REPLACE FUNCTION notify_mentioned_users()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO notifications (user_id, type, actor_id, target_id, created_at)
  SELECT
    cm.mentioned_user_id,
    'comment_mention',
    (SELECT user_id FROM post_comments WHERE id = cm.comment_id),
    (SELECT post_id FROM post_comments WHERE id = cm.comment_id), -- Use post_id as target
    NOW()
  FROM comment_mentions cm
  WHERE cm.id = NEW.id
  AND cm.mentioned_user_id != (SELECT user_id FROM post_comments WHERE id = cm.comment_id);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Update reply notification trigger
CREATE OR REPLACE FUNCTION notify_comment_reply()
RETURNS TRIGGER AS $$
BEGIN
  -- Only create notification if replying to someone else's comment
  IF NEW.parent_comment_id IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, actor_id, target_id, created_at)
    SELECT
      pc.user_id,
      'comment_reply',
      NEW.user_id,
      NEW.post_id, -- Use post_id as target
      NOW()
    FROM post_comments pc
    WHERE pc.id = NEW.parent_comment_id
    AND pc.user_id != NEW.user_id; -- Don't notify if replying to yourself
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- Verify constraint was updated
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.constraint_column_usage
    WHERE constraint_name = 'notifications_type_check'
  ) THEN
    RAISE EXCEPTION 'notifications_type_check constraint not found';
  END IF;
END $$;

-- Success message
DO $$
BEGIN
  RAISE NOTICE 'Migration completed successfully!';
  RAISE NOTICE 'Updated: notification types constraint and triggers to use target_id';
END $$;
