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
