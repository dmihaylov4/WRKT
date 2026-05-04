-- Earned plates: full cross-device barbell collection and rack state.
-- Supersedes barbell_racked_plates after the bridge release window.

create table if not exists public.earned_plates (
    user_id uuid not null references auth.users(id) on delete cascade,
    earned_by_event text not null,
    tier_id smallint not null,
    weight_kg real not null,
    engraving_text text not null default '',
    earned_at timestamptz not null,
    source_workout_id uuid null,
    is_racked boolean not null default false,
    rack_position smallint null,
    updated_at timestamptz not null default now(),
    primary key (user_id, earned_by_event),
    constraint earned_plates_rack_position_check check (
        (is_racked = false and rack_position is null)
        or (is_racked = true and rack_position between 0 and 3)
    )
);

create unique index if not exists idx_earned_plates_racked_slot
    on public.earned_plates (user_id, rack_position)
    where is_racked = true;

create or replace function public.set_earned_plates_updated_at()
returns trigger
security definer
set search_path = public
language plpgsql
as $$
begin
    if new.is_racked = false then
        new.rack_position = null;
    end if;
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists set_earned_plates_updated_at on public.earned_plates;
create trigger set_earned_plates_updated_at
    before update on public.earned_plates
    for each row
    execute function public.set_earned_plates_updated_at();

create or replace function public.can_view_user_earned_plates(target_user_id uuid)
returns boolean
security definer
set search_path = public
language sql
stable
as $$
    select target_user_id = auth.uid()
        or exists (
            select 1
            from public.friendships f
            where f.status = 'accepted'
              and (
                (f.user_id = auth.uid() and f.friend_id = target_user_id)
                or (f.friend_id = auth.uid() and f.user_id = target_user_id)
              )
        );
$$;

alter table public.earned_plates enable row level security;

drop policy if exists "earned plates owner read" on public.earned_plates;
create policy "earned plates owner read"
    on public.earned_plates
    for select
    using (auth.uid() = user_id);

drop policy if exists "earned plates owner insert" on public.earned_plates;
create policy "earned plates owner insert"
    on public.earned_plates
    for insert
    with check (auth.uid() = user_id);

drop policy if exists "earned plates owner update" on public.earned_plates;
create policy "earned plates owner update"
    on public.earned_plates
    for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "earned plates owner delete" on public.earned_plates;
create policy "earned plates owner delete"
    on public.earned_plates
    for delete
    using (auth.uid() = user_id);

drop policy if exists "friends can view racked earned plates" on public.earned_plates;
create policy "friends can view racked earned plates"
    on public.earned_plates
    for select
    using (
        is_racked = true
        and public.can_view_user_earned_plates(user_id)
    );

grant select, insert, update, delete on public.earned_plates to authenticated;
revoke execute on function public.set_earned_plates_updated_at() from public, anon, authenticated;
revoke execute on function public.can_view_user_earned_plates(uuid) from public, anon;
grant execute on function public.can_view_user_earned_plates(uuid) to authenticated;

comment on table public.earned_plates is
    'Full earned barbell plate collection with rack state, keyed by user and earned event.';
