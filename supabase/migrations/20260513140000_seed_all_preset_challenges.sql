-- Clean up user-created duplicate preset challenges (non-seeded rows)
-- and seed all community challenges as shared rows everyone joins.

-- Delete duplicate user-created Squat Squad rows (keep none — will re-seed below)
delete from public.challenge_participants
where challenge_id in (
    select id from public.challenges
    where title = 'Squat Squad' and is_preset = false
);
delete from public.challenges
where title = 'Squat Squad' and is_preset = false;

-- Delete other user-created preset duplicates
delete from public.challenge_participants
where challenge_id in (
    select id from public.challenges
    where is_preset = false
    and title in (
        '30-Day Warrior', 'Weekend Warrior', '21-Day Habit Builder',
        '100K Club', 'Volume Rookie', '50K in 2 Weeks',
        'Pull-Up Master', 'Push-Up Hero', 'Bench Press Beast',
        '7-Day Streak', 'Iron Will'
    )
);
delete from public.challenges
where is_preset = false
and title in (
    '30-Day Warrior', 'Weekend Warrior', '21-Day Habit Builder',
    '100K Club', 'Volume Rookie', '50K in 2 Weeks',
    'Pull-Up Master', 'Push-Up Hero', 'Bench Press Beast',
    '7-Day Streak', 'Iron Will'
);

-- Seed all community challenges as shared preset rows.
-- Goals are science-based and achievable for labeled difficulty.
-- end_date = 10 years so they are effectively evergreen.

-- WORKOUT COUNT

insert into public.challenges (title, challenge_type, goal_metric, goal_value, start_date, end_date, creator_id, is_preset, is_public, difficulty, description)
select '30-Day Warrior', 'workout_count', 'workouts', 20, now(), now() + interval '10 years', null, true, true, 'intermediate',
'Complete 20 workouts in 30 days. That is 5 per week — consistent without being excessive.'
where not exists (select 1 from public.challenges where title = '30-Day Warrior' and is_preset = true);

insert into public.challenges (title, challenge_type, goal_metric, goal_value, start_date, end_date, creator_id, is_preset, is_public, difficulty, description)
select 'Weekend Warrior', 'workout_count', 'workouts', 6, now(), now() + interval '10 years', null, true, true, 'beginner',
'Work out 6 weekends this month. Two sessions per weekend — build the habit without the weekday pressure.'
where not exists (select 1 from public.challenges where title = 'Weekend Warrior' and is_preset = true);

insert into public.challenges (title, challenge_type, goal_metric, goal_value, start_date, end_date, creator_id, is_preset, is_public, difficulty, description)
select '21-Day Habit Builder', 'workout_count', 'workouts', 12, now(), now() + interval '10 years', null, true, true, 'intermediate',
'Complete 12 workouts in 21 days. Four per week — enough to build a real habit.'
where not exists (select 1 from public.challenges where title = '21-Day Habit Builder' and is_preset = true);

-- VOLUME

insert into public.challenges (title, challenge_type, goal_metric, goal_value, start_date, end_date, creator_id, is_preset, is_public, difficulty, description)
select '50K Club', 'total_volume', 'kg', 50000, now(), now() + interval '10 years', null, true, true, 'advanced',
'Lift 50,000 kg total volume this month. Around 12,500 kg per week across all strength workouts.'
where not exists (select 1 from public.challenges where title = '50K Club' and is_preset = true);

insert into public.challenges (title, challenge_type, goal_metric, goal_value, start_date, end_date, creator_id, is_preset, is_public, difficulty, description)
select 'Volume Starter', 'total_volume', 'kg', 15000, now(), now() + interval '10 years', null, true, true, 'beginner',
'Lift 15,000 kg total this month. Around 500 kg per workout — achievable in just a few sets.'
where not exists (select 1 from public.challenges where title = 'Volume Starter' and is_preset = true);

insert into public.challenges (title, challenge_type, goal_metric, goal_value, start_date, end_date, creator_id, is_preset, is_public, difficulty, description)
select 'Volume Builder', 'total_volume', 'kg', 30000, now(), now() + interval '10 years', null, true, true, 'intermediate',
'Lift 30,000 kg total this month. A solid monthly volume target for consistent strength training.'
where not exists (select 1 from public.challenges where title = 'Volume Builder' and is_preset = true);

-- SPECIFIC EXERCISE (goals are total reps logged in-app)

insert into public.challenges (title, challenge_type, goal_metric, goal_value, start_date, end_date, creator_id, is_preset, is_public, difficulty, description)
select 'Pull-Up Progression', 'specific_exercise', 'pull-ups', 50, now(), now() + interval '10 years', null, true, true, 'intermediate',
'Log 50 pull-up reps in 7 days. Around 7 per day — hit it in 2-3 sessions.'
where not exists (select 1 from public.challenges where title = 'Pull-Up Progression' and is_preset = true);

insert into public.challenges (title, challenge_type, goal_metric, goal_value, start_date, end_date, creator_id, is_preset, is_public, difficulty, description)
select 'Push-Up Builder', 'specific_exercise', 'push-ups', 100, now(), now() + interval '10 years', null, true, true, 'beginner',
'Log 100 push-up reps in 7 days. Around 14 per day — 3 sets of 5 twice a day.'
where not exists (select 1 from public.challenges where title = 'Push-Up Builder' and is_preset = true);

insert into public.challenges (title, challenge_type, goal_metric, goal_value, start_date, end_date, creator_id, is_preset, is_public, difficulty, description)
select 'Squat Month', 'specific_exercise', 'squats', 300, now(), now() + interval '10 years', null, true, true, 'intermediate',
'Log 300 squat reps this month. Around 10 per day — 3 sets of 10 three times a week.'
where not exists (select 1 from public.challenges where title = 'Squat Month' and is_preset = true);

insert into public.challenges (title, challenge_type, goal_metric, goal_value, start_date, end_date, creator_id, is_preset, is_public, difficulty, description)
select 'Bench Month', 'specific_exercise', 'bench-press', 80, now(), now() + interval '10 years', null, true, true, 'intermediate',
'Log 80 bench press reps this month. Around 3 sets of 8, twice a week — solid chest work.'
where not exists (select 1 from public.challenges where title = 'Bench Month' and is_preset = true);

-- STREAK

insert into public.challenges (title, challenge_type, goal_metric, goal_value, start_date, end_date, creator_id, is_preset, is_public, difficulty, description)
select '7-Day Streak', 'streak', 'days', 7, now(), now() + interval '10 years', null, true, true, 'beginner',
'Work out 7 days in a row. Build the habit.'
where not exists (select 1 from public.challenges where title = '7-Day Streak' and is_preset = true);

insert into public.challenges (title, challenge_type, goal_metric, goal_value, start_date, end_date, creator_id, is_preset, is_public, difficulty, description)
select '14-Day Streak', 'streak', 'days', 14, now(), now() + interval '10 years', null, true, true, 'advanced',
'Work out 14 days in a row. Two full weeks of consistency — no rest days allowed.'
where not exists (select 1 from public.challenges where title = '14-Day Streak' and is_preset = true);
