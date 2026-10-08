-- Contexto de leitura do clube; os campos são opcionais para preservar os clubes atuais.
alter table public.user_clubs
  add column current_book_id uuid references public.books(id) on delete set null,
  add column current_season_id uuid references public.seasons(id) on delete set null,
  add column current_started_at timestamptz,
  add column current_ends_at timestamptz;

create index user_clubs_current_book_idx
  on public.user_clubs (current_book_id)
  where current_book_id is not null;
create index user_clubs_current_season_idx
  on public.user_clubs (current_season_id)
  where current_season_id is not null;
