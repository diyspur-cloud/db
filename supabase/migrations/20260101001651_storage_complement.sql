-- Source: SDDBD2.md.
insert into storage.buckets (id, name, public) values
  ('journal-media',    'journal-media',    false),
  ('chapter-extras',   'chapter-extras',   false),
  ('feed-media',       'feed-media',       true),
  ('newsletter-assets','newsletter-assets',true),
  ('social-cards',     'social-cards',     true),
  ('ebooks',           'ebooks',           false)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, public = EXCLUDED.public;

-- Diário: usuário só acessa o próprio diretório (paths = user_id/...)
DROP POLICY IF EXISTS "journal_media_own_read" ON storage.objects;
CREATE POLICY "journal_media_own_read" ON storage.objects for select
  using (
    bucket_id = 'journal-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
DROP POLICY IF EXISTS "journal_media_own_write" ON storage.objects;
CREATE POLICY "journal_media_own_write" ON storage.objects for insert
  with check (
    bucket_id = 'journal-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
DROP POLICY IF EXISTS "journal_media_own_update" ON storage.objects;
CREATE POLICY "journal_media_own_update" ON storage.objects for update
  using (
    bucket_id = 'journal-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- Extras de capítulo: leitura por qualquer autenticado; escrita admin
DROP POLICY IF EXISTS "chapter_extras_read_auth" ON storage.objects;
CREATE POLICY "chapter_extras_read_auth" ON storage.objects for select
  using (bucket_id = 'chapter-extras' and auth.role() = 'authenticated');
DROP POLICY IF EXISTS "chapter_extras_admin_write" ON storage.objects;
CREATE POLICY "chapter_extras_admin_write" ON storage.objects for all
  using (bucket_id = 'chapter-extras' and public.is_admin())
  with check (bucket_id = 'chapter-extras' and public.is_admin());

-- Feed media: leitura pública; escrita pelo autor
DROP POLICY IF EXISTS "feed_media_read" ON storage.objects;
CREATE POLICY "feed_media_read" ON storage.objects for select
  using (bucket_id = 'feed-media');
DROP POLICY IF EXISTS "feed_media_author_write" ON storage.objects;
CREATE POLICY "feed_media_author_write" ON storage.objects for insert
  with check (
    bucket_id = 'feed-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
DROP POLICY IF EXISTS "feed_media_author_update" ON storage.objects;
CREATE POLICY "feed_media_author_update" ON storage.objects for update
  using (
    bucket_id = 'feed-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- Assets de newsletter: leitura pública; escrita admin
DROP POLICY IF EXISTS "newsletter_assets_read" ON storage.objects;
CREATE POLICY "newsletter_assets_read" ON storage.objects for select
  using (bucket_id = 'newsletter-assets');
DROP POLICY IF EXISTS "newsletter_assets_admin" ON storage.objects;
CREATE POLICY "newsletter_assets_admin" ON storage.objects for all
  using (bucket_id = 'newsletter-assets' and public.is_admin())
  with check (bucket_id = 'newsletter-assets' and public.is_admin());

-- Cards sociais: leitura pública; escrita pelo autor
DROP POLICY IF EXISTS "social_cards_read" ON storage.objects;
CREATE POLICY "social_cards_read" ON storage.objects for select
  using (bucket_id = 'social-cards');
DROP POLICY IF EXISTS "social_cards_author_write" ON storage.objects;
CREATE POLICY "social_cards_author_write" ON storage.objects for insert
  with check (
    bucket_id = 'social-cards'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- Ebooks: leitura autenticada com URL assinada; upload admin
DROP POLICY IF EXISTS "ebooks_read_auth" ON storage.objects;
CREATE POLICY "ebooks_read_auth" ON storage.objects for select
  using (bucket_id = 'ebooks' and auth.role() = 'authenticated');
DROP POLICY IF EXISTS "ebooks_admin_write" ON storage.objects;
CREATE POLICY "ebooks_admin_write" ON storage.objects for all
  using (bucket_id = 'ebooks' and public.is_admin())
  with check (bucket_id = 'ebooks' and public.is_admin());
