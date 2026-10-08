-- Source: SDDBD2.md. Generated idempotent migration.
CREATE TABLE IF NOT EXISTS public.authors (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  slug          text unique not null,
  bio           text,
  photo_url     text,
  website_url   text,
  instagram     text,
  created_at    timestamptz not null default now()
);
CREATE TABLE IF NOT EXISTS public.books (
  id                uuid primary key default gen_random_uuid(),
  title             text not null,
  slug              text unique not null,
  author_id         uuid not null references public.authors(id) on delete restrict,
  isbn13            text unique,
  cover_url         text,
  synopsis          text,
  total_chapters    int,
  total_pages       int,
  publication_year  int,
  language          text default 'pt-BR',
  amazon_url        text,
  amazon_affiliate  text,
  ebook_url         text,
  audiobook_url     text,
  tags              text[] default '{}',
  embedding         vector(1536),                -- P2
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS books_slug_idx   on public.books (slug);
CREATE INDEX IF NOT EXISTS books_tags_gin   on public.books using gin (tags);
CREATE INDEX IF NOT EXISTS books_title_trgm on public.books using gin (title gin_trgm_ops);
