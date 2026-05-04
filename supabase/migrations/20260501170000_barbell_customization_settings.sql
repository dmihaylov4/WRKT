-- Barbell customization settings.
-- Cosmetic choices are separate from earned plate/progression state.

create table if not exists public.barbell_customization_settings (
    user_id uuid primary key references auth.users(id) on delete cascade,
    bar_skin_id text not null default 'steel_default',
    room_theme_id text not null default 'dark_gym',
    rack_style_id text not null default 'matte_black',
    collar_id text null,
    banner_id text null,
    show_plate_engravings boolean not null default true,
    room_name text null,
    room_motto text null,
    display_loadout jsonb not null default '{}'::jsonb,
    updated_at timestamptz not null default now(),
    constraint barbell_customization_settings_display_loadout_object
        check (jsonb_typeof(display_loadout) = 'object'),
    constraint barbell_customization_settings_room_name_length
        check (room_name is null or char_length(room_name) <= 32),
    constraint barbell_customization_settings_room_motto_length
        check (room_motto is null or char_length(room_motto) <= 64)
);

create or replace function public.set_barbell_customization_settings_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists set_barbell_customization_settings_updated_at
    on public.barbell_customization_settings;

create trigger set_barbell_customization_settings_updated_at
    before update on public.barbell_customization_settings
    for each row
    execute function public.set_barbell_customization_settings_updated_at();

alter table public.barbell_customization_settings enable row level security;

drop policy if exists "barbell customization owner read"
    on public.barbell_customization_settings;
create policy "barbell customization owner read"
    on public.barbell_customization_settings
    for select
    using (auth.uid() = user_id);

drop policy if exists "barbell customization owner insert"
    on public.barbell_customization_settings;
create policy "barbell customization owner insert"
    on public.barbell_customization_settings
    for insert
    with check (auth.uid() = user_id);

drop policy if exists "barbell customization owner update"
    on public.barbell_customization_settings;
create policy "barbell customization owner update"
    on public.barbell_customization_settings
    for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "barbell customization owner delete"
    on public.barbell_customization_settings;
create policy "barbell customization owner delete"
    on public.barbell_customization_settings
    for delete
    using (auth.uid() = user_id);

grant select, insert, update, delete on public.barbell_customization_settings to authenticated;

revoke execute on function public.set_barbell_customization_settings_updated_at()
    from public, anon, authenticated;

comment on table public.barbell_customization_settings is
    'Per-user barbell room customization settings. Cosmetic presentation only; earned/progression state remains in earned_plates.';
