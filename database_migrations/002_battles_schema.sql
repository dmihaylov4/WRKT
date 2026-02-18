-- =====================================================
-- BATTLES SCHEMA
-- Run this in Supabase SQL Editor AFTER 001_challenges_schema.sql
-- =====================================================

-- =====================================================
-- TABLE: battles
-- =====================================================

CREATE TABLE battles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- Participants
  challenger_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  opponent_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

  -- Battle configuration
  battle_type VARCHAR(50) NOT NULL, -- 'volume', 'consistency', 'workout_count', 'pr', 'exercise'
  target_metric VARCHAR(100),       -- Specific metric (e.g., 'bench_press' for exercise battles)

  -- Timing
  start_date TIMESTAMP NOT NULL,
  end_date TIMESTAMP NOT NULL,

  -- Status & Results
  status VARCHAR(20) DEFAULT 'pending', -- 'pending', 'active', 'completed', 'declined', 'cancelled'
  winner_id UUID REFERENCES profiles(id),

  -- Live scores (denormalized for performance)
  challenger_score DECIMAL DEFAULT 0,
  opponent_score DECIMAL DEFAULT 0,

  -- Metadata
  custom_rules TEXT,                -- JSON for custom battle parameters
  trash_talk_enabled BOOLEAN DEFAULT true,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  -- Constraints
  CONSTRAINT different_participants CHECK (challenger_id != opponent_id),
  CONSTRAINT valid_dates CHECK (end_date > start_date),
  CONSTRAINT valid_winner CHECK (winner_id IN (challenger_id, opponent_id) OR winner_id IS NULL),
  CONSTRAINT valid_battle_type CHECK (battle_type IN ('volume', 'consistency', 'workout_count', 'pr', 'exercise')),
  CONSTRAINT valid_status CHECK (status IN ('pending', 'active', 'completed', 'declined', 'cancelled'))
);

-- =====================================================
-- TABLE: battle_score_snapshots
-- =====================================================

CREATE TABLE battle_score_snapshots (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  battle_id UUID NOT NULL REFERENCES battles(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  score DECIMAL NOT NULL,
  snapshot_date TIMESTAMP DEFAULT NOW()
);

-- =====================================================
-- TABLE: battle_activities
-- =====================================================

CREATE TABLE battle_activities (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  battle_id UUID NOT NULL REFERENCES battles(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

  activity_type VARCHAR(50) NOT NULL, -- 'workout_logged', 'took_lead', 'milestone', 'accepted', 'completed'
  activity_data JSONB,                -- Workout details, score change, etc.

  created_at TIMESTAMP DEFAULT NOW(),

  CONSTRAINT valid_battle_activity_type CHECK (activity_type IN ('workout_logged', 'took_lead', 'milestone', 'accepted', 'completed'))
);

-- =====================================================
-- INDEXES
-- =====================================================

-- Battles
CREATE INDEX idx_battles_challenger ON battles(challenger_id, status);
CREATE INDEX idx_battles_opponent ON battles(opponent_id, status);
CREATE INDEX idx_battles_active ON battles(status, end_date);
CREATE INDEX idx_battles_dates ON battles(start_date, end_date);
CREATE INDEX idx_battles_participants ON battles(challenger_id, opponent_id);
CREATE INDEX idx_battles_end_date ON battles(end_date);

-- Battle score snapshots
CREATE INDEX idx_battle_snapshots_battle ON battle_score_snapshots(battle_id, snapshot_date DESC);
CREATE INDEX idx_battle_snapshots_user ON battle_score_snapshots(user_id, snapshot_date DESC);

-- Battle activities
CREATE INDEX idx_battle_activities_battle ON battle_activities(battle_id, created_at DESC);
CREATE INDEX idx_battle_activities_user ON battle_activities(user_id, created_at DESC);

-- =====================================================
-- ROW LEVEL SECURITY
-- =====================================================

ALTER TABLE battles ENABLE ROW LEVEL SECURITY;
ALTER TABLE battle_score_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE battle_activities ENABLE ROW LEVEL SECURITY;

-- Battles policies
CREATE POLICY "Users can view their battles" ON battles
  FOR SELECT USING (
    challenger_id = auth.uid() OR opponent_id = auth.uid()
  );

CREATE POLICY "Users can create battles" ON battles
  FOR INSERT WITH CHECK (challenger_id = auth.uid());

CREATE POLICY "Participants can update battle" ON battles
  FOR UPDATE USING (
    challenger_id = auth.uid() OR opponent_id = auth.uid()
  );

CREATE POLICY "Participants can delete battle" ON battles
  FOR DELETE USING (
    challenger_id = auth.uid() OR opponent_id = auth.uid()
  );

-- Battle score snapshots policies
CREATE POLICY "Users can view battle snapshots" ON battle_score_snapshots
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM battles
      WHERE battles.id = battle_score_snapshots.battle_id
      AND (battles.challenger_id = auth.uid() OR battles.opponent_id = auth.uid())
    )
  );

