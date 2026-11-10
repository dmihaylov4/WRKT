-- Minimal production-shaped fixture for isolated Postgres only.
-- The test runner creates and drops a dedicated database; never run on production.
create schema if not exists auth;
create or replace function auth.uid() returns uuid language sql stable as $$
    select coalesce(
        nullif(current_setting('request.jwt.claim.sub', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
    )::uuid;
$$;
grant usage on schema auth to anon, authenticated;

create table public.profiles (id uuid primary key, display_name text, username text);
insert into public.profiles(id) values
    ('11111111-1111-1111-1111-111111111111'),
    ('22222222-2222-2222-2222-222222222222'),
    ('33333333-3333-3333-3333-333333333333');

create table public.device_tokens (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    token text not null unique,
    platform text not null default 'ios',
    environment text not null default 'production',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
alter table public.device_tokens enable row level security;
grant all on public.device_tokens to anon, authenticated, service_role;
create policy tokens_select on public.device_tokens for select using (auth.uid() = user_id);
create policy tokens_insert on public.device_tokens for insert with check (auth.uid() = user_id);
create policy tokens_update on public.device_tokens for update using (auth.uid() = user_id);
create policy tokens_delete on public.device_tokens for delete using (auth.uid() = user_id);
insert into public.device_tokens (user_id, token) values ('11111111-1111-1111-1111-111111111111', 'legacy-token');

create table public.friendships (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    friend_id uuid not null references public.profiles(id) on delete cascade,
    status text not null default 'pending' check (status in ('pending', 'accepted', 'blocked')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    muted_notifications boolean default false,
    unique (user_id, friend_id),
    check (user_id <> friend_id)
);
alter table public.friendships enable row level security;
grant all on public.friendships to anon, authenticated, service_role;
create policy friendships_select on public.friendships for select
    using (auth.uid() in (user_id, friend_id) or status = 'accepted');
create policy friendships_insert on public.friendships for insert with check (auth.uid() = user_id);
create policy friendships_update on public.friendships for update using (auth.uid() in (user_id, friend_id));
create policy friendships_delete on public.friendships for delete using (auth.uid() in (user_id, friend_id));

create table public.virtual_runs (
    id uuid default gen_random_uuid() not null primary key,
    inviter_id uuid not null,
    invitee_id uuid not null,
    status text default 'pending'::text not null,
    started_at timestamp with time zone,
    ended_at timestamp with time zone,
    created_at timestamp with time zone default now(),
    inviter_distance_m double precision,
    inviter_duration_s integer,
    inviter_avg_pace_sec_per_km integer,
    inviter_avg_heart_rate integer,
    invitee_distance_m double precision,
    invitee_duration_s integer,
    invitee_avg_pace_sec_per_km integer,
    invitee_avg_heart_rate integer,
    winner_id uuid,
    inviter_route_uploaded boolean default false,
    invitee_route_uploaded boolean default false,
    expires_at timestamp with time zone
);
alter table public.virtual_runs enable row level security;
grant all on public.virtual_runs to anon, authenticated, service_role;
create policy "Users can view their own runs" on public.virtual_runs for select using (((auth.uid() = inviter_id) OR (auth.uid() = invitee_id)));
create policy "Users can create runs they invite" on public.virtual_runs for insert with check ((auth.uid() = inviter_id));
create policy "Users can update their own runs" on public.virtual_runs for update using (((auth.uid() = inviter_id) OR (auth.uid() = invitee_id)));
create table public.workout_posts (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id),
    caption text, workout_data jsonb, workout_data_list jsonb,
    images jsonb, visibility text not null, post_type text not null
);
create table public.post_participants (post_id uuid references public.workout_posts(id), user_id uuid, vr_stats jsonb);
alter table public.workout_posts enable row level security;
grant select on public.workout_posts to anon, authenticated;
create policy posts_read on public.workout_posts for select using (
    user_id = auth.uid() or visibility = 'public' or
    (visibility = 'friends' and exists (select 1 from public.friendships f
        where f.status = 'accepted' and
            ((f.user_id = auth.uid() and f.friend_id = workout_posts.user_id)
            or (f.friend_id = auth.uid() and f.user_id = workout_posts.user_id))))
);
create table public.notifications (
    id uuid primary key default gen_random_uuid(), user_id uuid, type text, actor_id uuid, target_id uuid,
    metadata jsonb default '{}', read boolean default false, created_at timestamptz default now()
);
alter table public.notifications enable row level security;
grant all on public.notifications to anon, authenticated;
create policy "Allow authenticated inserts" on public.notifications for insert to authenticated with check (true);
create policy notifications_read on public.notifications for select using (user_id = auth.uid());
create policy notifications_update on public.notifications for update using (user_id = auth.uid());
create policy notifications_delete on public.notifications for delete using (user_id = auth.uid());
create unique index notification_like_dedupe on public.notifications(user_id, type, actor_id, target_id) where type = 'post_like';

create table public.post_likes (
    id uuid primary key default gen_random_uuid(), post_id uuid references public.workout_posts,
    user_id uuid, created_at timestamptz default now(), unique(post_id, user_id)
);
create table public.post_comments (
    id uuid primary key default gen_random_uuid(), post_id uuid references public.workout_posts,
    user_id uuid, content text not null, parent_comment_id uuid references public.post_comments,
    created_at timestamptz default now(), updated_at timestamptz default now()
);
create table public.comment_mentions (
    id uuid primary key default gen_random_uuid(), comment_id uuid references public.post_comments,
    mentioned_user_id uuid, created_at timestamptz default now()
);
alter table public.post_likes enable row level security;
alter table public.post_comments enable row level security;
alter table public.comment_mentions enable row level security;
grant all on public.post_likes, public.post_comments, public.comment_mentions to anon, authenticated;
create policy "Users can create their own likes" on public.post_likes for insert with check (auth.uid() = user_id);
create policy "Users can view all likes" on public.post_likes for select using (true);
create policy "Users can create comments" on public.post_comments for insert with check (auth.uid() = user_id);
create policy comments_read on public.post_comments for select using (exists (select 1 from public.workout_posts p where p.id = post_id));
create policy comments_update on public.post_comments for update using (user_id = auth.uid());
create policy "Users can create mentions" on public.comment_mentions for insert with check (auth.uid() is not null);
create policy "Anyone can read comment mentions" on public.comment_mentions for select using (true);

-- Server notification routines are represented for the grant regression checks.
create table public.challenges (id uuid primary key, title text, goal_value numeric);
create table public.challenge_participants (
    id uuid primary key default gen_random_uuid(), challenge_id uuid references public.challenges,
    user_id uuid, current_progress numeric, progress_percentage integer default 0, completed boolean default false
);
alter table public.challenge_participants enable row level security;
grant select, update on public.challenge_participants to authenticated;
create policy participant_read on public.challenge_participants for select using (true);
create policy participant_update on public.challenge_participants for update using (user_id = auth.uid());
create function public.send_battle_completed_notifications(p_battle_id uuid) returns void language sql as 'select';
create function public.send_battle_ending_soon_notifications() returns void language sql as 'select';

create schema private;
create table private.push_config (key text primary key, value text not null);
insert into private.push_config values
    ('push_function_url', 'https://example.test/send-push'),
    ('service_role_key', 'old-credential-must-not-be-used'),
    ('push_dispatch_secret', 'isolated-dispatch-secret');
create schema net;
create table net.requests (url text, headers jsonb, body jsonb);
create function net.http_post(url text, headers jsonb, body jsonb) returns bigint language plpgsql as $$
begin
    insert into net.requests values(url, headers, body);
    return 1;
end;
$$;

create schema tests;
create schema storage;
grant usage on schema storage to anon, authenticated;
create table storage.buckets (
    id text primary key, public boolean, file_size_limit bigint, allowed_mime_types text[]
);
insert into storage.buckets(id, public) values ('user-images', true);
create table storage.objects (
    id uuid primary key default gen_random_uuid(), bucket_id text, name text,
    unique(bucket_id, name)
);
alter table storage.objects enable row level security;
grant all on storage.objects to anon, authenticated;
create policy "Allow authenticated users full access to user-images"
    on storage.objects for all to authenticated
    using (bucket_id = 'user-images') with check (bucket_id = 'user-images');
create policy "Allow public read access to user-images"
    on storage.objects for select using (bucket_id = 'user-images');

grant usage on schema tests to anon, authenticated;
create function tests.expect_error(command text, expected_state text) returns void language plpgsql as $$
begin
    begin
        execute command;
    exception when others then
        if sqlstate = expected_state then return; end if;
        raise;
    end;
    raise exception 'Expected SQLSTATE %, but statement succeeded', expected_state;
end;
$$;
