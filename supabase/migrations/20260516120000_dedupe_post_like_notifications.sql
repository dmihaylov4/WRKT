-- Dedupe post-like notifications so unlike/relike cycles do not send repeated pushes.

with ranked as (
    select
        id,
        row_number() over (
            partition by user_id, type, actor_id, target_id
            order by created_at asc, id asc
        ) as rn
    from public.notifications
    where type = 'post_like'
      and target_id is not null
)
delete from public.notifications n
using ranked r
where n.id = r.id
  and r.rn > 1;

create unique index if not exists idx_notifications_post_like_unique
    on public.notifications (user_id, type, actor_id, target_id)
    where type = 'post_like';

create or replace function public.create_post_like_notification()
returns trigger
security definer
set search_path = public
language plpgsql
as $$
declare
    post_author_id uuid;
begin
    select user_id into post_author_id
    from public.workout_posts
    where id = new.post_id;

    if post_author_id is null or post_author_id = new.user_id then
        return new;
    end if;

    insert into public.notifications (user_id, type, actor_id, target_id, read)
    values (post_author_id, 'post_like', new.user_id, new.post_id, false)
    on conflict (user_id, type, actor_id, target_id)
    where type = 'post_like'
    do nothing;

    return new;
end;
$$;

drop trigger if exists on_post_liked on public.post_likes;
drop trigger if exists post_like_notification_trigger on public.post_likes;

create trigger on_post_liked
    after insert on public.post_likes
    for each row
    execute function public.create_post_like_notification();