CREATE POLICY "System can create snapshots" ON battle_score_snapshots
  FOR INSERT WITH CHECK (true); -- Snapshots created by triggers

-- Battle activities policies
CREATE POLICY "Users can view battle activities" ON battle_activities
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM battles
      WHERE battles.id = battle_activities.battle_id
      AND (battles.challenger_id = auth.uid() OR battles.opponent_id = auth.uid())
    )
  );

CREATE POLICY "Users can create activities" ON battle_activities
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- =====================================================
-- TRIGGERS & FUNCTIONS
-- =====================================================

-- Function: Create score snapshots on score change
CREATE OR REPLACE FUNCTION create_battle_score_snapshot()
RETURNS TRIGGER AS $$
BEGIN
  -- Take snapshot when challenger score changes
  IF OLD.challenger_score != NEW.challenger_score THEN
    INSERT INTO battle_score_snapshots (battle_id, user_id, score)
    VALUES (NEW.id, NEW.challenger_id, NEW.challenger_score);
  END IF;

  -- Take snapshot when opponent score changes
  IF OLD.opponent_score != NEW.opponent_score THEN
    INSERT INTO battle_score_snapshots (battle_id, user_id, score)
    VALUES (NEW.id, NEW.opponent_id, NEW.opponent_score);
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER battle_score_snapshot_trigger
  AFTER UPDATE OF challenger_score, opponent_score ON battles
  FOR EACH ROW
  EXECUTE FUNCTION create_battle_score_snapshot();

-- Function: Determine winner when battle completes
CREATE OR REPLACE FUNCTION determine_battle_winner()
RETURNS TRIGGER AS $$
BEGIN
  -- Only run when battle becomes completed
  IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
    IF NEW.challenger_score > NEW.opponent_score THEN
      NEW.winner_id := NEW.challenger_id;
    ELSIF NEW.opponent_score > NEW.challenger_score THEN
      NEW.winner_id := NEW.opponent_id;
    ELSE
      NEW.winner_id := NULL; -- Tie
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER battle_winner_trigger
  BEFORE UPDATE OF status ON battles
  FOR EACH ROW
  EXECUTE FUNCTION determine_battle_winner();

-- Function: Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_battles_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER battles_updated_at_trigger
  BEFORE UPDATE ON battles
  FOR EACH ROW
  EXECUTE FUNCTION update_battles_updated_at();

-- Function: Auto-complete battles when end_date passes
-- Note: This should be run as a scheduled job (Supabase Edge Functions)
-- For now, we'll handle it in the app layer
CREATE OR REPLACE FUNCTION auto_complete_expired_battles()
RETURNS void AS $$
BEGIN
  UPDATE battles
  SET status = 'completed'
  WHERE status = 'active'
  AND end_date < NOW();
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- UTILITY VIEWS
-- =====================================================

-- View: Active battles for easy querying
CREATE OR REPLACE VIEW active_battles AS
SELECT
  b.*,
  c.username as challenger_username,
  o.username as opponent_username,
  EXTRACT(EPOCH FROM (b.end_date - CURRENT_TIMESTAMP)) / 3600 as hours_remaining
FROM battles b
JOIN profiles c ON b.challenger_id = c.id
JOIN profiles o ON b.opponent_id = o.id
WHERE b.status = 'active'
AND b.end_date > CURRENT_TIMESTAMP
ORDER BY b.end_date ASC;

-- =====================================================
-- SUCCESS MESSAGE
-- =====================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Battles schema created successfully!';
  RAISE NOTICE 'Tables: battles, battle_score_snapshots, battle_activities';
  RAISE NOTICE 'View: active_battles';
  RAISE NOTICE 'Next: Create Swift models';
END $$;
