-- Verity (edição brasileira) substitui o livro/ciclo demonstrativo anterior.
-- A colunação é aditiva e as dimensões admitem NULL para registros sem ficha física.
ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS publisher text,
  ADD COLUMN IF NOT EXISTS translator text,
  ADD COLUMN IF NOT EXISTS publication_date date,
  ADD COLUMN IF NOT EXISTS content_rating text,
  ADD COLUMN IF NOT EXISTS edition_number smallint,
  ADD COLUMN IF NOT EXISTS format text,
  ADD COLUMN IF NOT EXISTS width_mm smallint,
  ADD COLUMN IF NOT EXISTS height_mm smallint,
  ADD COLUMN IF NOT EXISTS depth_mm smallint;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_constraint
     WHERE conname = 'books_edition_dimensions_positive_check'
       AND conrelid = 'public.books'::regclass
  ) THEN
    ALTER TABLE public.books
      ADD CONSTRAINT books_edition_dimensions_positive_check
      CHECK (
        (width_mm IS NULL OR width_mm > 0)
        AND (height_mm IS NULL OR height_mm > 0)
        AND (depth_mm IS NULL OR depth_mm > 0)
        AND (edition_number IS NULL OR edition_number > 0)
      );
  END IF;
END;
$$;

-- Mantém a troca atômica entre conteúdo antigo e novo dentro de um único DO.
-- IDs novos vêm de DEFAULT/RETURNING, sem referenciar IDs gerados previamente.
DO $$
DECLARE
  v_old_book_id uuid;
  v_author_id uuid;
  v_book_id uuid;
  v_season_id uuid;
  v_unexpected_season_id uuid;
  v_reference_month date := date_trunc('month', current_date)::date;
  v_cover_url text := 'https://www.record.com.br/cdn/shop/files/d714a333a0c7d64404774020856088c2.jpg?v=1791572393';
