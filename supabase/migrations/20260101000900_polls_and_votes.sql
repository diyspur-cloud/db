-- Source: SDDBD2.md. Generated idempotent migration.
-- Enquete "qual próximo livro?"
CREATE TABLE IF NOT EXISTS public.book_polls (
  id            uuid primary key default gen_random_uuid(),
  season_id     uuid references public.seasons(id) on delete cascade,
  title         text not null,
  status        poll_status not null default 'open',
  opens_at      timestamptz not null default now(),
  closes_at     timestamptz not null,
  created_at    timestamptz not null default now()
);
CREATE TABLE IF NOT EXISTS public.book_poll_options (
  id           uuid primary key default gen_random_uuid(),
  poll_id      uuid not null references public.book_polls(id) on delete cascade,
  book_id      uuid not null references public.books(id) on delete cascade,
  proposal     text,
  votes_count  int  not null default 0,
  unique (poll_id, book_id)
);
CREATE TABLE IF NOT EXISTS public.book_poll_votes (
  poll_id     uuid not null references public.book_polls(id) on delete cascade,
  option_id   uuid not null references public.book_poll_options(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (poll_id, user_id)
);
