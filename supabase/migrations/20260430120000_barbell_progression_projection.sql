-- Barbell progression projection and append-only biography events.

alter table public.earned_plates
    add column if not exists lift_type_id text null,
    add column if not exists current_tier text not null default 'iron',
    add column if not exists workouts_used_count integer not null default 0,
    add column if not exists pr_count integer not null default 0,
    add column if not exists chalk_use_count integer not null default 0,
    add column if not exists grip_wear_count integer not null default 0,
    add column if not exists press_use_count integer not null default 0,
    add column if not exists first_earned_at timestamptz null,
    add column if not exists last_used_at timestamptz null;

update public.earned_plates
set first_earned_at = coalesce(first_earned_at, earned_at)
where first_earned_at is null;

alter table public.earned_plates
    alter column first_earned_at set not null;

alter table public.earned_plates
    drop constraint if exists earned_plates_current_tier_check;

alter table public.earned_plates
    add constraint earned_plates_current_tier_check
    check (current_tier in ('iron', 'steel', 'chrome', 'gold', 'obsidian', 'cosmic'));

create table if not exists public.barbell_plate_events (
    user_id uuid not null references auth.users(id) on delete cascade,
    stable_key text not null,
    earned_by_event text not null,
    kind text not null,
    occurred_at timestamptz not null,
    workout_id uuid null,
    tier text null,
    milestone_id text null,
    summary text not null,
    is_silent boolean not null default true,
    created_at timestamptz not null default now(),
    primary key (user_id, stable_key),
    constraint barbell_plate_events_kind_check check (
        kind in ('earned', 'tieredUp', 'personalRecord', 'milestoneVolume', 'anniversary')
    ),
    constraint barbell_plate_events_tier_check check (
        tier is null or tier in ('iron', 'steel', 'chrome', 'gold', 'obsidian', 'cosmic')
    )
);

create index if not exists idx_barbell_plate_events_plate
    on public.barbell_plate_events (user_id, earned_by_event, occurred_at);

alter table public.barbell_plate_events enable row level security;

drop policy if exists "barbell plate events owner read" on public.barbell_plate_events;
create policy "barbell plate events owner read"
    on public.barbell_plate_events
    for select
    using (auth.uid() = user_id);

drop policy if exists "barbell plate events owner insert" on public.barbell_plate_events;
create policy "barbell plate events owner insert"
    on public.barbell_plate_events
    for insert
    with check (auth.uid() = user_id);

drop policy if exists "barbell plate events owner update" on public.barbell_plate_events;
create policy "barbell plate events owner update"
    on public.barbell_plate_events
    for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "barbell plate events owner delete" on public.barbell_plate_events;
create policy "barbell plate events owner delete"
    on public.barbell_plate_events
    for delete
    using (auth.uid() = user_id);

grant select, insert, update, delete on public.barbell_plate_events to authenticated;

comment on table public.barbell_plate_events is
    'Append-only biography ledger for earned barbell plates, idempotent by stable event key.';
