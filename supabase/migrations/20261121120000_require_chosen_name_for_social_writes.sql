-- PROPOSED, NOT APPLIED. Applying it is the owner's decision.
--
-- Accounts created through Sign in with Apple or Google get their profile from the new-user
-- trigger (public.handle_new_user, defined in the dashboard, not in this repo) with display name
-- 'User' and username 'user_' || left(id::text, 8). The app (from feat/name-after-apple on) keeps
-- such an account out of Social until it chooses a name, and never auto-posts for it. App builds
-- older than that, including the current App Store build, still let it post, like, comment,
-- send friend requests, start battles and join challenges.
--
-- This migration closes the same doors on the server, for every app version:
--   1. public.profile_has_placeholder_name(id, username, display_name): the same test as
--      ProfileNamePolicy.isPlaceholder in the app (keep the two in step).
--   2. public.require_chosen_name(): a BEFORE INSERT trigger that rejects the row with
--      SQLSTATE 42501 and message 'choose_name_required' when the calling account (auth.uid())
--      still has a placeholder name. Calls without a user (service role, maintenance, cascades)
--      pass, as do accounts without a profile row.
--   3. The trigger on the tables a person writes to when being social: workout_posts,
--      post_likes, post_comments, friendships (new requests only; accepting, declining and
--      removing are updates and deletes, and stay open), battles and challenge_participants.
--
-- It changes no data and does not touch handle_new_user. The app works without it.
-- Effect on an old app build for a placeholder account: automatic posts fail quietly (they
-- are logged and dropped), a manual post, like, comment, friend request or battle shows that
-- build's usual error. Setting a display name in Edit Profile (available in old builds) ends the
-- placeholder state and reopens everything.
--
-- Before applying: check the live handle_new_user really produces this shape
--   select pg_get_functiondef('public.handle_new_user'::regprocedure);
-- and count who would be affected
--   select count(*) from public.profiles
--   where public.profile_has_placeholder_name(id, username, display_name);
-- (run the CREATE FUNCTION below first, or inline its expression).

create or replace function public.profile_has_placeholder_name(
    p_id uuid,
    p_username text,
    p_display_name text
)
returns boolean
language sql
immutable
set search_path = ''
as $$
    select
        -- The usernames the app's OAuth setup check already rejects.
        coalesce(char_length(p_username), 0) < 3
        or lower(p_username) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        -- The made-up username for this id, with a display name that tells nobody who it is.
        or (
            lower(btrim(p_username)) = 'user_' || left(p_id::text, 8)
            and (
                nullif(btrim(coalesce(p_display_name, '')), '') is null
                or lower(btrim(p_display_name)) = 'user'
                or lower(btrim(p_display_name)) = lower(btrim(p_username))
            )
        );
$$;

create or replace function public.require_chosen_name()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller_id uuid := auth.uid();
    caller_username text;
    caller_display_name text;
begin
    if caller_id is null then
        return new;
    end if;

    select p.username, p.display_name
      into caller_username, caller_display_name
      from public.profiles p
     where p.id = caller_id;

    if not found then
        return new;
    end if;

    if public.profile_has_placeholder_name(caller_id, caller_username, caller_display_name) then
        raise exception 'choose_name_required'
            using errcode = '42501',
                  hint = 'Choose a display name and username in the app before using social features.';
    end if;

    return new;
end;
$$;

revoke all on function public.require_chosen_name() from public, anon, authenticated;
revoke all on function public.profile_has_placeholder_name(uuid, text, text) from public, anon;

drop trigger if exists require_chosen_name on public.workout_posts;
create trigger require_chosen_name
    before insert on public.workout_posts
    for each row execute function public.require_chosen_name();

drop trigger if exists require_chosen_name on public.post_likes;
create trigger require_chosen_name
    before insert on public.post_likes
    for each row execute function public.require_chosen_name();

drop trigger if exists require_chosen_name on public.post_comments;
create trigger require_chosen_name
    before insert on public.post_comments
    for each row execute function public.require_chosen_name();

drop trigger if exists require_chosen_name on public.friendships;
create trigger require_chosen_name
    before insert on public.friendships
    for each row execute function public.require_chosen_name();

drop trigger if exists require_chosen_name on public.battles;
create trigger require_chosen_name
    before insert on public.battles
    for each row execute function public.require_chosen_name();

drop trigger if exists require_chosen_name on public.challenge_participants;
create trigger require_chosen_name
    before insert on public.challenge_participants
    for each row execute function public.require_chosen_name();
