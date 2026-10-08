-- Source: SDDBD2.md.
insert into storage.buckets (id, name, public) values
  ('avatars',       'avatars',       true),
  ('book-covers',   'book-covers',   true),
  ('manuscripts',   'manuscripts',   false),  -- Fellowship (P2)
  ('meeting-slides','meeting-slides',true) ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, public = EXCLUDED.public;

-- Avatares: usuário edita o próprio
DROP POLICY IF EXISTS "avatars_read" ON storage.objects;
CREATE POLICY "avatars_read" ON storage.objects for select
  using (bucket_id = 'avatars');
DROP POLICY IF EXISTS "avatars_write" ON storage.objects;
CREATE POLICY "avatars_write" ON storage.objects for insert
  with check (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);
DROP POLICY IF EXISTS "avatars_update" ON storage.objects;
CREATE POLICY "avatars_update" ON storage.objects for update
  using (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

-- Capas: admin
DROP POLICY IF EXISTS "covers_read" ON storage.objects;
CREATE POLICY "covers_read" ON storage.objects for select
  using (bucket_id = 'book-covers');
DROP POLICY IF EXISTS "covers_admin" ON storage.objects;
CREATE POLICY "covers_admin" ON storage.objects for all
  using (bucket_id = 'book-covers' and public.is_admin());
