-- Preserve friend barbell room cosmetics even when no racked plate rows are returned.

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
    from public.barbell_customization_settings s
    left join public.earned_plates p
      on p.user_id = s.user_id
     and p.is_racked = true
    where s.user_id = owner_id
    order by p.rack_position asc nulls last, p.earned_at desc;
end;
$$;

revoke execute on function public.get_friend_barbell_showcase(uuid) from public, anon;
grant execute on function public.get_friend_barbell_showcase(uuid) to authenticated;

comment on function public.get_friend_barbell_showcase(uuid) is
    'Friend-safe barbell room read. Returns room cosmetics even when no racked plates are available.';
