-- >>> 20260101001500_realtime.sql
-- Source: SDDBD2.md. Generated idempotent migration.
-- Adicionar tabelas à publicação realtime
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'comments') THEN EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.comments'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'reactions') THEN EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.reactions'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'video_timed_comments') THEN EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.video_timed_comments'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'notifications') THEN EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'book_poll_votes') THEN EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.book_poll_votes'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'host_prompt_votes') THEN EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.host_prompt_votes'; END IF; END $$;

-- >>> 20260101001600_storage.sql
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
