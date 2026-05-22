-- Battle Result Screen
-- Adds one-global-share-per-battle fields, battle feed post stats,
-- and a completion notification RPC called by the iOS client.

ALTER TABLE public.workout_posts
    ADD COLUMN IF NOT EXISTS battle_stats JSONB;

ALTER TABLE public.battles
    ADD COLUMN IF NOT EXISTS shared_post_id UUID REFERENCES public.workout_posts(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS shared_by_user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS battles_shared_post_id_idx
    ON public.battles(shared_post_id)
    WHERE shared_post_id IS NOT NULL;

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
        'battle_id', v_battle.id,
        'battle_type', v_battle.battle_type,
        'winner_id', v_battle.winner_id,
        'challenger_score', v_battle.challenger_score,
        'opponent_score', v_battle.opponent_score
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
