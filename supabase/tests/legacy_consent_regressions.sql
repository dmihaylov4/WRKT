-- Runs before the new migration, inside a transaction with isolated fixtures.
begin;
insert into public.friendships(id, user_id, friend_id, status) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'accepted'),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333', 'blocked');
insert into public.workout_posts(id, user_id, visibility, post_type) values
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'friends', 'workout');
\ir ../deferred/20260930153324_require_legacy_friendship_reconfirmation.sql
do $$ begin
    if not exists (select 1 from public.friendships
        where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and status = 'pending' and requires_reconfirmation) then
        raise exception 'Legacy relationship was lost or remained authorized';
    end if;
    if not exists (select 1 from public.friendships
        where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' and status = 'blocked') then
        raise exception 'Legacy block changed';
    end if;
end $$;
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ begin
    if exists (select 1 from public.workout_posts where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc') then
        raise exception 'Unverified relationship still exposes friends-only posts';
    end if;
end $$;
select tests.expect_error($sql$update public.friendships set status = 'accepted'
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$sql$, '42501');
select tests.expect_error($sql$update public.friendships set requires_reconfirmation = false
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$sql$, '42501');
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
update public.friendships set status = 'accepted' where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$ begin
    if not exists (select 1 from public.workout_posts where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc') then
        raise exception 'Recipient confirmation did not restore intended access';
    end if;
    if exists (select 1 from public.friendships where requires_reconfirmation) then
        raise exception 'Confirmed relationship still requests confirmation';
    end if;
end $$;
rollback;
\echo 'Legacy consent migration and recipient reconfirmation: PASS'