BEGIN
  -- Não sobrescrever uma temporada nº 1 que não seja o ciclo autorizado.
  SELECT s.id
    INTO v_unexpected_season_id
    FROM public.seasons AS s
   WHERE s.number = 1
     AND s.slug NOT IN ('t1-dom-casmurro', 't1-verity')
   LIMIT 1;
  IF v_unexpected_season_id IS NOT NULL THEN
    RAISE EXCEPTION 'Substituição cancelada: existe outra temporada nº 1 (%)', v_unexpected_season_id;
  END IF;

  SELECT b.id
    INTO v_old_book_id
    FROM public.books AS b
   WHERE b.slug = 'dom-casmurro'
     AND b.title = 'Dom Casmurro'
   LIMIT 1;

  IF v_old_book_id IS NOT NULL THEN
    SELECT ep.reference_month
      INTO v_reference_month
      FROM public.editorial_picks AS ep
     WHERE ep.book_id = v_old_book_id
       AND ep.kind = 'book_of_the_month'
     ORDER BY ep.reference_month DESC
     LIMIT 1;
    v_reference_month := coalesce(v_reference_month, date_trunc('month', current_date)::date);

    -- A cascata remove apenas os conteúdos vinculados ao livro que o usuário aprovou.
    DELETE FROM public.seasons AS s WHERE s.book_id = v_old_book_id;
    DELETE FROM public.books AS b WHERE b.id = v_old_book_id;
  END IF;

  INSERT INTO public.authors (name, slug, bio, website_url, instagram)
  VALUES (
    'Colleen Hoover',
    'colleen-hoover',
    'Autora norte-americana de romances contemporâneos e thrillers psicológicos; Verity é seu primeiro thriller.',
    'https://www.colleenhoover.com/',
    'https://www.instagram.com/ColleenHoover/'
  )
  ON CONFLICT (slug) DO UPDATE SET
    name = EXCLUDED.name,
    bio = EXCLUDED.bio,
    website_url = EXCLUDED.website_url,
    instagram = EXCLUDED.instagram
  RETURNING id INTO v_author_id;

  INSERT INTO public.books (
    title, slug, author_id, isbn13, cover_url, synopsis,
    total_chapters, total_pages, publication_year, language,
    publisher, translator, publication_date, content_rating, edition_number,
    format, width_mm, height_mm, depth_mm, amazon_url, tags
  )
  VALUES (
    'Verity',
    'verity',
    v_author_id,
    '9788501117847',
    v_cover_url,
    'Lowen Ashleigh, uma escritora em dificuldades, aceita o trabalho de concluir a série de sucesso de Verity Crawford, autora impossibilitada de escrever após um acidente. Ao organizar os materiais de Verity, Lowen encontra um manuscrito autobiográfico confidencial, cujas revelações sobre a família Crawford a colocam diante de uma decisão difícil.',
    25,
    320,
    2020,
    'pt-BR',
    'Galera Record',
    'Thaís Britto',
    DATE '2020-03-09',
    '18 anos',
    22,
    'Capa comum',
    135,
    210,
    17,
    'https://www.amazon.com.br/Verity-Colleen-Hoover/dp/8501117846',
    ARRAY['Suspense psicológico', 'Thriller romântico', 'Ficção contemporânea', '18+']::text[]
  )
  ON CONFLICT (slug) DO UPDATE SET
    title = EXCLUDED.title,
    author_id = EXCLUDED.author_id,
    isbn13 = EXCLUDED.isbn13,
    cover_url = EXCLUDED.cover_url,
    synopsis = EXCLUDED.synopsis,
    total_chapters = EXCLUDED.total_chapters,
    total_pages = EXCLUDED.total_pages,
    publication_year = EXCLUDED.publication_year,
    language = EXCLUDED.language,
    publisher = EXCLUDED.publisher,
    translator = EXCLUDED.translator,
    publication_date = EXCLUDED.publication_date,
    content_rating = EXCLUDED.content_rating,
    edition_number = EXCLUDED.edition_number,
    format = EXCLUDED.format,
    width_mm = EXCLUDED.width_mm,
    height_mm = EXCLUDED.height_mm,
    depth_mm = EXCLUDED.depth_mm,
    amazon_url = EXCLUDED.amazon_url,
    tags = EXCLUDED.tags,
    updated_at = now()
  RETURNING id INTO v_book_id;

  INSERT INTO public.seasons (
    number, title, slug, book_id, status, description,
    starts_at, ends_at, default_time, cover_url
  )
  VALUES (
    1,
    'Verity',
    't1-verity',
    v_book_id,
    'active',
    'Leitura coletiva de Verity, suspense psicológico de Colleen Hoover.',
    DATE '2026-10-08',
    DATE '2026-11-12',
    TIME '20:00',
    v_cover_url
  )
  ON CONFLICT (number) DO UPDATE SET
    title = EXCLUDED.title,
    slug = EXCLUDED.slug,
    book_id = EXCLUDED.book_id,
    status = EXCLUDED.status,
    description = EXCLUDED.description,
    starts_at = EXCLUDED.starts_at,
    ends_at = EXCLUDED.ends_at,
    default_time = EXCLUDED.default_time,
    cover_url = EXCLUDED.cover_url
  RETURNING id INTO v_season_id;

  INSERT INTO public.chapters (season_id, number, title, reading_range, youtube_url, summary)
  VALUES
    (v_season_id, 1, 'Capítulo 1 — O encontro que mudou tudo', 'Capítulo 1', 'https://youtu.be/zyJkEg09nbo', NULL),
    (v_season_id, 2, 'Capítulo 2 — O encontro que muda tudo', 'Capítulo 2', 'https://youtu.be/RQKB4AdTEKc', NULL),
    (v_season_id, 3, 'Capítulo 3 — O segredo sombrio da mansão Crawford', 'Capítulo 3', 'https://youtu.be/WThFSwoxpc8', NULL)
  ON CONFLICT (season_id, number) DO UPDATE SET
    title = EXCLUDED.title,
    reading_range = EXCLUDED.reading_range,
    youtube_url = EXCLUDED.youtube_url,
    summary = EXCLUDED.summary;

  IF EXISTS (
    SELECT 1
      FROM public.editorial_picks AS ep
     WHERE ep.kind = 'book_of_the_month'
       AND ep.reference_month = v_reference_month
       AND ep.book_id <> v_book_id
  ) THEN
    RAISE EXCEPTION 'Substituição cancelada: o destaque editorial de % pertence a outro livro', v_reference_month;
  END IF;

  INSERT INTO public.editorial_picks (
    book_id, season_id, kind, reference_month, title, rationale, is_active
  )
  VALUES (
    v_book_id,
    v_season_id,
    'book_of_the_month',
    v_reference_month,
    'Verity — o suspense por trás do manuscrito',
    'Um suspense psicológico em que um manuscrito e uma casa cheia de perguntas convidam o clube a comparar versões.',
    true
  )
  ON CONFLICT (kind, reference_month) DO UPDATE SET
    book_id = EXCLUDED.book_id,
    season_id = EXCLUDED.season_id,
    title = EXCLUDED.title,
    rationale = EXCLUDED.rationale,
    is_active = EXCLUDED.is_active;

  INSERT INTO public.book_mood_stats (book_id)
  VALUES (v_book_id)
  ON CONFLICT (book_id) DO NOTHING;

  PERFORM public.generate_milestones_for_season(v_season_id);
END;
$$;
