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
