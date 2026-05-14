-- Replace current_setting() approach (requires superuser) with a config table.
-- After applying this migration, insert the service_role_key via SQL editor:
--   INSERT INTO private.push_config (key, value)
--   VALUES ('service_role_key', 'YOUR_SERVICE_ROLE_KEY')
--   ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

create schema if not exists private;

create table if not exists private.push_config (
    key  text primary key,
    value text not null
);

revoke all on private.push_config from anon, authenticated;

-- Push URL is not sensitive — hardcode it
insert into private.push_config (key, value)
values ('push_function_url', 'https://wjkokxhdpuoacazaohsa.supabase.co/functions/v1/send-push')
on conflict (key) do update set value = excluded.value;

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
        when 'program_invite' then
            notification_title := 'Program Shared';
            notification_body  := actor_name || ' shared a program with you';
        when 'workout_completed' then
            notification_title := 'Workout Complete';
            notification_body  := actor_name || ' just completed a workout';
        else
            notification_title := 'VOLIA';
            notification_body  := 'You have a new notification';
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
