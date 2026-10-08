-- >>> 20260101001650_extensions_and_enums_complement.sql
-- Source: SDDBD2.md. Generated idempotent migration.
-- Extensions adicionais (além das já carregadas em 000)
create extension if not exists "unaccent";     -- busca normalizada em newsletters/feed
create extension if not exists "btree_gin";    -- índices compostos em arrays/jsonb

-- Enums complementares
DO $$ BEGIN CREATE TYPE public.mood_kind AS ENUM (
  'adventurous','emotional','dark','funny','hopeful','informative',
  'inspiring','lighthearted','mysterious','reflective','sad','tense','challenging'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE public.pace_kind AS ENUM ('slow','medium','fast'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.content_warning_severity AS ENUM ('minor','moderate','graphic'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.editorial_pick_kind AS ENUM ('book_of_the_month','editorial_pick','community_pick','staff_pick'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.reading_list_visibility AS ENUM ('private','unlisted','public'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.reading_list_item_kind AS ENUM ('book','chapter','quote','external'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.journal_visibility AS ENUM ('private','friends','club','public'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.feed_post_kind AS ENUM ('quote','review','shelf_update','progress','list','club_invite','link','photo','poll'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.feed_visibility AS ENUM ('public','followers','club','private'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.follow_status AS ENUM ('pending','accepted','blocked'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.member_tier AS ENUM ('free','plus','pro','patron','corporate'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.subscription_status AS ENUM ('trialing','active','past_due','canceled','paused','incomplete'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.payment_provider AS ENUM ('stripe','mercado_pago','pagseguro','manual'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.newsletter_status AS ENUM ('pending','confirmed','unsubscribed','bounced','complained'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.newsletter_frequency AS ENUM ('daily','weekly','monthly','special_only'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.extra_content_kind AS ENUM ('pdf','slides','audio','video','link','spreadsheet','deck','notebook','dataset','template'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.activity_kind AS ENUM ('quiz','crossword','word_search','poll','trivia','flashcards','debate_prompt','drawing_prompt','roleplay','essay_prompt','timed_challenge'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.activity_status AS ENUM ('draft','published','archived'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.social_template_kind AS ENUM ('quote_card','progress_card','milestone_card','review_card','list_card','aura_card','streak_card'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.social_render_status AS ENUM ('queued','rendered','failed','expired'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- >>> 20260101001651_storage_complement.sql
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

-- >>> 20260101001700_book_metadata_and_reading.sql
-- Source: SDDBD2.md. Generated idempotent migration.
-- =====================================================================
-- 1. Content Warnings estruturados
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.content_warnings (
  id             uuid primary key default gen_random_uuid(),
  code           text unique not null,     -- 'violence','grief','abuse','self_harm', ...
  label          text not null,            -- rótulo humano em pt-BR
  description    text,
  category       text,                     -- 'mental_health','violence','identity','substance', ...
  created_at     timestamptz not null default now()
);
CREATE TABLE IF NOT EXISTS public.book_content_warnings (
  id              uuid primary key default gen_random_uuid(),
  book_id         uuid not null references public.books(id) on delete cascade,
  warning_id      uuid not null references public.content_warnings(id) on delete cascade,
  severity        content_warning_severity not null default 'moderate',
  is_community    boolean not null default true,   -- true = gerado pela comunidade; false = curadoria editorial
  reported_by     uuid references public.profiles(id) on delete set null,
  community_votes int not null default 1,
  notes           text,
  created_at      timestamptz not null default now(),
  unique (book_id, warning_id)
);
CREATE INDEX IF NOT EXISTS bcw_book_idx     on public.book_content_warnings (book_id);
CREATE INDEX IF NOT EXISTS bcw_severity_idx on public.book_content_warnings (severity);

-- Votos individuais para recalcular community_votes sem depender de contador
CREATE TABLE IF NOT EXISTS public.book_content_warning_votes (
  warning_row_id uuid not null references public.book_content_warnings(id) on delete cascade,
  user_id        uuid not null references public.profiles(id) on delete cascade,
  agrees         boolean not null default true,
  created_at     timestamptz not null default now(),
  primary key (warning_row_id, user_id)
);

-- =====================================================================
-- 2. Mood / Pace / Plot-vs-Character por livro
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.book_mood_stats (
  book_id        uuid primary key references public.books(id) on delete cascade,
  mood_counts    jsonb not null default '{}'::jsonb,   -- {"dark": 42, "emotional": 38, ...}
  mood_percent   jsonb not null default '{}'::jsonb,   -- {"dark": 0.42, ...}
  pace_percent   jsonb not null default '{"slow":0,"medium":0,"fast":0}'::jsonb,
  plot_vs_character_avg numeric(3,2) not null default 0.50, -- 0=enredo, 1=personagem
  sample_size    int not null default 0,
  updated_at     timestamptz not null default now()
);
CREATE TABLE IF NOT EXISTS public.book_mood_votes (
  book_id      uuid not null references public.books(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  moods        mood_kind[] not null default '{}',
  pace         pace_kind,
  plot_vs_character numeric(3,2) check (plot_vs_character between 0 and 1),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (book_id, user_id)
);
CREATE INDEX IF NOT EXISTS bmv_moods_gin on public.book_mood_votes using gin (moods);

-- Rótulos display dos moods (i18n pt-BR)
CREATE TABLE IF NOT EXISTS public.mood_labels (
  mood       mood_kind primary key,
  label_pt   text not null,
  color_hex  text not null,
  icon       text
);

-- =====================================================================
-- 3. Escolha editorial (Book of the Month / Destaques)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.editorial_picks (
  id           uuid primary key default gen_random_uuid(),
  book_id      uuid not null references public.books(id) on delete cascade,
  season_id    uuid references public.seasons(id) on delete set null,
  kind         editorial_pick_kind not null default 'book_of_the_month',
  reference_month date not null,             -- primeiro dia do mês de referência
  title        text,                         -- headline editorial
  rationale    text,                         -- "por que escolhemos"
  media_url    text,                         -- vídeo/áudio da curadoria
  is_active    boolean not null default true,
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  unique (kind, reference_month)
);
CREATE INDEX IF NOT EXISTS editorial_picks_month_idx on public.editorial_picks (reference_month desc);

-- =====================================================================
-- 4. Buddy Reads (leitura em dupla/trio com checkpoints)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.buddy_reads (
  id            uuid primary key default gen_random_uuid(),
  book_id       uuid not null references public.books(id) on delete cascade,
  season_id     uuid references public.seasons(id) on delete set null,
  title         text,
  owner_id      uuid not null references public.profiles(id) on delete cascade,
  is_private    boolean not null default true,
  max_members   int not null default 3 check (max_members between 2 and 10),
  start_date    date,
  end_date      date,
  created_at    timestamptz not null default now()
);
CREATE TABLE IF NOT EXISTS public.buddy_read_members (
  buddy_read_id uuid not null references public.buddy_reads(id) on delete cascade,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  joined_at     timestamptz not null default now(),
  primary key (buddy_read_id, user_id)
);
CREATE TABLE IF NOT EXISTS public.buddy_read_checkpoints (
  id             uuid primary key default gen_random_uuid(),
  buddy_read_id  uuid not null references public.buddy_reads(id) on delete cascade,
  position       int not null,
  title          text not null,
  page_from      int,
  page_to        int,
  percent_from   numeric(5,2),
  percent_to     numeric(5,2),
  target_date    date,
  unique (buddy_read_id, position)
);

-- >>> 20260101001800_journal_and_lists.sql
-- Source: SDDBD2.md. Generated idempotent migration.
-- =====================================================================
-- 1. Diário de leitura (texto livre por sessão)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.reading_journal_entries (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles(id) on delete cascade,
  book_id        uuid not null references public.books(id) on delete cascade,
  chapter_id     uuid references public.chapters(id) on delete set null,
  season_id      uuid references public.seasons(id) on delete set null,
  entry_date     date not null default current_date,
  page_from      int,
  page_to        int,
  percent_at     numeric(5,2) check (percent_at between 0 and 100),
  minutes_read   int default 0,
  mood_at_time   mood_kind,
  title          text,
  body           text not null check (length(body) between 1 and 20000),
  visibility     journal_visibility not null default 'private',
  is_spoiler     boolean not null default false,
  min_percent    numeric(5,2) not null default 0.00,
  likes_count    int not null default 0,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS rje_user_date_idx  on public.reading_journal_entries (user_id, entry_date desc);
CREATE INDEX IF NOT EXISTS rje_book_idx       on public.reading_journal_entries (book_id);
CREATE INDEX IF NOT EXISTS rje_chapter_idx    on public.reading_journal_entries (chapter_id);
CREATE INDEX IF NOT EXISTS rje_visibility_idx on public.reading_journal_entries (visibility);

-- Anexos de mídia do diário (fotos, áudios, prints)
CREATE TABLE IF NOT EXISTS public.reading_journal_attachments (
  id            uuid primary key default gen_random_uuid(),
  entry_id      uuid not null references public.reading_journal_entries(id) on delete cascade,
  storage_path  text not null,
  mime_type     text not null,
  size_bytes    bigint not null,
  created_at    timestamptz not null default now()
);

-- =====================================================================
-- 2. Listas personalizadas (temáticas, colaborativas e curadas)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.reading_lists (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references public.profiles(id) on delete cascade,
  slug          text unique not null,
  title         text not null,
  description   text,
  cover_url     text,
  visibility    reading_list_visibility not null default 'private',
  is_collaborative boolean not null default false,
  theme         text,                 -- ex: 'Machado de Assis', 'Ficção Científica BR'
  tags          text[] default '{}',
  items_count   int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS rl_owner_idx      on public.reading_lists (owner_id);
CREATE INDEX IF NOT EXISTS rl_visibility_idx on public.reading_lists (visibility);
CREATE INDEX IF NOT EXISTS rl_tags_gin       on public.reading_lists using gin (tags);
CREATE TABLE IF NOT EXISTS public.reading_list_items (
  id           uuid primary key default gen_random_uuid(),
  list_id      uuid not null references public.reading_lists(id) on delete cascade,
  kind         reading_list_item_kind not null default 'book',
  book_id      uuid references public.books(id) on delete cascade,
  chapter_id   uuid references public.chapters(id) on delete cascade,
  external_url text,
  quote_text   text,
  note         text,
  position     int not null default 0,
  added_by     uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS rli_list_idx on public.reading_list_items (list_id, position);
CREATE TABLE IF NOT EXISTS public.reading_list_collaborators (
  list_id  uuid not null references public.reading_lists(id) on delete cascade,
  user_id  uuid not null references public.profiles(id) on delete cascade,
  can_edit boolean not null default true,
  added_at timestamptz not null default now(),
  primary key (list_id, user_id)
);

-- =====================================================================
-- 3. "Up Next" (fila de prioridade da estante)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.user_up_next (
  user_id   uuid not null references public.profiles(id) on delete cascade,
  book_id   uuid not null references public.books(id) on delete cascade,
  position  int not null check (position between 1 and 5),
  added_at  timestamptz not null default now(),
  primary key (user_id, book_id),
  unique (user_id, position)
);

-- >>> 20260101001900_milestones_stats_quiz.sql
-- Source: SDDBD2.md. Generated idempotent migration.
-- =====================================================================
-- 1. Milestones (marcos) — definidos por criador ou automáticos
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.milestones (
  id             uuid primary key default gen_random_uuid(),
  chapter_id     uuid references public.chapters(id) on delete cascade,
  season_id      uuid not null references public.seasons(id) on delete cascade,
  book_id        uuid not null references public.books(id) on delete cascade,
  position       int  not null,
  title          text not null,
  description    text,
  kind           text not null default 'auto',  -- 'auto' | 'custom'
  page_from      int,
  page_to        int,
  chapter_from   int,
  chapter_to     int,
  percent_from   numeric(5,2),
  percent_to     numeric(5,2),
  target_date    date,
  xp_reward      int not null default 15,
  created_by     uuid references public.profiles(id) on delete set null,
  created_at     timestamptz not null default now(),
  unique (season_id, position)
);
CREATE INDEX IF NOT EXISTS milestones_chapter_idx on public.milestones (chapter_id, position);
CREATE TABLE IF NOT EXISTS public.user_milestone_progress (
  user_id       uuid not null references public.profiles(id) on delete cascade,
  milestone_id  uuid not null references public.milestones(id) on delete cascade,
  completed_at  timestamptz,
  xp_awarded    boolean not null default false,
  created_at    timestamptz not null default now(),
  primary key (user_id, milestone_id)
);

-- =====================================================================
-- 2. Média de quizzes (materializada)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.user_quiz_averages (
  user_id           uuid primary key references public.profiles(id) on delete cascade,
  attempts_total    int not null default 0,
  score_sum         int not null default 0,
  total_sum         int not null default 0,
  average_percent   numeric(5,2) not null default 0.00,
  best_percent      numeric(5,2) not null default 0.00,
  last_attempt_at   timestamptz,
  updated_at        timestamptz not null default now()
);
CREATE TABLE IF NOT EXISTS public.chapter_quiz_averages (
  chapter_id        uuid primary key references public.chapters(id) on delete cascade,
  attempts_total    int not null default 0,
  average_percent   numeric(5,2) not null default 0.00,
  perfect_count     int not null default 0,
  updated_at        timestamptz not null default now()
);

-- =====================================================================
-- 3. Metas anuais e desafios de leitura
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.reading_goals (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles(id) on delete cascade,
  year           int not null,
  target_books   int,
  target_pages   int,
  target_minutes int,
  created_at     timestamptz not null default now(),
  unique (user_id, year)
);
CREATE TABLE IF NOT EXISTS public.reading_goal_progress (
  goal_id      uuid primary key references public.reading_goals(id) on delete cascade,
  books_done   int not null default 0,
  pages_done   int not null default 0,
  minutes_done int not null default 0,
  updated_at   timestamptz not null default now()
);

-- =====================================================================
-- 4. Desafios temáticos baseados em prompts
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.challenge_prompts (
  id            uuid primary key default gen_random_uuid(),
  challenge_id  uuid not null references public.challenges(id) on delete cascade,
  position      int not null,
  prompt        text not null,             -- "Livro traduzido", "Autor indígena"
  book_id       uuid references public.books(id) on delete set null,
  completed_at  timestamptz,
  completed_by  uuid references public.profiles(id) on delete set null,
  unique (challenge_id, position)
);

-- >>> 20260101002000_social_feed_and_match.sql
-- Source: SDDBD2.md. Generated idempotent migration.
-- =====================================================================
-- 1. Posts livres (feed social)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.feed_posts (
  id             uuid primary key default gen_random_uuid(),
  author_id      uuid not null references public.profiles(id) on delete cascade,
  kind           feed_post_kind not null default 'quote',
  visibility     feed_visibility not null default 'public',
  club_id        uuid references public.user_clubs(id) on delete set null,
  book_id        uuid references public.books(id) on delete set null,
  chapter_id     uuid references public.chapters(id) on delete set null,
  season_id      uuid references public.seasons(id) on delete set null,
  body           text check (length(body) <= 8000),
  quote_text     text,
  link_url       text,
  cover_url      text,
  metadata       jsonb not null default '{}'::jsonb,
  is_spoiler     boolean not null default false,
  min_percent    numeric(5,2) not null default 0.00,
  likes_count    int not null default 0,
  comments_count int not null default 0,
  shares_count   int not null default 0,
  deleted_at     timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS feed_posts_public_idx on public.feed_posts (created_at desc) where deleted_at is null and visibility = 'public';
CREATE INDEX IF NOT EXISTS feed_posts_author_idx on public.feed_posts (author_id, created_at desc);
CREATE INDEX IF NOT EXISTS feed_posts_club_idx   on public.feed_posts (club_id, created_at desc);
CREATE INDEX IF NOT EXISTS feed_posts_book_idx   on public.feed_posts (book_id);
CREATE TABLE IF NOT EXISTS public.feed_post_media (
  id           uuid primary key default gen_random_uuid(),
  post_id      uuid not null references public.feed_posts(id) on delete cascade,
  storage_path text not null,
  mime_type    text not null,
  position     int not null default 0,
  created_at   timestamptz not null default now()
);
CREATE TABLE IF NOT EXISTS public.feed_post_likes (
  post_id    uuid not null references public.feed_posts(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
CREATE TABLE IF NOT EXISTS public.feed_post_comments (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid not null references public.feed_posts(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  parent_id   uuid references public.feed_post_comments(id) on delete cascade,
  content     text not null check (length(content) between 1 and 4000),
  is_spoiler  boolean not null default false,
  likes_count int not null default 0,
  deleted_at  timestamptz,
  created_at  timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS fpc_post_idx on public.feed_post_comments (post_id, created_at desc);

-- =====================================================================
-- 2. Seguir / amigos (para feed "followers" e match social)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  followed_id uuid not null references public.profiles(id) on delete cascade,
  status      follow_status not null default 'accepted',
  created_at  timestamptz not null default now(),
  primary key (follower_id, followed_id),
  check (follower_id <> followed_id)
);
CREATE INDEX IF NOT EXISTS follows_followed_idx on public.follows (followed_id, status);

-- =====================================================================
-- 3. Preferências de leitura (questionário base do match)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.user_reading_preferences (
  user_id                  uuid primary key references public.profiles(id) on delete cascade,
  favorite_genres          text[] default '{}',
  disliked_genres          text[] default '{}',
  favorite_tropes          text[] default '{}',
  preferred_pacing         pace_kind[] default '{}',
  preferred_moods          mood_kind[] default '{}',
  avoided_content_warnings text[] default '{}',
  annual_goal_books        int default 12,
  annual_goal_pages        int,
  reading_language         text default 'pt-BR',
  updated_at               timestamptz not null default now()
);

-- =====================================================================
-- 4. Match entre leitores (similaridade entre perfis)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.user_reading_embeddings (
  user_id     uuid primary key references public.profiles(id) on delete cascade,
  embedding   vector(1536) not null,
  source_hash text,             -- hash do snapshot de histórico usado para gerar
  updated_at  timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS ure_embedding_idx on public.user_reading_embeddings
  using ivfflat (embedding vector_cosine_ops) with (lists = 100);
CREATE TABLE IF NOT EXISTS public.user_match_cache (
  user_id      uuid not null references public.profiles(id) on delete cascade,
  matched_id   uuid not null references public.profiles(id) on delete cascade,
  similarity   numeric(5,4) not null,
  shared_books int not null default 0,
  shared_moods mood_kind[] default '{}',
  computed_at  timestamptz not null default now(),
  primary key (user_id, matched_id),
  check (user_id <> matched_id)
);
CREATE INDEX IF NOT EXISTS umc_user_sim_idx on public.user_match_cache (user_id, similarity desc);

-- >>> 20260101002100_monetization_members_newsletter.sql
-- Source: SDDBD2.md. Generated idempotent migration.
-- =====================================================================
-- 1. Planos de assinatura / tiers
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.membership_plans (
  id              uuid primary key default gen_random_uuid(),
  code            text unique not null,        -- 'free','plus_monthly','plus_annual','patron'
  tier            member_tier not null,
  name            text not null,
  description     text,
  price_cents     int not null default 0,
  currency        text not null default 'BRL',
  interval        text not null default 'month', -- 'month','year','lifetime'
  stripe_price_id text,
  perks           jsonb not null default '[]'::jsonb,  -- [{code,label,description}]
  is_active       boolean not null default true,
  created_at      timestamptz not null default now()
);

-- =====================================================================
-- 2. Assinaturas dos usuários
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.user_subscriptions (
  id                       uuid primary key default gen_random_uuid(),
  user_id                  uuid not null references public.profiles(id) on delete cascade,
  plan_id                  uuid not null references public.membership_plans(id) on delete restrict,
  status                   subscription_status not null default 'incomplete',
  provider                 payment_provider not null default 'stripe',
  provider_customer_id     text,
  provider_subscription_id text unique,
  current_period_start     timestamptz,
  current_period_end       timestamptz,
  cancel_at_period_end     boolean not null default false,
  canceled_at              timestamptz,
  trial_end                timestamptz,
  metadata                 jsonb not null default '{}'::jsonb,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS us_user_idx   on public.user_subscriptions (user_id);
CREATE INDEX IF NOT EXISTS us_status_idx on public.user_subscriptions (status);

-- Registro bruto de eventos de gateway (auditoria/replay)
CREATE TABLE IF NOT EXISTS public.payment_events (
  id             uuid primary key default gen_random_uuid(),
  provider       payment_provider not null,
  event_id       text not null,
  event_type     text not null,
  user_id        uuid references public.profiles(id) on delete set null,
  payload        jsonb not null,
  processed_at   timestamptz,
  created_at     timestamptz not null default now(),
  unique (provider, event_id)
);

-- Benefícios consumidos pelo usuário (ex: desconto aplicado, ebook liberado)
CREATE TABLE IF NOT EXISTS public.user_membership_perks (
  user_id     uuid not null references public.profiles(id) on delete cascade,
  perk_code   text not null,
  payload     jsonb not null default '{}'::jsonb,
  granted_at  timestamptz not null default now(),
  expires_at  timestamptz,
  primary key (user_id, perk_code)
);

-- =====================================================================
-- 3. Newsletter (inscrições e disparos)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.newsletter_subscribers (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid references public.profiles(id) on delete set null,
  email                citext not null,
  name                 text,
  status               newsletter_status not null default 'pending',
  frequency            newsletter_frequency not null default 'weekly',
  source               text,                              -- 'site','checkout','import','club'
  tags                 text[] default '{}',
  confirmed_at         timestamptz,
  unsubscribed_at      timestamptz,
  bounce_reason        text,
  provider             text default 'resend',             -- 'resend','substack','klaviyo'
  provider_contact_id  text,
  created_at           timestamptz not null default now(),
  unique (email)
);
CREATE INDEX IF NOT EXISTS ns_status_idx on public.newsletter_subscribers (status);
CREATE TABLE IF NOT EXISTS public.newsletter_issues (
  id                    uuid primary key default gen_random_uuid(),
  slug                  text unique not null,
  subject               text not null,
  preview_text          text,
  body_markdown         text not null,
  body_html             text,
  scheduled_at          timestamptz,
  sent_at               timestamptz,
  provider_broadcast_id text,
  audience_filter       jsonb not null default '{}'::jsonb,
  created_by            uuid references public.profiles(id) on delete set null,
  created_at            timestamptz not null default now()
);
CREATE TABLE IF NOT EXISTS public.newsletter_deliveries (
  issue_id            uuid not null references public.newsletter_issues(id) on delete cascade,
  subscriber_id       uuid not null references public.newsletter_subscribers(id) on delete cascade,
  status              text not null default 'queued',   -- queued,sent,opened,clicked,bounced,complained
  provider_message_id text,
  sent_at             timestamptz,
  opened_at           timestamptz,
  clicked_at          timestamptz,
  primary key (issue_id, subscriber_id)
);

-- =====================================================================
-- 4. Amazon Afiliados — rastreio de cliques
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.affiliate_clicks (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references public.profiles(id) on delete set null,
  book_id     uuid references public.books(id) on delete set null,
  target_url  text not null,
  tag         text,
  referrer    text,
  user_agent  text,
  ip_hash     text,
  created_at  timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS ac_book_idx on public.affiliate_clicks (book_id, created_at desc);

-- >>> 20260101002200_extra_content_and_activities.sql
-- Source: SDDBD2.md. Generated idempotent migration.
-- =====================================================================
-- 1. Materiais complementares (PDFs, slides, planilhas, datasets)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.chapter_extra_content (
  id            uuid primary key default gen_random_uuid(),
  chapter_id    uuid references public.chapters(id) on delete cascade,
  season_id     uuid references public.seasons(id) on delete cascade,
  book_id       uuid references public.books(id) on delete cascade,
  kind          extra_content_kind not null,
  title         text not null,
  description   text,
  storage_path  text,             -- quando hospedado no bucket 'chapter-extras'
  external_url  text,             -- quando for link externo (Notion, Figma, etc.)
  preview_url   text,
  size_bytes    bigint,
  mime_type     text,
  position      int not null default 0,
  is_public     boolean not null default true,
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS cec_chapter_idx on public.chapter_extra_content (chapter_id, position);
CREATE INDEX IF NOT EXISTS cec_season_idx  on public.chapter_extra_content (season_id);

-- =====================================================================
-- 2. Atividades / jogos / desafios interativos por capítulo
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.chapter_activities (
  id              uuid primary key default gen_random_uuid(),
  chapter_id      uuid not null references public.chapters(id) on delete cascade,
  kind            activity_kind not null,
  status          activity_status not null default 'draft',
  title           text not null,
  instructions    text,
  config          jsonb not null default '{}'::jsonb,   -- definição específica por tipo
  xp_reward       int not null default 20,
  time_limit_sec  int,
  position        int not null default 0,
  available_from  timestamptz,
  available_until timestamptz,
  created_by      uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  unique (chapter_id, position)
);
CREATE INDEX IF NOT EXISTS ca_status_idx on public.chapter_activities (status, chapter_id);
CREATE TABLE IF NOT EXISTS public.chapter_activity_attempts (
  id            uuid primary key default gen_random_uuid(),
  activity_id   uuid not null references public.chapter_activities(id) on delete cascade,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  score         int,
  max_score     int,
  duration_ms   int,
  result        jsonb not null default '{}'::jsonb,
  submitted_at  timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS caa_user_idx on public.chapter_activity_attempts (user_id, activity_id);

-- =====================================================================
-- 3. "Faça você mesmo" / caderno interativo — respostas livres
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.chapter_prompts (
  id           uuid primary key default gen_random_uuid(),
  chapter_id   uuid not null references public.chapters(id) on delete cascade,
  position     int not null,
  prompt       text not null,
  hint         text,
  min_chars    int default 20,
  max_chars    int default 4000,
  created_at   timestamptz not null default now(),
  unique (chapter_id, position)
);
CREATE TABLE IF NOT EXISTS public.chapter_prompt_responses (
  prompt_id    uuid not null references public.chapter_prompts(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  response     text not null check (length(response) between 1 and 4000),
  visibility   journal_visibility not null default 'private',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (prompt_id, user_id)
);

-- >>> 20260101002250_social_render_jobs.sql
-- Source: SDDBD2.md. Generated idempotent migration.
CREATE TABLE IF NOT EXISTS public.social_render_jobs (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  kind         social_template_kind not null,
  payload      jsonb not null default '{}'::jsonb,
  status       social_render_status not null default 'queued',
  image_url    text,
  error        text,
  created_at   timestamptz not null default now(),
  rendered_at  timestamptz
);
CREATE INDEX IF NOT EXISTS srj_user_idx   on public.social_render_jobs (user_id, created_at desc);
CREATE INDEX IF NOT EXISTS srj_status_idx on public.social_render_jobs (status);

alter table public.social_render_jobs enable row level security;
DROP POLICY IF EXISTS "srj_own_read" ON public.social_render_jobs;
CREATE POLICY "srj_own_read" ON public.social_render_jobs for select
  using (user_id = auth.uid() or public.is_admin());
DROP POLICY IF EXISTS "srj_own_insert" ON public.social_render_jobs;
CREATE POLICY "srj_own_insert" ON public.social_render_jobs for insert
  with check (user_id = auth.uid());
