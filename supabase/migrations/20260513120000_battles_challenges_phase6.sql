-- Phase 6: battles/challenges preset seeds and battle score RLS hardening.

insert into public.challenges (
  title,
  challenge_type,
  goal_metric,
  goal_value,
  start_date,
  end_date,
  is_preset,
  is_public,
  difficulty
)
select
  'First Rep',
  'workout_count',
  'workout_count',
  1,
  now(),
  now() + interval '10 years',
  true,
  true,
  'beginner'
where not exists (
  select 1
  from public.challenges
  where title = 'First Rep'
    and challenge_type = 'workout_count'
    and goal_metric = 'workout_count'
    and is_preset = true
);

insert into public.challenges (
  title,
  challenge_type,
  goal_metric,
  goal_value,
  start_date,
  end_date,
  is_preset,
  is_public,
  difficulty
)
select
  'HIIT Forge',
  'custom',
  'conditioning_minutes',
  150,
  now(),
  now() + interval '7 days',
  true,
  true,
  'intermediate'
where not exists (
  select 1
  from public.challenges
  where title = 'HIIT Forge'
    and challenge_type = 'custom'
    and goal_metric = 'conditioning_minutes'
    and is_preset = true
);

drop policy if exists "challenger_score_update" on public.battles;
create policy "challenger_score_update"
on public.battles
for update
using (auth.uid() = challenger_id)
with check (auth.uid() = challenger_id);

drop policy if exists "opponent_score_update" on public.battles;
create policy "opponent_score_update"
on public.battles
for update
using (auth.uid() = opponent_id)
with check (auth.uid() = opponent_id);

create or replace function public.enforce_battle_score_owner_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
begin
  if actor_id is null then
    return new;
  end if;

  if actor_id = old.challenger_id
    and new.opponent_score is distinct from old.opponent_score then
    raise exception 'challengers cannot update opponent_score'
      using errcode = '42501';
  end if;

  if actor_id = old.opponent_id
    and new.challenger_score is distinct from old.challenger_score then
    raise exception 'opponents cannot update challenger_score'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_battle_score_owner_update on public.battles;
create trigger enforce_battle_score_owner_update
before update of challenger_score, opponent_score on public.battles
for each row
execute function public.enforce_battle_score_owner_update();
