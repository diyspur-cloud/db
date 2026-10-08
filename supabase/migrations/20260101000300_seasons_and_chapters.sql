-- Source: SDDBD2.md. Generated idempotent migration.
-- Temporadas / Ciclos
CREATE TABLE IF NOT EXISTS public.seasons (
  id              uuid primary key default gen_random_uuid(),
  number          int unique not null,
  title           text not null,                 -- "Dom Casmurro"
  slug            text unique not null,
  book_id         uuid not null references public.books(id),
  status          cycle_status not null default 'planned',
  description     text,
  starts_at       date,
  ends_at         date,
  default_time    time default '20:00',
  cover_url       text,
  created_at      timestamptz not null default now()
);

-- Capítulos (unidade completa de produto)
CREATE TABLE IF NOT EXISTS public.chapters (
  id               uuid primary key default gen_random_uuid(),
  season_id        uuid not null references public.seasons(id) on delete cascade,
  number           int not null,
  title            text not null,               -- "Capítulos I a V"
  reading_range    text,                        -- "pág. 1–35 · ~25 min"
  youtube_url      text,                        -- replay
  youtube_live_url text,                        -- futura live
  summary          text,
  published_at     timestamptz,
  created_at       timestamptz not null default now(),
  unique (season_id, number)
);
CREATE INDEX IF NOT EXISTS chapters_season_idx on public.chapters (season_id, number);
