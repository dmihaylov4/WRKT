-- Fix battle_completed notification metadata: numeric scores were stored as JSON
-- numbers but the iOS client decodes metadata as [String: String], causing a
-- DecodingError.typeMismatch that aborts the entire notifications fetch.
--
-- Step 1: patch existing rows by rebuilding the JSONB object using ->> (text extract),
--         which coerces any numeric/uuid value to a JSON string.
UPDATE public.notifications
SET metadata = (
    SELECT jsonb_object_agg(key, value)
    FROM jsonb_each_text(metadata)
)
WHERE type = 'battle_completed'
  AND metadata IS NOT NULL;

-- Step 2: replace the function so future notifications store all values as strings.
CREATE OR REPLACE FUNCTION public.send_battle_completed_notifications(p_battle_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_battle public.battles%ROWTYPE;
    v_metadata JSONB;
BEGIN
    SELECT *
    INTO v_battle
    FROM public.battles
    WHERE id = p_battle_id;

    IF NOT FOUND OR v_battle.status <> 'completed' THEN
        RETURN;
    END IF;

    v_metadata := jsonb_build_object(
        'battle_id',        v_battle.id::text,
        'battle_type',      v_battle.battle_type,
        'winner_id',        v_battle.winner_id::text,
        'challenger_score', v_battle.challenger_score::text,
        'opponent_score',   v_battle.opponent_score::text
    );

    INSERT INTO public.notifications (user_id, type, actor_id, target_id, read, metadata)
    SELECT
        v_battle.challenger_id,
        'battle_completed',
        v_battle.opponent_id,
        v_battle.id,
        false,
        v_metadata
    WHERE NOT EXISTS (
        SELECT 1
        FROM public.notifications
        WHERE user_id = v_battle.challenger_id
          AND type = 'battle_completed'
          AND target_id = v_battle.id
    );

    INSERT INTO public.notifications (user_id, type, actor_id, target_id, read, metadata)
    SELECT
        v_battle.opponent_id,
        'battle_completed',
        v_battle.challenger_id,
        v_battle.id,
        false,
        v_metadata
    WHERE NOT EXISTS (
        SELECT 1
        FROM public.notifications
        WHERE user_id = v_battle.opponent_id
          AND type = 'battle_completed'
          AND target_id = v_battle.id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_battle_completed_notifications(UUID) TO authenticated, service_role;
