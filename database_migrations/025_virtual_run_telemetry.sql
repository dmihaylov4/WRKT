-- P1-C: Virtual run production telemetry
-- Event logging table for observability and debugging

CREATE TABLE IF NOT EXISTS virtual_run_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id UUID REFERENCES virtual_runs(id),
    user_id UUID REFERENCES profiles(id),
    event_type TEXT NOT NULL,
    data JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for efficient querying
CREATE INDEX idx_vr_events_run ON virtual_run_events(run_id);
CREATE INDEX idx_vr_events_type ON virtual_run_events(event_type);
CREATE INDEX idx_vr_events_created ON virtual_run_events(created_at);

-- RLS: users can insert their own events
ALTER TABLE virtual_run_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert their own events"
    ON virtual_run_events
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can read events for their runs"
    ON virtual_run_events
    FOR SELECT
    USING (
        run_id IN (
            SELECT id FROM virtual_runs
            WHERE inviter_id = auth.uid() OR invitee_id = auth.uid()
        )
    );
