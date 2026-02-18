-- 029: Fix virtual run route storage RLS
--
-- Adds DELETE policy needed for upsert (retry uploads).
-- Also adds UPDATE policy for completeness.
-- Note: UUID case mismatch was fixed on the client side (Swift lowercased UUIDs).

-- Allow participants to delete/overwrite their own route files (needed for upsert)
CREATE POLICY "Users can delete own route" ON storage.objects FOR DELETE
USING (
    bucket_id = 'virtual-run-routes'
    AND (storage.foldername(name))[1] IN (
        SELECT id::text FROM virtual_runs
        WHERE inviter_id = auth.uid() OR invitee_id = auth.uid()
    )
    AND (storage.filename(name)) = auth.uid()::text || '.json'
);

-- Allow participants to update their own route files
CREATE POLICY "Users can update own route" ON storage.objects FOR UPDATE
USING (
    bucket_id = 'virtual-run-routes'
    AND (storage.foldername(name))[1] IN (
        SELECT id::text FROM virtual_runs
        WHERE inviter_id = auth.uid() OR invitee_id = auth.uid()
    )
    AND (storage.filename(name)) = auth.uid()::text || '.json'
);
