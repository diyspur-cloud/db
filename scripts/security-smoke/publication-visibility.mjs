import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { PGlite } from './node_modules/@electric-sql/pglite/dist/index.js';

const root = resolve(import.meta.dirname, '../..');
const migration = await readFile(resolve(root, 'supabase/migrations/20261009185509_restrict_future_chapter_visibility.sql'), 'utf8');
const db = new PGlite();
try {
  await db.exec(`
    CREATE ROLE anon NOLOGIN;
    CREATE ROLE authenticated NOLOGIN;
    CREATE SCHEMA auth;
    CREATE SCHEMA private;
    CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT NULL::uuid $$;
    CREATE TABLE public.seasons (id uuid PRIMARY KEY, status text NOT NULL);
    CREATE TABLE public.chapters (id uuid PRIMARY KEY, season_id uuid NOT NULL REFERENCES public.seasons(id), published_at timestamptz);
    CREATE TABLE public.meetings (id uuid PRIMARY KEY, chapter_id uuid REFERENCES public.chapters(id));
    CREATE TABLE public.quiz_questions (id uuid PRIMARY KEY, chapter_id uuid NOT NULL REFERENCES public.chapters(id), correct_idx integer NOT NULL);
    CREATE TABLE public.comments (id uuid PRIMARY KEY, chapter_id uuid NOT NULL REFERENCES public.chapters(id), user_id uuid NOT NULL, parent_id uuid, created_at timestamptz DEFAULT now(), likes_count integer DEFAULT 0, replies_count integer DEFAULT 0, is_spoiler boolean DEFAULT false, min_percent integer DEFAULT 0, content text NOT NULL, deleted_at timestamptz);
    CREATE TABLE public.user_progress (user_id uuid NOT NULL, chapter_id uuid NOT NULL, percent numeric NOT NULL DEFAULT 0);
    ALTER TABLE public.chapters ENABLE ROW LEVEL SECURITY;
    ALTER TABLE public.quiz_questions ENABLE ROW LEVEL SECURITY;
    ALTER TABLE public.meetings ENABLE ROW LEVEL SECURITY;
    CREATE POLICY chapters_read ON public.chapters FOR SELECT USING (true);
    CREATE POLICY quiz_q_read_auth ON public.quiz_questions FOR SELECT USING (true);
    CREATE POLICY meetings_read ON public.meetings FOR SELECT USING (true);
    CREATE FUNCTION private.get_visible_comments()
      RETURNS TABLE(id uuid, chapter_id uuid, user_id uuid, parent_id uuid, created_at timestamptz, likes_count integer, replies_count integer, is_spoiler boolean, content text, is_locked boolean)
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
        SELECT c.id,c.chapter_id,c.user_id,c.parent_id,c.created_at,c.likes_count,c.replies_count,c.is_spoiler,c.content,false
        FROM public.comments c WHERE c.deleted_at IS NULL
      $$;
    GRANT USAGE ON SCHEMA public, private, auth TO anon, authenticated;
    GRANT SELECT ON public.chapters, public.seasons, public.meetings TO anon, authenticated;
    GRANT SELECT ON public.quiz_questions TO authenticated;
    GRANT SELECT ON public.comments, public.user_progress TO authenticated;
    GRANT EXECUTE ON FUNCTION auth.uid(), private.get_visible_comments() TO anon, authenticated;
    INSERT INTO public.seasons VALUES
      ('10000000-0000-4000-8000-000000000001','active'),
      ('10000000-0000-4000-8000-000000000002','draft');
    INSERT INTO public.chapters VALUES
      ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',now()-interval '1 day'),
      ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001',now()+interval '1 day'),
      ('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001',NULL),
      ('20000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000002',now()-interval '1 day');
    INSERT INTO public.meetings VALUES
      ('30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001'),
      ('30000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002'),
      ('30000000-0000-4000-8000-000000000003',NULL);
    INSERT INTO public.quiz_questions VALUES
      ('40000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',0),
      ('40000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002',1),
      ('40000000-0000-4000-8000-000000000003','20000000-0000-4000-8000-000000000004',0);
    INSERT INTO public.comments(id,chapter_id,user_id,content) VALUES
      ('50000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000001','visible'),
      ('50000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002','60000000-0000-4000-8000-000000000001','future'),
      ('50000000-0000-4000-8000-000000000003','20000000-0000-4000-8000-000000000004','60000000-0000-4000-8000-000000000001','season draft');
  `);

  await db.exec(migration);
  await db.exec('SET ROLE anon');
  const chapters = await db.query('SELECT id FROM public.chapters ORDER BY id');
  assert.equal(chapters.rows.length, 2, 'anon should see the already available chapter and legacy null-published chapter only');
  const meetings = await db.query('SELECT id FROM public.meetings ORDER BY id');
  assert.equal(meetings.rows.length, 2, 'anon should not see meeting linked to future chapter; unlinked meeting stays visible');
  const comments = await db.query('SELECT id FROM private.get_visible_comments() ORDER BY id');
  assert.equal(comments.rows.length, 1, 'visible-comments helper should exclude future and inactive-season comments');
  await db.exec('RESET ROLE; SET ROLE authenticated');
  const questions = await db.query('SELECT id FROM public.quiz_questions ORDER BY id');
  assert.equal(questions.rows.length, 1, 'authenticated user should see questions only for available chapters and active seasons');
  await db.exec('RESET ROLE');
  console.log('PASS: publication visibility (anon/authenticated, future rows hidden, legacy NULL compatible)');
} finally {
  await db.close();
}
