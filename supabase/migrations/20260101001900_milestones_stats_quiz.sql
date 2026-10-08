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
