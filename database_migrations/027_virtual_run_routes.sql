-- 027: Virtual Run Route Storage
-- Adds route upload flags to virtual_runs + storage bucket RLS for route JSON files

-- Flags so each user can signal route upload completion
ALTER TABLE virtual_runs ADD COLUMN IF NOT EXISTS inviter_route_uploaded BOOLEAN DEFAULT FALSE;
ALTER TABLE virtual_runs ADD COLUMN IF NOT EXISTS invitee_route_uploaded BOOLEAN DEFAULT FALSE;

-- Storage bucket: virtual-run-routes (create via Supabase dashboard as PRIVATE bucket)
-- File naming convention: {runId}/{userId}.json

-- Upload own route (participants can only upload their own route file)
CREATE POLICY "Users can upload own route" ON storage.objects FOR INSERT
WITH CHECK (
    bucket_id = 'virtual-run-routes'
    AND (storage.foldername(name))[1] IN (
        SELECT id::text FROM virtual_runs
        WHERE inviter_id = auth.uid() OR invitee_id = auth.uid()
    )
    AND (storage.filename(name)) = auth.uid()::text || '.json'
);

-- Read routes from runs the user participates in
CREATE POLICY "Participants can read routes" ON storage.objects FOR SELECT
USING (
    bucket_id = 'virtual-run-routes'
    AND (storage.foldername(name))[1] IN (
        SELECT id::text FROM virtual_runs
        WHERE inviter_id = auth.uid() OR invitee_id = auth.uid()
    )
);
