import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { PGlite } from './node_modules/@electric-sql/pglite/dist/index.js';

const root = resolve(import.meta.dirname, '../..');
const migration = await readFile(resolve(root, 'supabase/migrations/20261009194650_add_verity_edition_metadata_and_catalog.sql'), 'utf8');
const seed = await readFile(resolve(root, 'supabase/seed.sql'), 'utf8');
const db = new PGlite();
try {
  await db.exec(`
    CREATE TYPE public.cycle_status AS ENUM ('planned', 'active', 'finished');
    CREATE TYPE public.editorial_pick_kind AS ENUM ('book_of_the_month');
    CREATE TABLE public.authors (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL,
      slug text UNIQUE NOT NULL, bio text, photo_url text, website_url text, instagram text,
      created_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE TABLE public.books (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(), title text NOT NULL, slug text UNIQUE NOT NULL,
      author_id uuid NOT NULL REFERENCES public.authors(id) ON DELETE RESTRICT,
      isbn13 text UNIQUE, cover_url text, synopsis text, total_chapters int, total_pages int,
      publication_year int, language text DEFAULT 'pt-BR', amazon_url text, amazon_affiliate text,
      ebook_url text, audiobook_url text, tags text[] DEFAULT '{}', created_at timestamptz DEFAULT now(),
      updated_at timestamptz DEFAULT now()
    );
    CREATE TABLE public.seasons (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(), number int UNIQUE NOT NULL, title text NOT NULL,
      slug text UNIQUE NOT NULL, book_id uuid NOT NULL REFERENCES public.books(id),
      status public.cycle_status NOT NULL DEFAULT 'planned', description text,
      starts_at date, ends_at date, default_time time DEFAULT '20:00', cover_url text,
      created_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE TABLE public.chapters (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(), season_id uuid NOT NULL REFERENCES public.seasons(id) ON DELETE CASCADE,
      number int NOT NULL, title text NOT NULL, reading_range text, youtube_url text,
      summary text, published_at timestamptz, UNIQUE (season_id, number)
    );
    CREATE TABLE public.editorial_picks (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(), book_id uuid NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
      season_id uuid REFERENCES public.seasons(id) ON DELETE SET NULL, kind public.editorial_pick_kind NOT NULL,
      reference_month date NOT NULL, title text, rationale text, is_active boolean NOT NULL DEFAULT true,
      UNIQUE (kind, reference_month)
    );
    CREATE TABLE public.book_mood_stats (
      book_id uuid PRIMARY KEY REFERENCES public.books(id) ON DELETE CASCADE
    );
    CREATE TABLE public.milestones (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(), chapter_id uuid NOT NULL REFERENCES public.chapters(id) ON DELETE CASCADE,
      season_id uuid NOT NULL REFERENCES public.seasons(id) ON DELETE CASCADE,
      book_id uuid NOT NULL REFERENCES public.books(id) ON DELETE CASCADE,
      position int NOT NULL, title text NOT NULL, description text NOT NULL, kind text NOT NULL,
      UNIQUE (season_id, position)
    );
    CREATE FUNCTION public.generate_milestones_for_season(p_season uuid)
      RETURNS void LANGUAGE plpgsql AS $$
      DECLARE v_book uuid; v_chapter record; v_position int := 0;
      BEGIN
        SELECT book_id INTO v_book FROM public.seasons WHERE id = p_season;
        FOR v_chapter IN SELECT id, number, title FROM public.chapters WHERE season_id = p_season ORDER BY number
        LOOP
          v_position := v_position + 1;
          INSERT INTO public.milestones(chapter_id, season_id, book_id, position, title, description, kind)
          VALUES (v_chapter.id, p_season, v_book, v_position,
                  format('Marco %s — %s', v_position, v_chapter.title),
                  'Marco gerado automaticamente a partir do capítulo.', 'auto')
          ON CONFLICT (season_id, position) DO NOTHING;
        END LOOP;
      END $$;

    INSERT INTO public.authors(id, name, slug) VALUES
      ('11111111-1111-1111-1111-111111111111', 'Machado de Assis', 'machado-de-assis');
    INSERT INTO public.books(id, title, slug, author_id, isbn13, total_chapters, total_pages)
    VALUES ('22222222-2222-2222-2222-222222222222', 'Dom Casmurro', 'dom-casmurro',
            '11111111-1111-1111-1111-111111111111', '9788535910663', 148, 256);
    INSERT INTO public.seasons(id, number, title, slug, book_id, status, starts_at, ends_at)
    VALUES ('33333333-3333-3333-3333-333333333333', 1, 'Dom Casmurro', 't1-dom-casmurro',
            '22222222-2222-2222-2222-222222222222', 'active', DATE '2026-10-08', DATE '2026-11-12');
    INSERT INTO public.chapters(season_id, number, title)
    SELECT '33333333-3333-3333-3333-333333333333', n, 'Capítulo antigo ' || n FROM generate_series(1, 5) AS n;
    INSERT INTO public.editorial_picks(book_id, season_id, kind, reference_month, title)
    VALUES ('22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333',
            'book_of_the_month', DATE '2026-10-01', 'Destaque antigo');
    INSERT INTO public.book_mood_stats(book_id) VALUES ('22222222-2222-2222-2222-222222222222');
    INSERT INTO public.milestones(chapter_id, season_id, book_id, position, title, description, kind)
    SELECT c.id, c.season_id, '22222222-2222-2222-2222-222222222222', c.number,
           'Marco antigo ' || c.number, 'fixture', 'auto'
      FROM public.chapters c WHERE c.season_id = '33333333-3333-3333-3333-333333333333';
  `);

  await db.exec(migration);

  await db.exec(`
    CREATE TABLE public.quiz_questions (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(), chapter_id uuid NOT NULL REFERENCES public.chapters(id) ON DELETE CASCADE,
      position int NOT NULL, question text NOT NULL, options jsonb NOT NULL, correct_idx int NOT NULL,
      explanation text, UNIQUE (chapter_id, position)
    );
    CREATE TABLE public.host_prompts (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(), chapter_id uuid NOT NULL REFERENCES public.chapters(id) ON DELETE CASCADE,
      question text NOT NULL, options jsonb
    );
    CREATE TABLE public.achievements (
      code text PRIMARY KEY, title text NOT NULL, description text NOT NULL, rule jsonb NOT NULL, xp_reward int
    );
  `);
  await db.exec(seed);

  const books = await db.query("SELECT slug, title, isbn13, publisher, translator, publication_date::text, content_rating, edition_number, format, width_mm, height_mm, depth_mm FROM public.books ORDER BY slug LIMIT 10");
  assert.equal(books.rows.length, 1, 'the old catalog book should be removed and exactly one replacement should remain');
  assert.deepEqual(books.rows[0], {
    slug: 'verity', title: 'Verity', isbn13: '9788501117847', publisher: 'Galera Record',
    translator: 'Thaís Britto', publication_date: '2020-03-09', content_rating: '18 anos',
    edition_number: 22, format: 'Capa comum', width_mm: 135, height_mm: 210, depth_mm: 17,
  });

  const seasons = await db.query("SELECT slug, status::text, starts_at::text, ends_at::text, default_time::text FROM public.seasons ORDER BY number LIMIT 10");
  assert.deepEqual(seasons.rows, [{ slug: 't1-verity', status: 'active', starts_at: '2026-10-08', ends_at: '2026-11-12', default_time: '20:00:00' }]);

  const chapters = await db.query('SELECT number, youtube_url FROM public.chapters ORDER BY number LIMIT 10');
  assert.deepEqual(chapters.rows, [
    { number: 1, youtube_url: 'https://youtu.be/zyJkEg09nbo' },
    { number: 2, youtube_url: 'https://youtu.be/RQKB4AdTEKc' },
    { number: 3, youtube_url: 'https://youtu.be/WThFSwoxpc8' },
  ]);

  const editorial = await db.query('SELECT reference_month::text, book_id FROM public.editorial_picks ORDER BY reference_month LIMIT 10');
  assert.equal(editorial.rows.length, 1, 'the monthly editorial pick should move to Verity');
  const moodStats = await db.query('SELECT count(*)::int AS count FROM public.book_mood_stats');
  assert.equal(moodStats.rows[0].count, 1, 'the replacement should have a fresh mood aggregate');
  const milestones = await db.query('SELECT count(*)::int AS count FROM public.milestones');
  assert.equal(milestones.rows[0].count, 3, 'milestones should be regenerated for the three published chapter entries');
  const quiz = await db.query('SELECT count(*)::int AS count FROM public.quiz_questions');
  assert.equal(quiz.rows[0].count, 1, 'the refreshed seed should create its non-spoiler Verity question');
  const prompts = await db.query('SELECT count(*)::int AS count FROM public.host_prompts');
  assert.equal(prompts.rows[0].count, 1, 'the refreshed seed should create a Verity discussion prompt');

  await assert.rejects(
    db.query("UPDATE public.books SET width_mm = 0 WHERE slug = 'verity'"),
    (error) => String(error.message).includes('books_edition_dimensions_positive_check'),
    'physical dimensions must be positive when present',
  );
  console.log('PASS: book edition metadata and catalog replacement (PGlite transaction + cascade + integrations)');
} finally {
  await db.close();
}
