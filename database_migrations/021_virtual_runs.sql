-- Virtual Runs: Allow two users to run together remotely
-- with live stats syncing via Supabase Realtime

-- =============================================================
-- Table: virtual_runs
-- =============================================================
CREATE TABLE virtual_runs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    inviter_id UUID REFERENCES profiles(id) NOT NULL,
    invitee_id UUID REFERENCES profiles(id) NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending', -- pending, active, completed, cancelled
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),

    -- Summary stats (populated on completion)
    inviter_distance_m DOUBLE PRECISION,
    inviter_duration_s INTEGER,
    inviter_avg_pace_sec_per_km INTEGER,
    inviter_avg_heart_rate INTEGER,
    invitee_distance_m DOUBLE PRECISION,
    invitee_duration_s INTEGER,
    invitee_avg_pace_sec_per_km INTEGER,
    invitee_avg_heart_rate INTEGER,

    -- Winner tracking
    winner_id UUID REFERENCES profiles(id)
);

CREATE INDEX idx_virtual_runs_status ON virtual_runs(status) WHERE status = 'active';
CREATE INDEX idx_virtual_runs_users ON virtual_runs(inviter_id, invitee_id);

-- =============================================================
-- Table: virtual_run_snapshots
-- =============================================================
CREATE TABLE virtual_run_snapshots (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    virtual_run_id UUID REFERENCES virtual_runs(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) NOT NULL,

    -- Stats
    distance_m DOUBLE PRECISION NOT NULL DEFAULT 0,
    duration_s INTEGER NOT NULL DEFAULT 0,
    current_pace_sec_per_km INTEGER,
    heart_rate INTEGER,
    calories INTEGER,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,

    -- Ordering & conflict resolution
    seq INTEGER NOT NULL DEFAULT 0,
    client_recorded_at TIMESTAMPTZ NOT NULL,
    server_received_at TIMESTAMPTZ DEFAULT NOW(),

    -- Only keep latest snapshot per user per run (for UPSERT)
    CONSTRAINT unique_run_user UNIQUE (virtual_run_id, user_id)
);

CREATE INDEX idx_snapshots_run_user ON virtual_run_snapshots(virtual_run_id, user_id);

-- =============================================================
-- Rate Limiting: max 1 snapshot per second per user
-- =============================================================
CREATE OR REPLACE FUNCTION check_snapshot_rate_limit()
RETURNS TRIGGER AS $$
DECLARE
    last_snapshot_time TIMESTAMPTZ;
BEGIN
    SELECT server_received_at INTO last_snapshot_time
    FROM virtual_run_snapshots
    WHERE virtual_run_id = NEW.virtual_run_id AND user_id = NEW.user_id;

    IF last_snapshot_time IS NOT NULL AND
       NEW.server_received_at - last_snapshot_time < INTERVAL '1 second' THEN
        RAISE EXCEPTION 'Rate limit exceeded: max 1 snapshot per second';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER enforce_snapshot_rate_limit
    BEFORE INSERT OR UPDATE ON virtual_run_snapshots
    FOR EACH ROW EXECUTE FUNCTION check_snapshot_rate_limit();

-- =============================================================
-- RLS Policies
-- =============================================================

-- virtual_runs
ALTER TABLE virtual_runs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own runs"
    ON virtual_runs FOR SELECT
    USING (auth.uid() = inviter_id OR auth.uid() = invitee_id);

CREATE POLICY "Users can create runs they invite"
    ON virtual_runs FOR INSERT
    WITH CHECK (auth.uid() = inviter_id);

CREATE POLICY "Users can update their own runs"
    ON virtual_runs FOR UPDATE
    USING (auth.uid() = inviter_id OR auth.uid() = invitee_id);

-- virtual_run_snapshots
ALTER TABLE virtual_run_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Run participants can view snapshots"
    ON virtual_run_snapshots FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM virtual_runs
            WHERE id = virtual_run_id
            AND (inviter_id = auth.uid() OR invitee_id = auth.uid())
        )
    );

CREATE POLICY "Users can only write own snapshots"
    ON virtual_run_snapshots FOR INSERT
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can only update own snapshots"
    ON virtual_run_snapshots FOR UPDATE
    USING (user_id = auth.uid());

-- =============================================================
-- Enable Realtime for live sync
-- =============================================================
ALTER PUBLICATION supabase_realtime ADD TABLE virtual_run_snapshots;

-- Set replica identity to FULL so old record is available on UPDATE events
ALTER TABLE virtual_run_snapshots REPLICA IDENTITY FULL;
