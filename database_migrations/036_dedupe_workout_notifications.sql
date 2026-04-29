-- Dedupe workout-completed notifications and keep one canonical workout-post trigger.

alter table public.notifications add column if not exists metadata jsonb;
alter table public.friendships add column if not exists muted_notifications boolean default false;

drop trigger if exists workout_post_notification_trigger on public.workout_posts;
drop function if exists public.notify_friends_on_workout_post() cascade;

with ranked as (
    select
        id,
        row_number() over (
            partition by user_id, type, actor_id, target_id
            order by created_at asc, id asc
        ) as rn
    from public.notifications
    where type = 'workout_completed'
      and target_id is not null
)
delete from public.notifications n
using ranked r
where n.id = r.id
  and r.rn > 1;

create unique index if not exists idx_notifications_workout_completed_unique
    on public.notifications (user_id, type, actor_id, target_id)
    where type = 'workout_completed';

create or replace function public.create_workout_completed_notifications()
returns trigger
security definer
set search_path = public
language plpgsql
as $$
declare
    notification_metadata jsonb;
    workout_type text;
    distance_m numeric;
begin
    if new.visibility = 'private' then
        return new;
    end if;

    workout_type := new.workout_data->>'cardioWorkoutType';
    notification_metadata := '{}'::jsonb;

    if workout_type is not null and length(workout_type) > 0 then
        notification_metadata := notification_metadata
            || jsonb_build_object('workout_type', workout_type);

        if (new.workout_data->>'matchedHealthKitDistance') ~ '^[0-9]+(\.[0-9]+)?$' then
            distance_m := (new.workout_data->>'matchedHealthKitDistance')::numeric;
            if distance_m > 0 then
                notification_metadata := notification_metadata
                    || jsonb_build_object('distance_km', round(distance_m / 1000.0, 2)::text);
            end if;
        end if;
    end if;

    insert into public.notifications (user_id, type, actor_id, target_id, read, metadata)
    select
        case
            when f.user_id = new.user_id then f.friend_id
            else f.user_id
        end,
        'workout_completed',
        new.user_id,
        new.id,
        false,
        notification_metadata
    from public.friendships f
    where (f.user_id = new.user_id or f.friend_id = new.user_id)
      and f.status = 'accepted'
      and coalesce(f.muted_notifications, false) = false
    on conflict (user_id, type, actor_id, target_id)
    where type = 'workout_completed'
    do nothing;

    return new;
end;
$$;

drop trigger if exists on_workout_post_created on public.workout_posts;
create trigger on_workout_post_created
    after insert on public.workout_posts
    for each row
    execute function public.create_workout_completed_notifications();
