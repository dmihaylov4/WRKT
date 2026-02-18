-- =====================================================
-- CHALLENGES SCHEMA
-- Run this in Supabase SQL Editor
-- =====================================================

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =====================================================
-- TABLE: challenges
-- =====================================================

CREATE TABLE challenges (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title VARCHAR(200) NOT NULL,
  description TEXT,

  -- Challenge type & goal
  challenge_type VARCHAR(50) NOT NULL, -- 'workout_count', 'total_volume', 'specific_exercise', 'streak', 'custom'
  goal_metric VARCHAR(100) NOT NULL,   -- 'workouts', 'total_sets', 'pull_ups', 'days'
  goal_value DECIMAL NOT NULL,         -- Target number (e.g., 30 workouts, 100 pull-ups)

  -- Timing
  start_date TIMESTAMP NOT NULL,
  end_date TIMESTAMP NOT NULL,

  -- Metadata
  creator_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  is_public BOOLEAN DEFAULT false,
  is_preset BOOLEAN DEFAULT false,     -- Official WRKT challenges
  difficulty VARCHAR(20),               -- 'beginner', 'intermediate', 'advanced'
  participant_limit INT,

  -- Engagement metrics
  participant_count INT DEFAULT 0,
  completion_count INT DEFAULT 0,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  -- Constraints
  CONSTRAINT valid_challenge_type CHECK (challenge_type IN ('workout_count', 'total_volume', 'specific_exercise', 'streak', 'custom')),
  CONSTRAINT valid_difficulty CHECK (difficulty IS NULL OR difficulty IN ('beginner', 'intermediate', 'advanced')),
  CONSTRAINT valid_dates CHECK (end_date > start_date),
  CONSTRAINT positive_goal CHECK (goal_value > 0)
);

-- =====================================================
-- TABLE: challenge_participants
-- =====================================================

CREATE TABLE challenge_participants (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  challenge_id UUID REFERENCES challenges(id) ON DELETE CASCADE,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,

  -- Progress tracking
  current_progress DECIMAL DEFAULT 0,  -- Current count toward goal
  progress_percentage INT DEFAULT 0,   -- Cached percentage
  completed BOOLEAN DEFAULT false,
  completion_date TIMESTAMP,

  -- Engagement
  last_activity_date TIMESTAMP,

  joined_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(challenge_id, user_id)
);

-- =====================================================
-- TABLE: challenge_activities
-- =====================================================

CREATE TABLE challenge_activities (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  challenge_id UUID REFERENCES challenges(id) ON DELETE CASCADE,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  activity_type VARCHAR(50) NOT NULL,  -- 'joined', 'progress', 'milestone', 'completed'
  activity_data JSONB,                 -- Flexible data (e.g., workout details)
  created_at TIMESTAMP DEFAULT NOW(),

  CONSTRAINT valid_activity_type CHECK (activity_type IN ('joined', 'progress', 'milestone', 'completed'))
);

-- =====================================================
-- INDEXES
-- =====================================================

-- Challenges
CREATE INDEX idx_challenges_public ON challenges(is_public, end_date) WHERE is_public = true;
CREATE INDEX idx_challenges_active ON challenges(start_date, end_date);
CREATE INDEX idx_challenges_creator ON challenges(creator_id);
CREATE INDEX idx_challenges_end_date ON challenges(end_date);

-- Challenge participants
CREATE INDEX idx_challenge_participants_user ON challenge_participants(user_id, completed);
CREATE INDEX idx_challenge_participants_challenge ON challenge_participants(challenge_id, progress_percentage DESC);
CREATE INDEX idx_challenge_participants_active ON challenge_participants(user_id) WHERE completed = false;

-- Challenge activities
CREATE INDEX idx_challenge_activities_challenge ON challenge_activities(challenge_id, created_at DESC);
CREATE INDEX idx_challenge_activities_user ON challenge_activities(user_id, created_at DESC);

-- =====================================================
-- ROW LEVEL SECURITY
-- =====================================================

ALTER TABLE challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE challenge_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE challenge_activities ENABLE ROW LEVEL SECURITY;

-- Challenges policies
CREATE POLICY "Public challenges visible to all" ON challenges
  FOR SELECT USING (
    is_public = true
    OR creator_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM challenge_participants
      WHERE challenge_participants.challenge_id = challenges.id
      AND challenge_participants.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can create challenges" ON challenges
  FOR INSERT WITH CHECK (creator_id = auth.uid());

CREATE POLICY "Creators can update their challenges" ON challenges
  FOR UPDATE USING (creator_id = auth.uid());

CREATE POLICY "Creators can delete their challenges" ON challenges
  FOR DELETE USING (creator_id = auth.uid());

-- Challenge participants policies
CREATE POLICY "Users can view challenge participants" ON challenge_participants
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM challenges
      WHERE challenges.id = challenge_participants.challenge_id
      AND (challenges.is_public = true OR challenges.creator_id = auth.uid())
    )
    OR user_id = auth.uid()
  );

CREATE POLICY "Users can join challenges" ON challenge_participants
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update their own participation" ON challenge_participants
  FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "Users can leave challenges" ON challenge_participants
  FOR DELETE USING (user_id = auth.uid());

-- Challenge activities policies
CREATE POLICY "Users can view challenge activities" ON challenge_activities
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM challenges
      WHERE challenges.id = challenge_activities.challenge_id
      AND (challenges.is_public = true OR challenges.creator_id = auth.uid())
    )
    OR EXISTS (
      SELECT 1 FROM challenge_participants
      WHERE challenge_participants.challenge_id = challenge_activities.challenge_id
      AND challenge_participants.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can create activities" ON challenge_activities
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- =====================================================
-- TRIGGERS & FUNCTIONS
-- =====================================================

-- Function: Update progress percentage
CREATE OR REPLACE FUNCTION update_challenge_progress_percentage()
RETURNS TRIGGER AS $$
DECLARE
  target_goal DECIMAL;
BEGIN
  -- Get the goal value from challenges table
  SELECT goal_value INTO target_goal
  FROM challenges
  WHERE id = NEW.challenge_id;

  -- Calculate percentage
  NEW.progress_percentage := LEAST(100, ROUND((NEW.current_progress / target_goal) * 100));

  -- Check if completed
  IF NEW.current_progress >= target_goal AND NOT NEW.completed THEN
    NEW.completed := true;
    NEW.completion_date := NOW();

    -- Update challenge completion count
    UPDATE challenges
    SET completion_count = completion_count + 1
    WHERE id = NEW.challenge_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER challenge_progress_update
  BEFORE UPDATE OF current_progress ON challenge_participants
  FOR EACH ROW
  EXECUTE FUNCTION update_challenge_progress_percentage();

-- Function: Update participant count
CREATE OR REPLACE FUNCTION update_challenge_participant_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE challenges
    SET participant_count = participant_count + 1
    WHERE id = NEW.challenge_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE challenges
    SET participant_count = participant_count - 1
    WHERE id = OLD.challenge_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER challenge_participant_count_update
  AFTER INSERT OR DELETE ON challenge_participants
  FOR EACH ROW
  EXECUTE FUNCTION update_challenge_participant_count();

-- Function: Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_challenges_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER challenges_updated_at_trigger
  BEFORE UPDATE ON challenges
  FOR EACH ROW
  EXECUTE FUNCTION update_challenges_updated_at();

-- =====================================================
-- SUCCESS MESSAGE
-- =====================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Challenges schema created successfully!';
  RAISE NOTICE 'Tables: challenges, challenge_participants, challenge_activities';
  RAISE NOTICE 'Next: Run 002_battles_schema.sql';
END $$;
