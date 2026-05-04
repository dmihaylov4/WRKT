-- Use display_loadout as the canonical friend showcase order.
-- App clients now sync display_loadout plate keys as earned_by_event values, because local
-- SwiftData plate UUIDs are device-local and cannot be resolved by another device.

create or replace function public.get_friend_barbell_showcase(owner_id uuid)
returns table (
    bar_skin_id text,
    room_theme_id text,
    rack_style_id text,
    collar_id text,
    banner_id text,
    show_plate_engravings boolean,
    room_name text,
    room_motto text,
    display_loadout jsonb,
    tier_id smallint,
    weight_kg real,
    engraving_text text,
    earned_by_event text,
    lift_type_id text,
    current_tier text,
    chalk_use_count integer,
    grip_wear_count integer,
    press_use_count integer,
    first_earned_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
    if owner_id = auth.uid() then
        return;
    end if;

    if not exists (
        select 1
        from public.friendships f
        where f.status = 'accepted'
          and (
            (f.user_id = auth.uid() and f.friend_id = owner_id)
            or (f.friend_id = auth.uid() and f.user_id = owner_id)
          )
    ) then
        return;
    end if;

    return query
    with settings as (
        select *
        from public.barbell_customization_settings
        where user_id = owner_id
    ),
    loadout_keys as (
        select key, ordinality::integer as sort_position
        from settings s,
        jsonb_array_elements_text(coalesce(s.display_loadout -> 'onBar', '[]'::jsonb))
            with ordinality as keys(key, ordinality)
    ),
    loadout_plates as (
        select
            p.*,
            k.sort_position
        from loadout_keys k
        join public.earned_plates p
          on p.user_id = owner_id
         and p.earned_by_event = k.key
    ),
    fallback_plates as (
        select
            p.*,
            p.rack_position::integer as sort_position
        from public.earned_plates p
        where p.user_id = owner_id
          and p.is_racked = true
          and not exists (select 1 from loadout_plates)
    ),
    selected_plates as (
        select * from loadout_plates
        union all
        select * from fallback_plates
    )
    select
        s.bar_skin_id,
        s.room_theme_id,
        s.rack_style_id,
        s.collar_id,
        s.banner_id,
        s.show_plate_engravings,
        s.room_name,
        s.room_motto,
        s.display_loadout,
        p.tier_id,
        p.weight_kg,
        case
            when p.earned_by_event is null then null
            when s.show_plate_engravings then p.engraving_text
            else ''
        end,
        p.earned_by_event,
        p.lift_type_id,
        p.current_tier,
        p.chalk_use_count,
        p.grip_wear_count,
        p.press_use_count,
        p.first_earned_at
    from settings s
    left join selected_plates p on true
    order by p.sort_position asc nulls last, p.earned_at desc;
end;
$$;

revoke execute on function public.get_friend_barbell_showcase(uuid) from public, anon;
grant execute on function public.get_friend_barbell_showcase(uuid) to authenticated;

comment on function public.get_friend_barbell_showcase(uuid) is
    'Friend-safe barbell room read. Uses display_loadout earned_by_event keys first, then falls back to racked plate state.';
