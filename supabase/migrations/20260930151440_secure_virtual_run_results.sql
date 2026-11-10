-- Keep the released client's lifecycle writes, but make results server-owned.
revoke all on public.virtual_runs from public, anon;
revoke insert, update on public.virtual_runs from authenticated;
grant insert (inviter_id, invitee_id, status) on public.virtual_runs to authenticated;
grant update (status, started_at, inviter_route_uploaded, invitee_route_uploaded)
    on public.virtual_runs to authenticated;

create function public.guard_virtual_run_client_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare caller uuid := auth.uid();
begin
    -- Invoker security distinguishes direct client writes from the completion
    -- function and server maintenance. Clients cannot assume these roles.
    if current_user in ('postgres', 'service_role') then return new; end if;
    if caller is null then
        raise exception 'Authentication required' using errcode = '42501';
    end if;
    if tg_op = 'INSERT' then
        if new.inviter_id is distinct from caller or new.invitee_id = caller
            or new.status is distinct from 'pending' then
            raise exception 'Only pending invitations may be created' using errcode = '42501';
        end if;
        if not exists (
            select 1 from public.friendships f where f.status = 'accepted'
                and ((f.user_id = caller and f.friend_id = new.invitee_id)
                    or (f.friend_id = caller and f.user_id = new.invitee_id))
        ) then
            raise exception 'An accepted friendship is required' using errcode = '42501';
        end if;
        return new;
    end if;

    if caller not in (old.inviter_id, old.invitee_id) then
        raise exception 'Participant required' using errcode = '42501';
    end if;
    if (caller = old.inviter_id and new.invitee_route_uploaded is distinct from old.invitee_route_uploaded)
        or (caller = old.invitee_id and new.inviter_route_uploaded is distinct from old.inviter_route_uploaded) then
        raise exception 'Cannot change another participant route' using errcode = '42501';
    end if;
    if new.status is distinct from old.status then
        if old.status = 'pending' and new.status = 'active' and caller = old.invitee_id
            and (old.expires_at is null or old.expires_at > now()) then
            new.started_at := now();
        elsif old.status in ('pending', 'active') and new.status = 'cancelled' then
            new.started_at := old.started_at;
        else
            raise exception 'Invalid run transition' using errcode = '42501';
        end if;
    elsif new.started_at is distinct from old.started_at then
        raise exception 'Run start time is immutable' using errcode = '42501';
    end if;
    return new;
end;
$$;
revoke all on function public.guard_virtual_run_client_write() from public, anon, authenticated;
create trigger guard_virtual_run_client_write
    before insert or update on public.virtual_runs
    for each row execute function public.guard_virtual_run_client_write();

create or replace function public.complete_virtual_run(
    p_run_id uuid,
    p_user_id uuid,
    p_distance_m double precision,
    p_duration_s integer,
    p_avg_pace_sec_per_km integer default null,
    p_avg_heart_rate integer default null
)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller uuid := auth.uid();
    run public.virtual_runs;
    submitted boolean;
    same_result boolean;
begin
    if caller is null or p_user_id is distinct from caller then
        raise exception 'Authenticated participant required' using errcode = '42501';
    end if;
    select * into run from public.virtual_runs
        where id = p_run_id and caller in (inviter_id, invitee_id) for update;
    if not found then
        raise exception 'Run unavailable' using errcode = '42501';
    end if;
    if run.status not in ('active', 'completed') then
        raise exception 'Run is not active' using errcode = '22023';
    end if;
    -- Broad safety bounds, including rejection of NaN and infinity.
    if p_distance_m is null or not (p_distance_m between 0 and 1000000)
        or p_duration_s is null or p_duration_s not between 0 and 604800
        or (p_avg_pace_sec_per_km is not null and p_avg_pace_sec_per_km not between 0 and 86400)
        or (p_avg_heart_rate is not null and p_avg_heart_rate not between 0 and 300) then
        raise exception 'Invalid run result' using errcode = '22023';
    end if;

    if caller = run.inviter_id then
        submitted := run.inviter_duration_s is not null;
        same_result := row(run.inviter_distance_m, run.inviter_duration_s,
            run.inviter_avg_pace_sec_per_km, run.inviter_avg_heart_rate)
            is not distinct from row(p_distance_m, p_duration_s, p_avg_pace_sec_per_km, p_avg_heart_rate);
    else
        submitted := run.invitee_duration_s is not null;
        same_result := row(run.invitee_distance_m, run.invitee_duration_s,
            run.invitee_avg_pace_sec_per_km, run.invitee_avg_heart_rate)
            is not distinct from row(p_distance_m, p_duration_s, p_avg_pace_sec_per_km, p_avg_heart_rate);
    end if;
    if submitted then
        if same_result then return row_to_json(run); end if;
        raise exception 'Result already finalized' using errcode = '22023';
    end if;

    if caller = run.inviter_id then
        update public.virtual_runs set
            inviter_distance_m = p_distance_m, inviter_duration_s = p_duration_s,
            inviter_avg_pace_sec_per_km = p_avg_pace_sec_per_km,
            inviter_avg_heart_rate = p_avg_heart_rate
        where id = p_run_id returning * into run;
    else
        update public.virtual_runs set
            invitee_distance_m = p_distance_m, invitee_duration_s = p_duration_s,
            invitee_avg_pace_sec_per_km = p_avg_pace_sec_per_km,
            invitee_avg_heart_rate = p_avg_heart_rate
        where id = p_run_id returning * into run;
    end if;
    if run.inviter_duration_s is not null and run.invitee_duration_s is not null then
        update public.virtual_runs set status = 'completed', ended_at = coalesce(ended_at, now()),
            winner_id = case
                when run.inviter_distance_m > run.invitee_distance_m then run.inviter_id
                when run.invitee_distance_m > run.inviter_distance_m then run.invitee_id
                else null
            end
        where id = p_run_id returning * into run;
    end if;
    return row_to_json(run);
end;
$$;
revoke all on function public.complete_virtual_run(uuid, uuid, double precision, integer, integer, integer)
    from public, anon;
grant execute on function public.complete_virtual_run(uuid, uuid, double precision, integer, integer, integer)
    to authenticated;
notify pgrst, 'reload schema';
