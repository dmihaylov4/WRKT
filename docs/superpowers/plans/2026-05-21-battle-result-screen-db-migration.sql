-- Battle Result Screen: DB Migration
-- Run in Supabase SQL editor. All changes are additive - safe for existing rows.

-- 1. Add share-lock columns to battles
ALTER TABLE battles
  ADD COLUMN IF NOT EXISTS shared_post_id UUID REFERENCES posts(id) NULL,
  ADD COLUMN IF NOT EXISTS shared_by_user_id UUID REFERENCES profiles(id) NULL;

-- 2. Add battle_stats JSONB to posts (null for all existing posts)
ALTER TABLE posts
  ADD COLUMN IF NOT EXISTS battle_stats JSONB NULL;

-- 3. Add 'battle' to post_type enum (if post_type is stored as a PG enum).
--    Skip this step if post_type is a VARCHAR - no migration needed.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumlabel = 'battle'
      AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'post_type')
  ) THEN
    ALTER TYPE post_type ADD VALUE 'battle';
  END IF;
END $$;

-- 4. Create battle completion notification function.
--    Replace the body below with the pattern from send_battle_ending_soon_notifications.
CREATE OR REPLACE FUNCTION send_battle_completed_notifications(p_battle_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_battle battles%ROWTYPE;
  v_challenger_token TEXT;
  v_opponent_token TEXT;
  v_winner_name TEXT;
BEGIN
  SELECT * INTO v_battle FROM battles WHERE id = p_battle_id;
  IF NOT FOUND THEN RETURN; END IF;

  -- Avoid double-sending: only notify if status = 'completed'
  IF v_battle.status != 'completed' THEN RETURN; END IF;

  -- Fetch winner display name (falls back to username)
  SELECT COALESCE(display_name, username) INTO v_winner_name
  FROM profiles
  WHERE id = v_battle.winner_id;

  -- Send push to challenger
  -- (Use the same push mechanism as send_battle_ending_soon_notifications)
  PERFORM send_push_notification(
    p_user_id := v_battle.challenger_id,
    p_title := 'Battle Complete',
    p_body := COALESCE(v_winner_name, 'Someone') || ' won the ' ||
              v_battle.battle_type || ' battle!'
  );

  -- Send push to opponent
  PERFORM send_push_notification(
    p_user_id := v_battle.opponent_id,
    p_title := 'Battle Complete',
    p_body := COALESCE(v_winner_name, 'Someone') || ' won the ' ||
              v_battle.battle_type || ' battle!'
  );
END;
$$;
