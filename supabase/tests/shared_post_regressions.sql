begin;
set plpgsql.check_asserts = on;
create trigger test_push after insert on public.notifications
    for each row execute function public.send_push_notification();

insert into public.friendships(user_id, friend_id, status)
values ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'accepted');

set local role anon;
select tests.expect_error($q$select public.create_shared_post()$q$, '42501');

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select tests.expect_error($q$select public.create_shared_post()$q$, '22023');
select tests.expect_error($q$select public.create_shared_post(p_visibility=>'friends', p_workout_data=>'{}', p_partner_user_id=>'33333333-3333-3333-3333-333333333333')$q$, '42501');
select tests.expect_error($q$select public.create_shared_post(p_visibility=>'friends', p_workout_data=>'{}', p_partner_user_id=>'11111111-1111-1111-1111-111111111111')$q$, '22023');
select tests.expect_error($q$select public.create_shared_post(p_visibility=>'friends', p_workout_data=>'{}', p_partner_user_id=>'22222222-2222-2222-2222-222222222222', p_partner_vr_stats=>'{}')$q$, '42501');

-- Exact omitted-optional argument pattern of the installed single-workout client.
select public.create_shared_post(
    p_visibility => 'friends',
    p_images => '[{"url":"https://example.test/fixture-map.jpg"}]',
    p_workout_data => '{"id":"44444444-4444-4444-4444-444444444444"}',
    p_partner_user_id => '22222222-2222-2222-2222-222222222222'
);

-- New clients send explicit nulls, which must retain identical semantics.
select public.create_shared_post(
    p_caption => null, p_visibility => 'friends', p_images => null,
    p_workout_data => '{"id":"55555555-5555-5555-5555-555555555555"}',
    p_workout_data_list => null,
    p_partner_user_id => '22222222-2222-2222-2222-222222222222',
    p_partner_vr_stats => null, p_run_id => null
);

reset role;
do $$ begin
    assert (select count(*) = 2 from public.workout_posts);
    assert (select bool_and(user_id='11111111-1111-1111-1111-111111111111' and visibility='friends' and post_type='shared') from public.workout_posts);
    assert (select count(*) = 2 from public.post_participants where user_id='22222222-2222-2222-2222-222222222222');
    assert (select count(*) = 2 from public.notifications where user_id='22222222-2222-2222-2222-222222222222' and type='post_participant_tag');
    assert (select count(*) = 2 from net.requests);
    assert (select bool_and(headers->>'Authorization' = 'Bearer isolated-dispatch-secret') from net.requests);
end $$;

rollback;
\echo 'PASS: legacy and explicit-null shared posts, participant ownership and authorization'
