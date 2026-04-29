create table if not exists public.shared_programs (
    id uuid primary key default gen_random_uuid(),
    creator_user_id uuid not null references auth.users(id) on delete cascade,
    name text not null,
    description text,
    structure jsonb not null,
    reschedule_policy text not null check (reschedule_policy in ('strict', 'rolling', 'flexible')),
    created_at timestamptz not null default now(),
    deleted_at timestamptz
);

create index if not exists shared_programs_creator_idx
on public.shared_programs (creator_user_id);

create table if not exists public.program_invites (
    id uuid primary key default gen_random_uuid(),
    program_id uuid not null references public.shared_programs(id) on delete cascade,
    sender_user_id uuid not null references auth.users(id) on delete cascade,
    recipient_user_id uuid not null references auth.users(id) on delete cascade,
    status text not null check (status in ('pending', 'accepted', 'declined', 'revoked')),
    created_at timestamptz not null default now(),
    responded_at timestamptz
);

create index if not exists program_invites_recipient_pending_idx
on public.program_invites (recipient_user_id, status)
where status = 'pending';

create index if not exists program_invites_sender_idx
on public.program_invites (sender_user_id);

create unique index if not exists program_invites_unique_pending
on public.program_invites (program_id, sender_user_id, recipient_user_id)
where status = 'pending';

alter table public.shared_programs enable row level security;
alter table public.program_invites enable row level security;

drop policy if exists "creator inserts" on public.shared_programs;
create policy "creator inserts" on public.shared_programs
    for insert
    with check (auth.uid() = creator_user_id);

drop policy if exists "creator or invited reads" on public.shared_programs;
create policy "creator or invited reads" on public.shared_programs
    for select
    using (
        auth.uid() = creator_user_id
        or (
            deleted_at is null
            and exists (
                select 1
                from public.program_invites pi
                where pi.program_id = shared_programs.id
                  and pi.recipient_user_id = auth.uid()
                  and pi.status in ('pending', 'accepted')
            )
        )
    );

drop policy if exists "creator updates own" on public.shared_programs;
create policy "creator updates own" on public.shared_programs
    for update
    using (auth.uid() = creator_user_id)
    with check (auth.uid() = creator_user_id);

drop policy if exists "sender inserts to friends" on public.program_invites;
create policy "sender inserts to friends" on public.program_invites
    for insert
    with check (
        auth.uid() = sender_user_id
        and exists (
            select 1
            from public.friendships f
            where f.status = 'accepted'
              and (
                (f.user_id = auth.uid() and f.friend_id = recipient_user_id)
                or (f.friend_id = auth.uid() and f.user_id = recipient_user_id)
              )
        )
    );

drop policy if exists "involved parties read" on public.program_invites;
create policy "involved parties read" on public.program_invites
    for select
    using (auth.uid() = sender_user_id or auth.uid() = recipient_user_id);

drop policy if exists "involved parties update" on public.program_invites;
create policy "involved parties update" on public.program_invites
    for update
    using (auth.uid() = sender_user_id or auth.uid() = recipient_user_id);

create or replace function public.check_program_invite_transition()
returns trigger
language plpgsql
security definer
as $$
begin
    if old.program_id is distinct from new.program_id
       or old.sender_user_id is distinct from new.sender_user_id
       or old.recipient_user_id is distinct from new.recipient_user_id
       or old.created_at is distinct from new.created_at then
        raise exception 'program_invite identifying columns are immutable';
    end if;

    if old.status in ('accepted', 'declined', 'revoked') then
        raise exception 'program_invite is in terminal state %, cannot update', old.status;
    end if;

    if new.status in ('accepted', 'declined') and auth.uid() <> old.recipient_user_id then
        raise exception 'only recipient can set status to %', new.status;
    end if;

    if new.status = 'revoked' and auth.uid() <> old.sender_user_id then
        raise exception 'only sender can revoke';
    end if;

    if old.status = 'pending' and new.status <> 'pending' then
        new.responded_at := now();
    end if;

    return new;
end;
$$;

drop trigger if exists program_invite_transition_check on public.program_invites;
create trigger program_invite_transition_check
    before update on public.program_invites
    for each row execute function public.check_program_invite_transition();

create or replace function public.notify_program_invite()
returns trigger
language plpgsql
security definer
as $$
begin
    insert into public.notifications (user_id, type, actor_id, target_id, read, metadata)
    values (new.recipient_user_id, 'program_invite', new.sender_user_id, new.id, false, null);
    return new;
end;
$$;

drop trigger if exists notify_on_program_invite_insert on public.program_invites;
create trigger notify_on_program_invite_insert
    after insert on public.program_invites
    for each row execute function public.notify_program_invite();

create or replace function public.cleanup_program_invite_notification()
returns trigger
language plpgsql
security definer
as $$
begin
    if old.status = 'pending' and new.status in ('accepted', 'declined', 'revoked') then
        delete from public.notifications
        where type = 'program_invite'
          and target_id = new.id
          and read = false;
    end if;
    return new;
end;
$$;

drop trigger if exists cleanup_on_program_invite_terminal_transition on public.program_invites;
create trigger cleanup_on_program_invite_terminal_transition
    after update on public.program_invites
    for each row execute function public.cleanup_program_invite_notification();

alter publication supabase_realtime add table public.program_invites;
