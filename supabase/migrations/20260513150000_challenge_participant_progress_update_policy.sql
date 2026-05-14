-- Allow users to update their own challenge participation progress.
-- Battle score updates already had explicit RLS policies; challenge progress needs the same.

drop policy if exists "challenge_participants_self_update" on public.challenge_participants;
create policy "challenge_participants_self_update"
on public.challenge_participants
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "challenge_activities_self_insert" on public.challenge_activities;
create policy "challenge_activities_self_insert"
on public.challenge_activities
for insert
with check (auth.uid() = user_id);
