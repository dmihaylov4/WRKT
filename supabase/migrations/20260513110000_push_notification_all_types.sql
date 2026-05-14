-- Add push notification copy for all notification types.
-- Previously every type not in the original 8 fell through to the generic
-- "You have a new notification" fallback. This migration covers all types
-- defined in NotificationType (Swift enum) plus battle_cancelled which is
-- inserted by a database trigger when the inviter cancels a pending battle.

create or replace function public.send_push_notification()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
    actor_name        text;
    notification_title text;
    notification_body  text;
    push_url          text;
    service_key       text;
begin
    select value into push_url   from private.push_config where key = 'push_function_url';
    select value into service_key from private.push_config where key = 'service_role_key';

    if push_url is null or service_key is null then
        raise warning 'Push notification skipped: private.push_config missing push_function_url or service_role_key';
        return new;
    end if;

    select coalesce(display_name, username, 'Someone') into actor_name
    from public.profiles
    where id = new.actor_id;

    case new.type
        -- Social
        when 'friend_request' then
            notification_title := 'New Friend Request';
            notification_body  := actor_name || ' sent you a friend request';
        when 'friend_accepted' then
            notification_title := 'Friend Request Accepted';
            notification_body  := actor_name || ' accepted your friend request';
        when 'post_like' then
            notification_title := 'New Like';
            notification_body  := actor_name || ' liked your workout';
        when 'post_comment' then
            notification_title := 'New Comment';
            notification_body  := actor_name || ' commented on your workout';
        when 'comment_reply' then
            notification_title := 'New Reply';
            notification_body  := actor_name || ' replied to your comment';
        when 'comment_mention' then
            notification_title := 'You were mentioned';
            notification_body  := actor_name || ' mentioned you in a comment';

        -- Battle
        when 'battle_invite' then
            notification_title := 'Battle Challenge!';
            notification_body  := actor_name || ' challenged you to a battle';
        when 'battle_accepted' then
            notification_title := 'Battle On!';
            notification_body  := actor_name || ' accepted your battle challenge';
        when 'battle_declined' then
            notification_title := 'Battle Declined';
            notification_body  := actor_name || ' declined your battle challenge';
        when 'battle_cancelled' then
            notification_title := 'Battle Cancelled';
            notification_body  := actor_name || ' cancelled the battle challenge';
        when 'battle_lead_taken' then
            notification_title := 'You Took the Lead!';
            notification_body  := 'You are now ahead of ' || actor_name;
        when 'battle_lead_lost' then
            notification_title := 'Lead Lost';
            notification_body  := actor_name || ' just took the lead in your battle';
        when 'battle_opponent_activity' then
            notification_title := 'Opponent Active';
            notification_body  := actor_name || ' just logged a workout in your battle';
        when 'battle_ending_soon' then
            notification_title := 'Battle Ending Soon';
            notification_body  := 'Your battle with ' || actor_name || ' ends in 24 hours';
        when 'battle_completed' then
            notification_title := 'Battle Ended';
            notification_body  := 'Your battle with ' || actor_name || ' has ended';
        when 'battle_victory' then
            notification_title := 'Victory!';
            notification_body  := 'You beat ' || actor_name || ' in your battle';
        when 'battle_defeat' then
            notification_title := 'Battle Lost';
            notification_body  := actor_name || ' won the battle. Challenge them to a rematch!';

        -- Challenge
        when 'challenge_invite' then
            notification_title := 'Challenge Invite';
            notification_body  := actor_name || ' invited you to join a challenge';
        when 'challenge_joined' then
            notification_title := 'New Challenger';
            notification_body  := actor_name || ' joined your challenge';
        when 'challenge_milestone' then
            notification_title := 'Milestone Reached!';
            notification_body  := 'You reached a new milestone in your challenge';
        when 'challenge_leaderboard_change' then
            notification_title := 'Leaderboard Update';
            notification_body  := 'Your position changed in the challenge leaderboard';
        when 'challenge_ending_soon' then
            notification_title := 'Challenge Ending Soon';
            notification_body  := 'Your challenge ends in 24 hours';
        when 'challenge_completed' then
            notification_title := 'Challenge Complete!';
            notification_body  := 'Challenge finished — check your final ranking';
        when 'challenge_new_participant' then
            notification_title := 'New Participant';
            notification_body  := actor_name || ' joined the challenge you are in';

        -- Virtual run
        when 'virtual_run_invite' then
            notification_title := 'Run Together!';
            notification_body  := actor_name || ' wants to run with you';

        -- Workout / Planner
        when 'workout_completed' then
            notification_title := 'Workout Complete';
            notification_body  := actor_name || ' just completed a workout';
        when 'program_invite' then
            notification_title := 'Program Shared';
            notification_body  := actor_name || ' shared a program with you';

        else
            raise warning 'send_push_notification: unhandled notification type "%" for notification %', new.type, new.id;
            return new;
    end case;

    perform net.http_post(
        url     := push_url,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || service_key
        ),
        body    := jsonb_build_object(
            'user_id', new.user_id,
            'title',   notification_title,
            'body',    notification_body,
            'data',    jsonb_build_object(
                'user_id',         new.user_id,
                'type',            new.type,
                'notification_id', new.id,
                'actor_id',        new.actor_id,
                'target_id',       new.target_id
            )
        )
    );

    return new;
exception
    when others then
        raise warning 'Failed to send push notification for notification %: %', new.id, sqlerrm;
        return new;
end;
$$;

drop trigger if exists on_notification_created_send_push on public.notifications;
create trigger on_notification_created_send_push
    after insert on public.notifications
    for each row
    execute function public.send_push_notification();
