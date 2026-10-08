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
