-- Installed clients omit nil Encodable fields. Defaults retain that wire contract.
-- Required values are validated explicitly because optional arguments precede them.
create or replace function public.create_shared_post(
    p_caption text default null,
    p_visibility text default null,
    p_images jsonb default null,
    p_workout_data jsonb default null,
    p_workout_data_list jsonb default null,
    p_partner_user_id uuid default null,
    p_partner_vr_stats jsonb default null,
    p_run_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller_id uuid := auth.uid();
    post_id uuid;
begin
    if caller_id is null then
        raise exception 'Authentication required' using errcode = '42501';
    end if;
    if p_partner_user_id is null or p_partner_user_id = caller_id
       or p_visibility is null or p_visibility not in ('public', 'friends', 'private')
       or p_workout_data is null or jsonb_typeof(p_workout_data) <> 'object'
       or (p_images is not null and jsonb_typeof(p_images) <> 'array')
       or (p_workout_data_list is not null and jsonb_typeof(p_workout_data_list) <> 'array') then
        raise exception 'Invalid shared workout' using errcode = '22023';
    end if;

    if p_partner_vr_stats is null then
        if not exists (
            select 1 from public.friendships
            where ((user_id = caller_id and friend_id = p_partner_user_id)
                or (friend_id = caller_id and user_id = p_partner_user_id))
              and status = 'accepted'
        ) then
            raise exception 'The workout partner must be an accepted friend' using errcode = '42501';
        end if;
    elsif p_run_id is null or not exists (
        select 1 from public.virtual_runs
        where id = p_run_id
          and ((inviter_id = caller_id and invitee_id = p_partner_user_id)
            or (invitee_id = caller_id and inviter_id = p_partner_user_id))
    ) then
        raise exception 'Only run participants may share this workout' using errcode = '42501';
    end if;

    insert into public.workout_posts (user_id, caption, workout_data, workout_data_list, images, visibility, post_type)
    values (caller_id, p_caption, p_workout_data, p_workout_data_list, p_images, p_visibility, 'shared')
    returning id into post_id;

    insert into public.post_participants (post_id, user_id, vr_stats)
    values (post_id, p_partner_user_id, p_partner_vr_stats);

    insert into public.notifications (user_id, type, actor_id, target_id)
    values (p_partner_user_id, 'post_participant_tag', caller_id, post_id);
    return post_id;
end;
$$;

revoke all on function public.create_shared_post(text, text, jsonb, jsonb, jsonb, uuid, jsonb, uuid) from public, anon;
grant execute on function public.create_shared_post(text, text, jsonb, jsonb, jsonb, uuid, jsonb, uuid) to authenticated;
notify pgrst, 'reload schema';
