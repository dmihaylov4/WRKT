begin;
insert into storage.objects(bucket_id, name) values
    ('user-images', '11111111-1111-1111-1111-111111111111/avatar.jpg'),
    ('user-images', '22222222-2222-2222-2222-222222222222/avatar.jpg');
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
do $$
declare changed integer;
begin
    update storage.objects set name = '11111111-1111-1111-1111-111111111111/stolen.jpg'
        where name = '22222222-2222-2222-2222-222222222222/avatar.jpg';
    get diagnostics changed = row_count;
    if changed <> 0 then raise exception 'Cross-account avatar overwrite succeeded'; end if;
    delete from storage.objects where name = '22222222-2222-2222-2222-222222222222/avatar.jpg';
    get diagnostics changed = row_count;
    if changed <> 0 then raise exception 'Cross-account avatar delete succeeded'; end if;
end;
$$;
select tests.expect_error($sql$insert into storage.objects(bucket_id, name)
    values ('user-images', '22222222-2222-2222-2222-222222222222/forged.jpg')$sql$, '42501');
select tests.expect_error($sql$update storage.objects set name = '22222222-2222-2222-2222-222222222222/moved.jpg'
    where name = '11111111-1111-1111-1111-111111111111/avatar.jpg'$sql$, '42501');
insert into storage.objects(bucket_id, name)
    values ('user-images', '11111111-1111-1111-1111-111111111111/avatar.jpg')
    on conflict(bucket_id, name) do update set name = excluded.name;
update storage.objects set name = '11111111-1111-1111-1111-111111111111/replaced.jpg'
    where name = '11111111-1111-1111-1111-111111111111/avatar.jpg';
do $$ begin
    if not exists (select 1 from storage.objects
        where name = '11111111-1111-1111-1111-111111111111/replaced.jpg') then
        raise exception 'Own avatar replacement failed';
    end if;
end $$;
delete from storage.objects where name = '11111111-1111-1111-1111-111111111111/replaced.jpg';

set local request.jwt.claim.sub = 'abcdefab-cdef-abcd-efab-cdefabcdefab';
insert into storage.objects(bucket_id, name)
    values ('user-images', 'ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB/avatar.jpg');
set local role anon;
do $$ begin
    if (select count(*) from storage.objects) <> 2 then
        raise exception 'Public avatar reads or owner deletion changed';
    end if;
end $$;
rollback;
\echo 'Avatar ownership, rename, upsert and public reads: PASS'
