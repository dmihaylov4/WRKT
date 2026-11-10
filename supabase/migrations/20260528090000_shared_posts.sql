-- Shared / co-authored workout posts.

alter table public.notifications
    drop constraint if exists notifications_type_check;

create table if not exists public.post_participants (
    id uuid primary key default gen_random_uuid(),
    post_id uuid references public.workout_posts(id) on delete cascade not null,
    user_id uuid references public.profiles(id) not null,
    workout_data jsonb,
    vr_stats jsonb,
    joined_at timestamptz default now() not null,
    removed_at timestamptz
);

create index if not exists post_participants_post_id_idx
    on public.post_participants(post_id);

create index if not exists post_participants_user_id_active_idx
    on public.post_participants(user_id)
    where removed_at is null;

create unique index if not exists post_participants_post_user_active_idx
    on public.post_participants(post_id, user_id)
    where removed_at is null;

create unique index if not exists post_participants_one_active_per_post_idx
    on public.post_participants(post_id)
    where removed_at is null;

alter table public.post_participants enable row level security;

drop policy if exists participants_select on public.post_participants;
create policy participants_select on public.post_participants for select
    using (
        exists (
            select 1
            from public.workout_posts wp
            where wp.id = post_id
              and (
                wp.visibility = 'public'
                or wp.user_id = auth.uid()
                or (
                    wp.visibility = 'friends'
                    and exists (
                        select 1
                        from public.friendships f
                        where (
                                (f.user_id = auth.uid() and f.friend_id = wp.user_id)
                             or (f.user_id = wp.user_id and f.friend_id = auth.uid())
                            )
                          and f.status = 'accepted'
                    )
                )
              )
        )
    );

create or replace function public.remove_post_participant(p_post_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    update public.post_participants
    set removed_at = now()
    where post_id = p_post_id
      and user_id = auth.uid()
      and removed_at is null;
end;
$$;

create or replace function public.get_friend_feed(
    p_limit int,
    p_cursor_created_at timestamptz default null,
    p_cursor_id uuid default null
)
returns setof public.workout_posts
language sql stable
security definer
set search_path = public
as $$
    with friend_ids as (
        select case
            when user_id = auth.uid() then friend_id
            else user_id
        end as friend_id
        from public.friendships
        where (user_id = auth.uid() or friend_id = auth.uid())
          and status = 'accepted'
    ),
    deduped as (
        select distinct on (wp.id) wp.*
        from public.workout_posts wp
        left join public.post_participants pp
            on pp.post_id = wp.id and pp.removed_at is null
        where (
            wp.user_id = auth.uid()
            or pp.user_id = auth.uid()
            or
            wp.user_id in (select friend_id from friend_ids)
            or pp.user_id in (select friend_id from friend_ids)
        )
        and (
            wp.visibility = 'public'
            or wp.user_id = auth.uid()
            or (
                wp.visibility = 'friends'
                and exists (
                    select 1
                    from public.friendships f
                    where (
                            (f.user_id = auth.uid() and f.friend_id = wp.user_id)
                         or (f.user_id = wp.user_id and f.friend_id = auth.uid())
                        )
                      and f.status = 'accepted'
                )
            )
            or (
                wp.visibility = 'friends'
                and exists (
                    select 1
                    from public.post_participants pp2
                    join public.friendships f
                      on (
                            (f.user_id = auth.uid() and f.friend_id = pp2.user_id)
                         or (f.user_id = pp2.user_id and f.friend_id = auth.uid())
                         )
                    where pp2.post_id = wp.id
                      and pp2.removed_at is null
                      and f.status = 'accepted'
                )
            )
        )
        order by wp.id
    )
    select *
    from deduped
    where p_cursor_created_at is null
       or (created_at < p_cursor_created_at)
       or (created_at = p_cursor_created_at and id < p_cursor_id)
    order by created_at desc, id desc
    limit p_limit;
$$;

create or replace function public.create_shared_post(
    p_caption text,
    p_visibility text,
    p_images jsonb,
    p_workout_data jsonb,
    p_workout_data_list jsonb,
    p_partner_user_id uuid,
    p_partner_vr_stats jsonb,
    p_run_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_post_id uuid;
    v_is_vr boolean := p_partner_vr_stats is not null;
begin
    if auth.uid() is null then
        raise exception 'not_authenticated';
    end if;

    if p_partner_user_id = auth.uid() then
        raise exception 'cannot_tag_self';
    end if;

    if not v_is_vr then
        if not exists (
            select 1
            from public.friendships
            where ((user_id = auth.uid() and friend_id = p_partner_user_id)
                or (user_id = p_partner_user_id and friend_id = auth.uid()))
              and status = 'accepted'
        ) then
            raise exception 'not_friends';
        end if;
    end if;

    if v_is_vr then
        if p_run_id is null or not exists (
            select 1
            from public.virtual_runs
            where id = p_run_id
              and ((inviter_id = auth.uid() and invitee_id = p_partner_user_id)
                or (invitee_id = auth.uid() and inviter_id = p_partner_user_id))
        ) then
            raise exception 'not_vr_participants';
        end if;
    end if;

    insert into public.workout_posts (
        user_id, caption, workout_data, workout_data_list,
        images, visibility, post_type
    ) values (
        auth.uid(), p_caption, p_workout_data, p_workout_data_list,
        p_images, p_visibility, 'shared'
    )
    returning id into v_post_id;

    insert into public.post_participants (post_id, user_id, vr_stats)
    values (v_post_id, p_partner_user_id, p_partner_vr_stats);

    insert into public.notifications (user_id, type, actor_id, target_id)
    values (p_partner_user_id, 'post_participant_tag', auth.uid(), v_post_id);

    return v_post_id;
end;
$$;

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
    if new.post_type = 'shared' then
        return new;
    end if;

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

-- Add post_participant_tag branch; all other branches are unchanged from
-- 20260518000001_enrich_push_bodies.sql to preserve metadata-enriched bodies.
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
        -- Shared posts (new)
        when 'post_participant_tag' then
            notification_title := 'Workout Together';
            notification_body  := actor_name || ' tagged you in a shared workout';

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
            notification_body := case
                when (new.metadata->>'score_added') is not null
                     and (new.metadata->>'score_added') != ''
                then actor_name || ' added ' || (new.metadata->>'score_added') || ' kg'
                else actor_name || ' just logged a workout in your battle'
            end;
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
            notification_body := case
                when (new.metadata->>'position') is not null
                then actor_name || ' passed you. You dropped to #' || (new.metadata->>'position') || '.'
                else 'Your position changed in the challenge leaderboard'
            end;
        when 'challenge_ending_soon' then
            notification_title := 'Challenge Ending Soon';
            notification_body  := 'Your challenge ends in 24 hours';
        when 'challenge_completed' then
            notification_title := 'Challenge Complete!';
            notification_body  := 'Challenge finished — check your final ranking';
        when 'challenge_new_participant' then
            notification_title := 'New Participant';
            notification_body  := actor_name || ' joined the challenge you are in';

        -- Virtual run / Workout / Planner
        when 'virtual_run_invite' then
            notification_title := 'Run Together!';
            notification_body  := actor_name || ' wants to run with you';
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
