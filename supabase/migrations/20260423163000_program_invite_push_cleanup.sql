-- Keep program invite notifications actionable-only and send program invite APNs.

create or replace function public.cleanup_program_invite_notification()
returns trigger
language plpgsql
security definer
as $$
begin
    if old.status = 'pending' and new.status in ('accepted', 'declined', 'revoked') then
        delete from public.notifications
        where type = 'program_invite'
          and target_id = new.id;
    end if;
    return new;
end;
$$;

drop trigger if exists cleanup_on_program_invite_terminal_transition on public.program_invites;
create trigger cleanup_on_program_invite_terminal_transition
    after update on public.program_invites
    for each row execute function public.cleanup_program_invite_notification();

create or replace function public.send_push_notification()
returns trigger
language plpgsql
security definer
as $$
declare
    actor_name text;
    notification_title text;
    notification_body text;
begin
    select coalesce(display_name, username, 'Someone') into actor_name
    from public.profiles
    where id = new.actor_id;

    case new.type
        when 'friend_request' then
            notification_title := 'New Friend Request';
            notification_body := actor_name || ' sent you a friend request';
        when 'friend_accepted' then
            notification_title := 'Friend Request Accepted';
            notification_body := actor_name || ' accepted your friend request';
        when 'post_like' then
            notification_title := 'New Like';
            notification_body := actor_name || ' liked your workout';
        when 'post_comment' then
            notification_title := 'New Comment';
            notification_body := actor_name || ' commented on your workout';
        when 'comment_reply' then
            notification_title := 'New Reply';
            notification_body := actor_name || ' replied to your comment';
        when 'comment_mention' then
            notification_title := 'You were mentioned';
            notification_body := actor_name || ' mentioned you in a comment';
        when 'program_invite' then
            notification_title := 'Program Shared';
            notification_body := actor_name || ' shared a program with you';
        else
            notification_title := 'WRKT';
            notification_body := 'You have a new notification';
    end case;

    perform net.http_post(
        url := current_setting('app.settings.push_function_url', true),
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
        ),
        body := jsonb_build_object(
            'user_id', new.user_id,
            'title', notification_title,
            'body', notification_body,
            'data', jsonb_build_object(
                'user_id', new.user_id,
                'type', new.type,
                'notification_id', new.id,
                'actor_id', new.actor_id,
                'target_id', new.target_id
            )
        )
    );

    return new;
exception
    when others then
        raise warning 'Failed to send push notification: %', SQLERRM;
        return new;
end;
$$;

drop trigger if exists on_notification_created_send_push on public.notifications;
create trigger on_notification_created_send_push
    after insert on public.notifications
    for each row
    execute function public.send_push_notification();
