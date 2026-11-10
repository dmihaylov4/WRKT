drop policy "Allow authenticated users full access to user-images" on storage.objects;

-- All existing avatar objects use a UUID directory. Preserve public reads and
-- permit mutations only inside the authenticated user's directory.
create policy "Owners can upload avatars" on storage.objects
    for insert to authenticated
    with check (bucket_id = 'user-images' and lower(split_part(name, '/', 1)) = auth.uid()::text);
create policy "Owners can replace avatars" on storage.objects
    for update to authenticated
    using (bucket_id = 'user-images' and lower(split_part(name, '/', 1)) = auth.uid()::text)
    with check (bucket_id = 'user-images' and lower(split_part(name, '/', 1)) = auth.uid()::text);
create policy "Owners can delete avatars" on storage.objects
    for delete to authenticated
    using (bucket_id = 'user-images' and lower(split_part(name, '/', 1)) = auth.uid()::text);

update storage.buckets set
    file_size_limit = 10485760,
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
where id = 'user-images';
