-- Fonte: SDDBD2.md; seed do catálogo atual e idempotente por slug/constraint.
-- Autor legado permanece disponível como entidade; o livro ativo agora é Verity.
insert into public.authors (name, slug, bio)
values ('Machado de Assis', 'machado-de-assis', 'Escritor brasileiro (1839–1908).')
on conflict (slug) do nothing;

DO $$
DECLARE
  v_author_id uuid;
  v_book_id uuid;
  v_season_id uuid;
  v_cover_url text := 'https://www.record.com.br/cdn/shop/files/d714a333a0c7d64404774020856088c2.jpg?v=1791572393';
BEGIN
  insert into public.authors (name, slug, bio, website_url, instagram)
  values (
    'Colleen Hoover', 'colleen-hoover',
    'Autora norte-americana de romances contemporâneos e thrillers psicológicos; Verity é seu primeiro thriller.',
    'https://www.colleenhoover.com/', 'https://www.instagram.com/ColleenHoover/'
  )
  on conflict (slug) do update set
    name = excluded.name,
    bio = excluded.bio,
    website_url = excluded.website_url,
    instagram = excluded.instagram
  returning id into v_author_id;

  insert into public.books (
    title, slug, author_id, isbn13, cover_url, synopsis, total_chapters, total_pages,
    publication_year, language, publisher, translator, publication_date, content_rating,
    edition_number, format, width_mm, height_mm, depth_mm, amazon_url, tags
  )
  values (
    'Verity', 'verity', v_author_id, '9788501117847', v_cover_url,
    'Lowen Ashleigh, uma escritora em dificuldades, aceita o trabalho de concluir a série de sucesso de Verity Crawford, autora impossibilitada de escrever após um acidente. Ao organizar os materiais de Verity, Lowen encontra um manuscrito autobiográfico confidencial, cujas revelações sobre a família Crawford a colocam diante de uma decisão difícil.',
    25, 320, 2020, 'pt-BR', 'Galera Record', 'Thaís Britto', DATE '2020-03-09',
    '18 anos', 22, 'Capa comum', 135, 210, 17,
    'https://www.amazon.com.br/Verity-Colleen-Hoover/dp/8501117846',
    ARRAY['Suspense psicológico', 'Thriller romântico', 'Ficção contemporânea', '18+']::text[]
  )
  on conflict (slug) do update set
    title = excluded.title,
    author_id = excluded.author_id,
    isbn13 = excluded.isbn13,
    cover_url = excluded.cover_url,
    synopsis = excluded.synopsis,
    total_chapters = excluded.total_chapters,
    total_pages = excluded.total_pages,
    publication_year = excluded.publication_year,
    language = excluded.language,
    publisher = excluded.publisher,
    translator = excluded.translator,
    publication_date = excluded.publication_date,
    content_rating = excluded.content_rating,
    edition_number = excluded.edition_number,
    format = excluded.format,
    width_mm = excluded.width_mm,
    height_mm = excluded.height_mm,
    depth_mm = excluded.depth_mm,
    amazon_url = excluded.amazon_url,
    tags = excluded.tags,
    updated_at = now()
  returning id into v_book_id;

  insert into public.seasons (
    number, title, slug, book_id, status, description, starts_at, ends_at, default_time, cover_url
  )
  values (
    1, 'Verity', 't1-verity', v_book_id, 'active',
    'Leitura coletiva de Verity, suspense psicológico de Colleen Hoover.',
    DATE '2026-10-08', DATE '2026-11-12', TIME '20:00', v_cover_url
  )
  on conflict (number) do update set
    title = excluded.title,
    slug = excluded.slug,
    book_id = excluded.book_id,
    status = excluded.status,
    description = excluded.description,
    starts_at = excluded.starts_at,
    ends_at = excluded.ends_at,
    default_time = excluded.default_time,
    cover_url = excluded.cover_url
  returning id into v_season_id;

  insert into public.chapters (season_id, number, title, reading_range, youtube_url, summary)
  values
    (v_season_id, 1, 'Capítulo 1 — O encontro que mudou tudo', 'Capítulo 1', 'https://youtu.be/zyJkEg09nbo', null),
    (v_season_id, 2, 'Capítulo 2 — O encontro que muda tudo', 'Capítulo 2', 'https://youtu.be/RQKB4AdTEKc', null),
    (v_season_id, 3, 'Capítulo 3 — O segredo sombrio da mansão Crawford', 'Capítulo 3', 'https://youtu.be/WThFSwoxpc8', null)
  on conflict (season_id, number) do update set
    title = excluded.title,
    reading_range = excluded.reading_range,
    youtube_url = excluded.youtube_url,
    summary = excluded.summary;

  insert into public.quiz_questions (chapter_id, position, question, options, correct_idx, explanation)
  select c.id, 1,
         'Quem contrata Lowen para concluir os livros restantes da série de Verity?',
         '["Jeremy Crawford","Verity Crawford","Lowen Ashleigh","A editora de Verity"]'::jsonb,
         0,
         'Jeremy Crawford, marido de Verity, faz a proposta a Lowen.'
    from public.chapters c
   where c.season_id = v_season_id and c.number = 1
  on conflict (chapter_id, position) do nothing;

  insert into public.host_prompts (chapter_id, question, options)
  select c.id,
         'Que pista até agora mais influencia sua confiança nas versões da história?',
         '["As anotações","O ambiente da casa","As conversas","Ainda estou em dúvida"]'::jsonb
    from public.chapters c
   where c.season_id = v_season_id and c.number = 3
     and not exists (
       select 1 from public.host_prompts hp
        where hp.chapter_id = c.id
          and hp.question = 'Que pista até agora mais influencia sua confiança nas versões da história?'
     );
END;
$$;

-- Conquistas padrão
insert into public.achievements (code, title, description, rule, xp_reward) values
  ('first_book','Primeiro livro','Concluiu o primeiro livro do clube.',
    '{"type":"count","source":"finish_book","gte":1}'::jsonb, 50),
  ('streak_4w','4 semanas seguidas','Manteve streak de 4 semanas.',
    '{"type":"streak","gte":28}'::jsonb, 100),
  ('machado_master','Mestre do Machado','Concluiu todas as obras de Machado na plataforma.',
    '{"type":"author_complete","author":"machado-de-assis"}'::jsonb, 200)
ON CONFLICT (code) DO NOTHING;
