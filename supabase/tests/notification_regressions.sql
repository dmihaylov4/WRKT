begin;
insert into public.friendships(user_id, friend_id, status) values
    ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'accepted');
insert into public.challenges(id, title, goal_value) values ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'Fixture challenge', 100);
insert into public.challenge_participants(challenge_id, user_id, current_progress) values
    ('ffffffff-ffff-ffff-ffff-ffffffffffff', '11111111-1111-1111-1111-111111111111', 20),
    ('ffffffff-ffff-ffff-ffff-ffffffffffff', '22222222-2222-2222-2222-222222222222', 60),
    ('ffffffff-ffff-ffff-ffff-ffffffffffff', '33333333-3333-3333-3333-333333333333', 70);
insert into public.workout_posts(id, user_id, visibility, post_type) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'private', 'workout'),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '22222222-2222-2222-2222-222222222222', 'public', 'workout');
insert into public.post_comments(id, post_id, user_id, content) values
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '22222222-2222-2222-2222-222222222222', 'Parent'),
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'Private parent');
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select tests.expect_error($sql$insert into public.notifications(user_id, actor_id, type)
    values ('22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333', 'friend_request')$sql$, '42501');
select tests.expect_error($sql$select public.send_battle_completed_notifications('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$sql$, '42501');
select tests.expect_error($sql$select public.send_battle_ending_soon_notifications()$sql$, '42501');
select tests.expect_error($sql$insert into public.post_likes(post_id, user_id) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111')$sql$, '42501');
select tests.expect_error($sql$insert into public.post_comments(post_id, user_id, content) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'Forged')$sql$, '42501');
select tests.expect_error($sql$insert into public.post_comments(post_id, user_id, content, parent_comment_id) values
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', 'Wrong post', 'dddddddd-dddd-dddd-dddd-dddddddddddd')$sql$, '22023');
select tests.expect_error($sql$insert into public.comment_mentions(comment_id, mentioned_user_id) values
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', '33333333-3333-3333-3333-333333333333')$sql$, '42501');

insert into public.post_likes(post_id, user_id) values
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111');
insert into public.post_comments(id, post_id, user_id, content) values
    ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', 'Visible comment');
insert into public.post_comments(post_id, user_id, content, parent_comment_id) values
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', 'Reply', 'cccccccc-cccc-cccc-cccc-cccccccccccc');
insert into public.comment_mentions(comment_id, mentioned_user_id) values
    ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', '33333333-3333-3333-3333-333333333333');
select tests.expect_error($sql$update public.post_comments set user_id = '33333333-3333-3333-3333-333333333333'
    where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'$sql$, '42501');
update public.post_comments set content = 'Edited' where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
insert into public.virtual_runs(inviter_id, invitee_id) values
    ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222');

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$ begin
    if (select count(*) from public.notifications) <> 4
        or exists (select 1 from public.notifications where actor_id <> '11111111-1111-1111-1111-111111111111')
        or not exists (select 1 from public.notifications where type = 'comment_reply') then
        raise exception 'Like, comment and reply events did not create exactly the authorized notifications';
    end if;
end $$;
select tests.expect_error($sql$update public.notifications set actor_id = '33333333-3333-3333-3333-333333333333'$sql$, '42501');
update public.notifications set read = true;
do $$ begin
    if exists (select 1 from public.notifications where not read) then
        raise exception 'Recipient cannot mark notifications read';
    end if;
end $$;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
do $$ begin
    if (select count(*) from public.notifications where type = 'comment_mention') <> 1 then
        raise exception 'Authorized mention event was lost';
    end if;
end $$;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
update public.challenge_participants set current_progress = 80 where user_id = auth.uid();
update public.challenge_participants set current_progress = 80 where user_id = auth.uid();
do $$ begin
    if (select count(*) from public.notifications where type = 'challenge_milestone') <> 1 then
        raise exception 'Progress transition did not create exactly one milestone';
    end if;
end $$;
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$ begin
    if (select count(*) from public.notifications where type = 'challenge_leaderboard_change'
        and metadata->>'position' = '3' and actor_id = '11111111-1111-1111-1111-111111111111') <> 1 then
        raise exception 'Displaced participant did not receive the server-derived rank';
    end if;
    if not exists (select 1 from public.notifications n join public.virtual_runs r on r.id = n.target_id
        where n.type = 'virtual_run_invite' and n.actor_id = r.inviter_id and n.user_id = r.invitee_id) then
        raise exception 'Virtual-run invitation notification missing';
    end if;
end $$;
rollback;
\echo 'Trusted notification events and mutation permissions: PASS'
