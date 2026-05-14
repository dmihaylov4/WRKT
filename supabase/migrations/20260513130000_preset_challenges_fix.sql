-- Fix preset challenge seeding (creator_id was missing, HIIT Forge end_date was too short)
-- Also adds "challenge" source to barbell_cosmetic_unlocks constraint.

-- Allow null creator_id for system preset challenges
alter table public.challenges
    alter column creator_id drop not null;

-- Add "challenge" as valid unlock source
alter table public.barbell_cosmetic_unlocks
    drop constraint if exists barbell_cosmetic_unlocks_source_check;

alter table public.barbell_cosmetic_unlocks
    add constraint barbell_cosmetic_unlocks_source_check check (
        source in ('default', 'workout', 'seasonal', 'setBonus', 'hidden', 'migration', 'support', 'challenge')
    );

-- First Rep: complete any 1 workout — evergreen, no expiry
insert into public.challenges (
  title,
  challenge_type,
  goal_metric,
  goal_value,
  start_date,
  end_date,
  creator_id,
  is_preset,
  is_public,
  difficulty,
  description
)
select
  'First Rep',
  'workout_count',
  'workout_count',
  1,
  now(),
  now() + interval '10 years',
  null,
  true,
  true,
  'beginner',
  'Log your first workout and earn the exclusive VOLIA bar skin.'
where not exists (
  select 1 from public.challenges
  where title = 'First Rep' and is_preset = true
);

-- HIIT Forge: 150 qualifying minutes — 30-day rolling window
insert into public.challenges (
  title,
  challenge_type,
  goal_metric,
  goal_value,
  start_date,
  end_date,
  creator_id,
  is_preset,
  is_public,
  difficulty,
  description
)
select
  'HIIT Forge',
  'custom',
  'conditioning_minutes',
  150,
  now(),
  now() + interval '10 years',
  null,
  true,
  true,
  'intermediate',
  'Log 150 minutes of HIIT or functional training. Sessions under 10 min don''t count.'
where not exists (
  select 1 from public.challenges
  where title = 'HIIT Forge' and is_preset = true
);
