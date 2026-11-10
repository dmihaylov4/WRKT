-- Existing assignments were accepted without caller authorization. Only a new,
-- authenticated registration may make a token eligible for push delivery.
alter table public.device_tokens add column if not exists verified_at timestamptz;

revoke all on public.device_tokens from public, anon;
revoke insert, update on public.device_tokens from authenticated;
grant select, delete on public.device_tokens to authenticated;

create or replace function public.upsert_device_token(
    p_user_id uuid,
    p_token text,
    p_platform text default 'ios',
    p_environment text default 'production'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller_id uuid := auth.uid();
    result_id uuid;
begin
    if caller_id is null or p_user_id is distinct from caller_id then
        raise exception 'Device registration requires the owning account' using errcode = '42501';
    end if;
    if p_token is null or length(btrim(p_token)) = 0 or length(p_token) > 512
       or p_platform is null or p_platform not in ('ios', 'android')
       or p_environment is null or p_environment not in ('sandbox', 'production') then
        raise exception 'Invalid device registration' using errcode = '22023';
    end if;

    insert into public.device_tokens (user_id, token, platform, environment, verified_at)
    values (caller_id, p_token, p_platform, p_environment, now())
    on conflict (token) do update set
        user_id = caller_id,
        platform = excluded.platform,
        environment = excluded.environment,
        verified_at = now(),
        updated_at = now()
    returning id into result_id;

    return result_id;
end;
$$;

revoke all on function public.upsert_device_token(uuid, text, text, text) from public, anon;
grant execute on function public.upsert_device_token(uuid, text, text, text) to authenticated;
