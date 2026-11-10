-- Deferred by the owner on 2026-09-30 until the coordinated app release.
-- Older accepted rows have no trustworthy consent provenance. Preserve each
-- relationship ID and creation date, and use the existing recipient acceptance
-- flow before it grants private access again. Blocked rows are left untouched.
alter table public.friendships add column requires_reconfirmation boolean not null default false;

create or replace function public.enforce_friendship_consent()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller_id uuid := auth.uid();
begin
    -- Allow trusted maintenance and account-deletion cascades, not anonymous API calls.
    if caller_id is null then
        if current_setting('role', true) in ('postgres', 'service_role')
           or (session_user = 'postgres' and current_setting('role', true) = 'none') then
            if tg_op = 'DELETE' then return old; end if;
            return new;
        end if;
        raise exception 'Authentication required' using errcode = '42501';
    end if;

    if tg_op = 'INSERT' then
        if new.user_id is distinct from caller_id or new.friend_id = caller_id
           or new.status is distinct from 'pending' or new.blocked_by is not null then
            raise exception 'A friend request must start pending' using errcode = '42501';
        end if;
        -- Serialize requests in both directions, including a blocked reverse row.
        perform pg_advisory_xact_lock(hashtextextended(
            least(new.user_id, new.friend_id)::text || greatest(new.user_id, new.friend_id)::text, 0
        ));
        if exists (
            select 1 from public.friendships
            where (user_id = new.user_id and friend_id = new.friend_id)
               or (user_id = new.friend_id and friend_id = new.user_id)
        ) then
            raise exception 'A relationship already exists' using errcode = '23505';
        end if;
        return new;
    end if;

    if caller_id <> old.user_id and caller_id <> old.friend_id then
        raise exception 'Only participants may change a friendship' using errcode = '42501';
    end if;
    if tg_op = 'DELETE' then
        if old.status = 'blocked' and old.blocked_by is distinct from caller_id then
            raise exception 'Only the blocker may remove a block' using errcode = '42501';
        end if;
        return old;
    end if;

    if new.id is distinct from old.id or new.user_id is distinct from old.user_id
       or new.friend_id is distinct from old.friend_id or new.created_at is distinct from old.created_at
       or new.blocked_by is distinct from old.blocked_by then
        raise exception 'Relationship identity is immutable' using errcode = '42501';
    end if;
    if new.status is not distinct from old.status then return new; end if;

    if old.status = 'pending' and new.status = 'accepted' and caller_id = old.friend_id then
        new.requires_reconfirmation := false;
        return new;
    end if;
    if old.status in ('pending', 'accepted') and new.status = 'blocked' then
        new.blocked_by := caller_id;
        return new;
    end if;
    raise exception 'Invalid friendship transition' using errcode = '42501';
end;
$$;


revoke insert, update on public.friendships from public, anon, authenticated;
grant insert (id, user_id, friend_id, status) on public.friendships to authenticated;
grant update (status, muted_notifications) on public.friendships to authenticated;

update public.friendships
set status = 'pending', requires_reconfirmation = true
where status = 'accepted';
notify pgrst, 'reload schema';
