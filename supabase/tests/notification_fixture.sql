CREATE OR REPLACE FUNCTION public.create_friend_accepted_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    IF OLD.status = 'pending' AND NEW.status = 'accepted' THEN
        INSERT INTO notifications (user_id, type, actor_id, target_id)
        VALUES (NEW.user_id, 'friend_accepted', NEW.friend_id, NEW.id);
    END IF;
    RETURN NEW;
END;
$function$;
CREATE TRIGGER friend_accepted_notification_trigger AFTER UPDATE ON public.friendships FOR EACH ROW EXECUTE FUNCTION create_friend_accepted_notification();

CREATE OR REPLACE FUNCTION public.create_friend_request_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    IF NEW.status = 'pending' THEN
        INSERT INTO notifications (user_id, type, actor_id, target_id)
        VALUES (NEW.friend_id, 'friend_request', NEW.user_id, NEW.id);
    END IF;
    RETURN NEW;
END;
$function$;
CREATE TRIGGER friend_request_notification_trigger AFTER INSERT ON public.friendships FOR EACH ROW EXECUTE FUNCTION create_friend_request_notification();

CREATE OR REPLACE FUNCTION public.create_post_like_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    post_author_id uuid;
begin
    select user_id into post_author_id
    from public.workout_posts
    where id = new.post_id;

    if post_author_id is null or post_author_id = new.user_id then
        return new;
    end if;

    insert into public.notifications (user_id, type, actor_id, target_id, read)
    values (post_author_id, 'post_like', new.user_id, new.post_id, false)
    on conflict (user_id, type, actor_id, target_id)
    where type = 'post_like'
    do nothing;

    return new;
end;
$function$;
CREATE TRIGGER on_post_liked AFTER INSERT ON public.post_likes FOR EACH ROW EXECUTE FUNCTION create_post_like_notification();

CREATE OR REPLACE FUNCTION public.notify_post_commented()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    post_owner_id UUID;
BEGIN
    -- Skip replies - the existing notify_comment_reply trigger handles those
    IF NEW.parent_comment_id IS NOT NULL THEN
        RETURN NEW;
    END IF;

    SELECT user_id INTO post_owner_id
    FROM workout_posts
    WHERE id = NEW.post_id;

    -- Don't notify when commenting on your own post
    IF post_owner_id IS NOT NULL AND post_owner_id != NEW.user_id THEN
        INSERT INTO notifications (user_id, type, actor_id, target_id, read, created_at)
        VALUES (
            post_owner_id,
            'post_comment',
            NEW.user_id,
            NEW.post_id,
            false,
            NOW()
        );
    END IF;

    RETURN NEW;
END;
$function$;
CREATE TRIGGER notify_post_commented_trigger AFTER INSERT ON public.post_comments FOR EACH ROW EXECUTE FUNCTION notify_post_commented();

CREATE OR REPLACE FUNCTION public.notify_comment_reply()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
$function$;
CREATE TRIGGER trigger_notify_reply AFTER INSERT ON public.post_comments FOR EACH ROW EXECUTE FUNCTION notify_comment_reply();

CREATE OR REPLACE FUNCTION public.notify_mentioned_users()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
$function$;

CREATE TRIGGER trigger_notify_mentions AFTER INSERT ON public.comment_mentions FOR EACH ROW EXECUTE FUNCTION public.notify_mentioned_users();

CREATE OR REPLACE FUNCTION public.notify_challenge_leaderboard_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
  declare
      challenge_record record;
  begin
      if tg_op = 'update' and old.current_progress != new.current_progress then
          select * into challenge_record from challenges where id = new.challenge_id;

          if new.progress_percentage >= 100 and old.progress_percentage < 100 then
              insert into notifications (user_id, type, actor_id, target_id, read, metadata)
              values (
                  new.user_id, 'challenge_leaderboard_change', new.user_id, challenge_record.id, false,
                  jsonb_build_object(
                      'challenge_title', challenge_record.title,
                      'progress', new.current_progress::text
                  )
              );
          end if;
      end if;
      return new;
  end;
  $function$;

CREATE OR REPLACE FUNCTION public.notify_challenge_milestone()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
  declare
      challenge_record record;
      progress_percent numeric;
      milestone int;
  begin
      if tg_op = 'update' and old.current_progress != new.current_progress then
          select * into challenge_record from challenges where id = new.challenge_id;

          if challenge_record.goal_value > 0 then
              progress_percent := (new.current_progress / challenge_record.goal_value) * 100;

              if progress_percent >= 100 and old.current_progress / challenge_record.goal_value * 100 < 100 then
                  milestone := 100;
              elsif progress_percent >= 75 and old.current_progress / challenge_record.goal_value * 100 < 75 then
                  milestone := 75;
              elsif progress_percent >= 50 and old.current_progress / challenge_record.goal_value * 100 < 50 then
                  milestone := 50;
              elsif progress_percent >= 25 and old.current_progress / challenge_record.goal_value * 100 < 25 then
                  milestone := 25;
              else
                  return new;
              end if;

              insert into notifications (user_id, type, actor_id, target_id, read, metadata)
              values (
                  new.user_id, 'challenge_milestone', new.user_id, challenge_record.id, false,
                  jsonb_build_object(
                      'milestone', milestone::text,
                      'challenge_title', challenge_record.title,
                      'progress', new.current_progress::text,
                      'goal', challenge_record.goal_value::text
                  )
              );
          end if;
      end if;
      return new;
  end;
  $function$;
CREATE TRIGGER challenge_milestone AFTER UPDATE ON public.challenge_participants FOR EACH ROW EXECUTE FUNCTION public.notify_challenge_milestone();
CREATE TRIGGER challenge_leaderboard AFTER UPDATE ON public.challenge_participants FOR EACH ROW EXECUTE FUNCTION public.notify_challenge_leaderboard_change();
