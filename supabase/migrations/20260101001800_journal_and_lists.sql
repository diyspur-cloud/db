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
