begin;
set plpgsql.check_asserts = on;

do $$ begin
    assert not has_function_privilege('anon', 'public.upsert_device_token(uuid,text,text,text)', 'execute');
    assert not has_table_privilege('anon', 'public.device_tokens', 'select');
    assert not has_table_privilege('authenticated', 'public.device_tokens', 'insert');
    assert not has_table_privilege('authenticated', 'public.device_tokens', 'update');
    assert (select verified_at is null from public.device_tokens where token = 'legacy-token');
end $$;

set local role anon;
select tests.expect_error($q$select public.upsert_device_token('11111111-1111-1111-1111-111111111111','attacker-token')$q$, '42501');

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select tests.expect_error($q$select public.upsert_device_token('22222222-2222-2222-2222-222222222222','attacker-token')$q$, '42501');
select tests.expect_error($q$select public.upsert_device_token('11111111-1111-1111-1111-111111111111','','ios','production')$q$, '22023');
select public.upsert_device_token('11111111-1111-1111-1111-111111111111','valid-device','ios','sandbox');
do $$ begin
    assert (select verified_at is not null from public.device_tokens where token = 'valid-device');
end $$;

set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select public.upsert_device_token('22222222-2222-2222-2222-222222222222','valid-device','ios','production');
do $$ begin
    assert (select user_id = auth.uid() and environment = 'production' from public.device_tokens where token = 'valid-device');
end $$;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
delete from public.device_tokens where token = 'valid-device';
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$ begin assert (select count(*) = 1 from public.device_tokens where token = 'valid-device'); end $$;
delete from public.device_tokens where token = 'valid-device';

set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select tests.expect_error($q$insert into public.friendships(user_id,friend_id,status) values ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222','accepted')$q$, '42501');
insert into public.friendships(id,user_id,friend_id)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222');
select tests.expect_error($q$update public.friendships set status='accepted' where id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$q$, '42501');
select tests.expect_error($q$update public.friendships set friend_id='33333333-3333-3333-3333-333333333333' where id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$q$, '42501');
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
update public.friendships set status='accepted' where id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
do $$ begin assert (select status='accepted' from public.friendships where id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'); end $$;
update public.friendships set muted_notifications=true where id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
update public.friendships set status='blocked' where id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
do $$ begin assert (select blocked_by=auth.uid() from public.friendships where id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'); end $$;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select tests.expect_error($q$delete from public.friendships where id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$q$, '42501');
select tests.expect_error($q$update public.friendships set status='accepted' where id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$q$, '42501');
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select tests.expect_error($q$insert into public.friendships(user_id,friend_id) values ('22222222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111')$q$, '23505');
delete from public.friendships where id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
do $$ begin assert not exists (select 1 from public.friendships); end $$;

rollback;
\echo 'PASS: token ownership, legacy quarantine, consent, immutable participants and block protection'
