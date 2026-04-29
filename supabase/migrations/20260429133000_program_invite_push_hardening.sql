-- Make program invite push delivery failures visible instead of silently swallowing
-- missing database settings. In-app notifications are created by
-- notify_program_invite(); APNs delivery depends on this notification trigger.

create extension if not exists pg_net;

create or replace function public.send_push_notification()
returns trigger
language plpgsql
security definer
as $$
declare
    actor_name text;
    notification_title text;
    notification_body text;
    push_url text;
    service_key text;
begin
    push_url := nullif(current_setting('app.settings.push_function_url', true), '');
    service_key := nullif(current_setting('app.settings.service_role_key', true), '');

    if push_url is null or service_key is null then
        raise warning 'Push notification skipped: app.settings.push_function_url or app.settings.service_role_key is not set';
        return new;
    end if;

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
            notification_title := 'VOLIA';
            notification_body := 'You have a new notification';
    end case;

    perform net.http_post(
        url := push_url,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || service_key
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
        raise warning 'Failed to send push notification for notification %: %', new.id, SQLERRM;
        return new;
end;
$$;

drop trigger if exists on_notification_created_send_push on public.notifications;
create trigger on_notification_created_send_push
    after insert on public.notifications
    for each row
    execute function public.send_push_notification();

create or replace function public.verify_program_invite_push_setup()
returns table(check_name text, ok boolean, detail text)
language sql
security definer
as $$
    select
        'program invite notification trigger',
        exists (
            select 1
            from information_schema.triggers
            where event_object_schema = 'public'
              and event_object_table = 'program_invites'
              and trigger_name = 'notify_on_program_invite_insert'
        ),
        'program_invites insert should create an in-app notification'
    union all
    select
        'notification push trigger',
        exists (
            select 1
            from information_schema.triggers
            where event_object_schema = 'public'
              and event_object_table = 'notifications'
              and trigger_name = 'on_notification_created_send_push'
        ),
        'notifications insert should call send_push_notification()'
    union all
    select
        'push function url setting',
        nullif(current_setting('app.settings.push_function_url', true), '') is not null,
        coalesce(nullif(current_setting('app.settings.push_function_url', true), ''), 'missing')
    union all
    select
        'service role setting',
        nullif(current_setting('app.settings.service_role_key', true), '') is not null,
        case
            when nullif(current_setting('app.settings.service_role_key', true), '') is null then 'missing'
            else 'set'
        end
    union all
    select
        'pg_net extension',
        exists (select 1 from pg_extension where extname = 'pg_net'),
        'required for net.http_post';
$$;
