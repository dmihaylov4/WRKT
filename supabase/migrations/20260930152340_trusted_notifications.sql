-- Clients consume notifications; authorized database events create them.
drop policy "Allow authenticated inserts" on public.notifications;
revoke all on public.notifications from public, anon;
revoke insert, update on public.notifications from authenticated;
grant select, delete on public.notifications to authenticated;
grant update (read) on public.notifications to authenticated;
revoke all on function public.send_battle_completed_notifications(uuid) from public, anon, authenticated;
revoke all on function public.send_battle_ending_soon_notifications() from public, anon, authenticated;
grant execute on function public.send_battle_completed_notifications(uuid),
    public.send_battle_ending_soon_notifications() to service_role;

-- A caller must be able to read the underlying post before triggering an event.
drop policy "Users can create their own likes" on public.post_likes;
create policy "Users can create their own likes" on public.post_likes
    for insert to authenticated with check (
        auth.uid() = user_id and exists (select 1 from public.workout_posts p where p.id = post_id)
    );
drop policy "Users can view all likes" on public.post_likes;
create policy "Users can read likes on visible posts" on public.post_likes
    for select using (exists (select 1 from public.workout_posts p where p.id = post_id));
drop policy "Users can create comments" on public.post_comments;
create policy "Users can create comments" on public.post_comments
    for insert to authenticated with check (
        auth.uid() = user_id and exists (select 1 from public.workout_posts p where p.id = post_id)
    );
revoke update on public.post_comments from public, anon, authenticated;
grant update (content) on public.post_comments to authenticated;

create function public.validate_comment_parent()
returns trigger language plpgsql set search_path = '' as $$
begin
    if new.parent_comment_id is not null and not exists (
        select 1 from public.post_comments c
        where c.id = new.parent_comment_id and c.post_id = new.post_id and c.parent_comment_id is null
    ) then
        raise exception 'Reply must reference a visible top-level comment on this post' using errcode = '22023';
    end if;
    return new;
end;
$$;
create trigger validate_comment_parent before insert on public.post_comments
    for each row execute function public.validate_comment_parent();
revoke all on function public.validate_comment_parent() from public, anon, authenticated;

drop policy "Users can create mentions" on public.comment_mentions;
create policy "Comment authors can create mentions" on public.comment_mentions
    for insert to authenticated with check (
        exists (select 1 from public.post_comments c where c.id = comment_id and c.user_id = auth.uid())
    );
drop policy "Anyone can read comment mentions" on public.comment_mentions;
create policy "Users can read mentions on visible comments" on public.comment_mentions
    for select using (exists (select 1 from public.post_comments c where c.id = comment_id));

-- These two old triggers ran with client privileges. Make their narrow,
-- event-derived inserts trusted before removing the client's INSERT grant.
create or replace function public.notify_comment_reply()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    if new.parent_comment_id is not null then
        insert into public.notifications(user_id, type, actor_id, target_id)
        select c.user_id, 'comment_reply', new.user_id, new.post_id
        from public.post_comments c
        where c.id = new.parent_comment_id and c.post_id = new.post_id and c.user_id <> new.user_id;
    end if;
    return new;
end;
$$;

create or replace function public.notify_mentioned_users()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    insert into public.notifications(user_id, type, actor_id, target_id)
    select new.mentioned_user_id, 'comment_mention', c.user_id, c.post_id
    from public.post_comments c join public.workout_posts p on p.id = c.post_id
    where c.id = new.comment_id and new.mentioned_user_id <> c.user_id
        and (p.visibility = 'public' or p.user_id = new.mentioned_user_id
            or (p.visibility = 'friends' and exists (
                select 1 from public.friendships f where f.status = 'accepted'
                    and ((f.user_id = p.user_id and f.friend_id = new.mentioned_user_id)
                        or (f.friend_id = p.user_id and f.user_id = new.mentioned_user_id))
            )));
    return new;
end;
$$;
revoke all on function public.notify_comment_reply(), public.notify_mentioned_users()
    from public, anon, authenticated;

create function public.notify_virtual_run_invite()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    if new.status = 'pending' then
        insert into public.notifications(user_id, type, actor_id, target_id)
        values (new.invitee_id, 'virtual_run_invite', new.inviter_id, new.id);
    end if;
    return new;
end;
$$;
create trigger notify_virtual_run_invite after insert on public.virtual_runs
    for each row execute function public.notify_virtual_run_invite();
revoke all on function public.notify_virtual_run_invite() from public, anon, authenticated;

-- Replace the client-side leaderboard scan with the actual progress transition.
create or replace function public.notify_challenge_milestone()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
    challenge public.challenges;
    milestone integer;
begin
    if tg_op <> 'UPDATE' or new.current_progress <= old.current_progress then return new; end if;
    select * into challenge from public.challenges where id = new.challenge_id;
    if challenge.goal_value is null or challenge.goal_value <= 0 then return new; end if;
    milestone := least(100, floor(new.current_progress / challenge.goal_value * 4)::integer * 25);
    if milestone < 25 or old.current_progress / challenge.goal_value * 100 >= milestone then return new; end if;
    insert into public.notifications(user_id, type, actor_id, target_id, metadata)
    select new.user_id, 'challenge_milestone', new.user_id, new.challenge_id,
        jsonb_build_object('milestone', milestone::text, 'challenge_title', challenge.title,
            'progress', new.current_progress::text, 'goal', challenge.goal_value::text)
    where not exists (select 1 from public.notifications n
        where n.user_id = new.user_id and n.type = 'challenge_milestone'
            and n.target_id = new.challenge_id and n.metadata->>'milestone' = milestone::text);
    return new;
end;
$$;
revoke all on function public.notify_challenge_milestone() from public, anon, authenticated;

create or replace function public.notify_challenge_leaderboard_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare challenge_title text;
begin
    if new.current_progress <= old.current_progress then return new; end if;
    select title into challenge_title from public.challenges where id = new.challenge_id;
    insert into public.notifications(user_id, type, actor_id, target_id, metadata)
    select p.user_id, 'challenge_leaderboard_change', new.user_id, new.challenge_id,
        jsonb_build_object(
            'challenge_title', challenge_title,
            'position', (1 + (select count(*) from public.challenge_participants ahead
                where ahead.challenge_id = new.challenge_id
                    and ahead.current_progress > p.current_progress))::text
        )
    from public.challenge_participants p
    where p.challenge_id = new.challenge_id and p.user_id <> new.user_id
        and not p.completed and p.current_progress > old.current_progress
        and p.current_progress < new.current_progress
    order by p.current_progress desc limit 5;
    return new;
end;
$$;
revoke all on function public.notify_challenge_leaderboard_change() from public, anon, authenticated;
notify pgrst, 'reload schema';
