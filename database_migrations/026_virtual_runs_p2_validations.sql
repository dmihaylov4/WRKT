-- Migration 026: P2 Virtual Run validations
-- Snapshot plausibility checks + invite rate limiting

-- ============================================================
-- 3A: Snapshot Plausibility Checks
-- ============================================================

-- Replace the existing rate-limit trigger with an expanded version
-- that also validates pace, heart rate, and speed plausibility.
CREATE OR REPLACE FUNCTION check_snapshot_plausibility()
RETURNS TRIGGER AS $$
DECLARE
    _last_received timestamptz;
    _last_distance double precision;
    _time_delta double precision;
    _dist_delta double precision;
    _speed_kmh double precision;
BEGIN
    -- Pace check: reject if faster than 2:00/km (world record ~2:50/km)
    IF NEW.current_pace_sec_per_km IS NOT NULL AND NEW.current_pace_sec_per_km < 120 THEN
        RAISE EXCEPTION 'Implausible pace: % sec/km is faster than 2:00/km', NEW.current_pace_sec_per_km;
    END IF;

    -- Heart rate check: reject if above physiological limit
    IF NEW.heart_rate IS NOT NULL AND NEW.heart_rate > 250 THEN
        RAISE EXCEPTION 'Implausible heart rate: % bpm exceeds 250', NEW.heart_rate;
    END IF;

    -- Speed plausibility on UPDATE: check distance delta vs time delta
    IF TG_OP = 'UPDATE' THEN
        _last_received := OLD.server_received_at;
        _last_distance := OLD.distance_m;

        IF _last_received IS NOT NULL AND _last_distance IS NOT NULL THEN
            _time_delta := EXTRACT(EPOCH FROM (now() - _last_received));
            _dist_delta := NEW.distance_m - _last_distance;

            IF _time_delta > 0 AND _dist_delta > 0 THEN
                _speed_kmh := (_dist_delta / _time_delta) * 3.6;
                IF _speed_kmh > 60 THEN
                    RAISE EXCEPTION 'Implausible speed: % km/h exceeds 60 km/h limit', round(_speed_kmh::numeric, 1);
                END IF;
            END IF;
        END IF;
    END IF;

    NEW.server_received_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop the old trigger if it exists, then create for both INSERT and UPDATE
DROP TRIGGER IF EXISTS trg_check_snapshot_rate_limit ON virtual_run_snapshots;
DROP TRIGGER IF EXISTS trg_check_snapshot_plausibility ON virtual_run_snapshots;

CREATE TRIGGER trg_check_snapshot_plausibility
    BEFORE INSERT OR UPDATE ON virtual_run_snapshots
    FOR EACH ROW
    EXECUTE FUNCTION check_snapshot_plausibility();

-- ============================================================
-- 3B: Invite Rate Limiting (max 5 pending invites per user)
-- ============================================================

CREATE OR REPLACE FUNCTION check_invite_rate_limit()
RETURNS TRIGGER AS $$
DECLARE
    _pending_count integer;
BEGIN
    SELECT COUNT(*) INTO _pending_count
    FROM virtual_runs
    WHERE inviter_id = NEW.inviter_id
      AND status = 'pending';

    IF _pending_count >= 5 THEN
        RAISE EXCEPTION 'Too many pending invites (%). Maximum 5 allowed.', _pending_count;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_invite_rate_limit ON virtual_runs;

CREATE TRIGGER trg_check_invite_rate_limit
    BEFORE INSERT ON virtual_runs
    FOR EACH ROW
    EXECUTE FUNCTION check_invite_rate_limit();

-- Partial index for efficient pending-invite lookups
CREATE INDEX IF NOT EXISTS idx_virtual_runs_inviter_pending
    ON virtual_runs(inviter_id, status) WHERE status = 'pending';
