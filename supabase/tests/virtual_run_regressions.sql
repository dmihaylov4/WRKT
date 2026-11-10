begin;
insert into public.friendships(user_id, friend_id, status) values
    ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'accepted');
insert into public.virtual_runs (id, inviter_id, invitee_id, status) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'active'),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'pending');

set local role anon;
select tests.expect_error($sql$select public.complete_virtual_run(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 1000, 300)$sql$, '42501');

set local role authenticated;
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select tests.expect_error($sql$select public.complete_virtual_run(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 1000, 300)$sql$, '42501');

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select tests.expect_error($sql$insert into public.virtual_runs(inviter_id, invitee_id, status) values
    ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'completed')$sql$, '42501');
select tests.expect_error($sql$insert into public.virtual_runs(inviter_id, invitee_id) values
    ('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333')$sql$, '42501');
insert into public.virtual_runs(inviter_id, invitee_id) values
    ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222');
select tests.expect_error($sql$select public.complete_virtual_run(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 1000, 300)$sql$, '42501');
select tests.expect_error($sql$select public.complete_virtual_run(
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '11111111-1111-1111-1111-111111111111', 1000, 300)$sql$, '22023');

do $$
declare distance double precision;
begin
    foreach distance in array array[-1, 'NaN'::float8, 'Infinity'::float8, '-Infinity'::float8, null::float8] loop
        perform tests.expect_error(format(
            'select public.complete_virtual_run(%L, %L, %L::float8, 300)',
            'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', distance), '22023');
    end loop;
end;
$$;
select tests.expect_error($sql$select public.complete_virtual_run(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 1000, -1)$sql$, '22023');
select tests.expect_error($sql$select public.complete_virtual_run(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 1000, 300, -1, 150)$sql$, '22023');
select tests.expect_error($sql$select public.complete_virtual_run(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 1000, 300, 300, 301)$sql$, '22023');

-- Direct writes cannot bypass finalization or replace participants.
select tests.expect_error($sql$update public.virtual_runs set invitee_duration_s = 1
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$sql$, '42501');
select tests.expect_error($sql$update public.virtual_runs set invitee_id = '33333333-3333-3333-3333-333333333333'
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$sql$, '42501');
select tests.expect_error($sql$update public.virtual_runs set status = 'completed'
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$sql$, '42501');
select tests.expect_error($sql$update public.virtual_runs set status = 'active'
    where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'$sql$, '42501');
select tests.expect_error($sql$update public.virtual_runs set invitee_route_uploaded = true
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$sql$, '42501');
update public.virtual_runs set inviter_route_uploaded = true where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

-- A first submission is final. Identical retry returns the same record.
do $$
declare first_result jsonb; retry_result jsonb;
begin
    first_result := public.complete_virtual_run('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        '11111111-1111-1111-1111-111111111111', 1000, 300, 300, 150)::jsonb;
    retry_result := public.complete_virtual_run('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        '11111111-1111-1111-1111-111111111111', 1000, 300, 300, 150)::jsonb;
    if first_result is distinct from retry_result or first_result->>'status' <> 'active' then
        raise exception 'First participant retry changed the run';
    end if;
end;
$$;
select tests.expect_error($sql$select public.complete_virtual_run(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 2000, 300, 300, 150)$sql$, '22023');

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
update public.virtual_runs set status = 'active', started_at = now()
    where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
do $$ begin
    if not exists (select 1 from public.virtual_runs
        where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' and status = 'active' and started_at = now()) then
        raise exception 'Invitee acceptance failed';
    end if;
end $$;
do $$
declare completed jsonb; retry_result jsonb;
begin
    completed := public.complete_virtual_run('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        '22222222-2222-2222-2222-222222222222', 900, 290)::jsonb;
    retry_result := public.complete_virtual_run('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        '22222222-2222-2222-2222-222222222222', 900, 290)::jsonb;
    if completed is distinct from retry_result or completed->>'status' <> 'completed'
        or completed->>'winner_id' <> '11111111-1111-1111-1111-111111111111'
        or completed->>'ended_at' is null then
        raise exception 'Completion/retry did not preserve both results and winner';
    end if;
end;
$$;
select tests.expect_error($sql$select public.complete_virtual_run(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 5000, 290)$sql$, '22023');
select tests.expect_error($sql$update public.virtual_runs set status = 'cancelled'
    where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$sql$, '42501');
rollback;
\echo 'Virtual-run authorization and immutable finalization: PASS'
