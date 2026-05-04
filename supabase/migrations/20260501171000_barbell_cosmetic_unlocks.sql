-- Durable optional barbell cosmetic ownership.
-- Append-only ownership ledger, idempotent by user and cosmetic ID.

create table if not exists public.barbell_cosmetic_unlocks (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    cosmetic_id text not null,
    unlocked_at timestamptz not null default now(),
    source text not null,
    source_workout_id uuid null,
    catalog_version text null,
    created_at timestamptz not null default now(),
    unique (user_id, cosmetic_id),
    constraint barbell_cosmetic_unlocks_source_check check (
        source in ('default', 'workout', 'seasonal', 'setBonus', 'hidden', 'migration', 'support')
    )
);

create index if not exists idx_barbell_cosmetic_unlocks_user
    on public.barbell_cosmetic_unlocks (user_id, unlocked_at desc);

alter table public.barbell_cosmetic_unlocks enable row level security;

drop policy if exists "barbell cosmetic unlocks owner read"
    on public.barbell_cosmetic_unlocks;
create policy "barbell cosmetic unlocks owner read"
    on public.barbell_cosmetic_unlocks
    for select
    using (auth.uid() = user_id);

drop policy if exists "barbell cosmetic unlocks owner insert"
    on public.barbell_cosmetic_unlocks;
create policy "barbell cosmetic unlocks owner insert"
    on public.barbell_cosmetic_unlocks
    for insert
    with check (auth.uid() = user_id);

drop policy if exists "barbell cosmetic unlocks owner update"
    on public.barbell_cosmetic_unlocks;
create policy "barbell cosmetic unlocks owner update"
    on public.barbell_cosmetic_unlocks
    for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "barbell cosmetic unlocks owner delete"
    on public.barbell_cosmetic_unlocks;
create policy "barbell cosmetic unlocks owner delete"
    on public.barbell_cosmetic_unlocks
    for delete
    using (auth.uid() = user_id);

grant select, insert, update, delete on public.barbell_cosmetic_unlocks to authenticated;

comment on table public.barbell_cosmetic_unlocks is
    'Append-only ownership ledger for optional barbell cosmetics, unique per user and cosmetic ID.';
