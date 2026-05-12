alter table public.workout_posts
add column if not exists workout_data_list jsonb;
