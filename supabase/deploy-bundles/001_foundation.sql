-- >>> 20260101000000_extensions_and_enums.sql
-- Source: SDDBD2.md. Generated idempotent migration.
-- Extensions
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";
create extension if not exists "vector";        -- P2: recomendações + match entre leitores
create extension if not exists "pg_trgm";       -- busca fuzzy de títulos

-- Enums globais
DO $$ BEGIN CREATE TYPE public.shelf_status AS ENUM ('want_to_read','reading','read','dnf'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.cycle_status AS ENUM ('planned','enrolling','active','finished'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.meeting_status AS ENUM ('scheduled','live','done','cancelled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.meeting_kind AS ENUM ('online','in_person','hybrid'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.user_role AS ENUM ('reader','ambassador','editor','admin'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.reaction_kind AS ENUM ('like','love','fire','clap','thinking'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.xp_source AS ENUM (
  'join_meeting','finish_chapter','comment','quiz_answer','finish_book','streak_bonus'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.notification_kind AS ENUM (
  'new_chapter','meeting_reminder','reply','mention','badge_unlocked','poll_open'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.poll_status AS ENUM ('open','closed'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.proposal_status AS ENUM ('pending','approved','rejected','winner'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE EXTENSION IF NOT EXISTS citext;

-- >>> 20260101000100_profiles.sql
-- Source: SDDBD2.md. Generated idempotent migration.
-- Perfis (1:1 com auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  username        citext unique not null,
  display_name    text   not null,
  avatar_url      text,
  bio             text,
  role            user_role not null default 'reader',
  level           text,                -- 'estudante','junior','pleno','senior','lideranca'
  whatsapp        text,
  lgpd_consent    boolean not null default false,
  lgpd_consent_at timestamptz,
  onboarding_done boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS profiles_username_idx on public.profiles (username);
-- citext is installed by the preceding extensions migration.

-- >>> 20260101000200_books_and_authors.sql
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

-- >>> 20260101000300_seasons_and_chapters.sql
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

-- >>> 20260101000400_meetings.sql
-- Source: SDDBD2.md. Generated idempotent migration.
CREATE TABLE IF NOT EXISTS public.meetings (
  id            uuid primary key default gen_random_uuid(),
  chapter_id    uuid not null references public.chapters(id) on delete cascade,
  title         text not null,
  kind          meeting_kind not null default 'online',
  status        meeting_status not null default 'scheduled',
  scheduled_at  timestamptz not null,
  duration_min  int default 90,
  meeting_url   text,
  location      text,
  slides_url    text,
  agenda        text,
  created_at    timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS meetings_schedule_idx on public.meetings (scheduled_at);

-- RSVP
CREATE TABLE IF NOT EXISTS public.meeting_rsvps (
  meeting_id  uuid not null references public.meetings(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  attending   boolean not null default true,
  created_at  timestamptz not null default now(),
  primary key (meeting_id, user_id)
);

-- >>> 20260101000500_progress.sql
-- Source: SDDBD2.md. Generated idempotent migration.
CREATE TABLE IF NOT EXISTS public.user_progress (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  chapter_id    uuid not null references public.chapters(id) on delete cascade,
  status        shelf_status not null default 'want_to_read',
  percent       numeric(5,2) not null default 0.00 check (percent between 0 and 100),
  finished_at   timestamptz,
  started_at    timestamptz default now(),
  updated_at    timestamptz not null default now(),
  unique (user_id, chapter_id)
);
CREATE INDEX IF NOT EXISTS user_progress_user_idx on public.user_progress (user_id);

-- >>> 20260101000600_comments_and_reactions.sql
-- Source: SDDBD2.md. Generated idempotent migration.
-- Comentários hierárquicos + spoiler por capítulo
CREATE TABLE IF NOT EXISTS public.comments (
  id             uuid primary key default gen_random_uuid(),
  chapter_id     uuid not null references public.chapters(id) on delete cascade,
  user_id        uuid not null references public.profiles(id) on delete cascade,
  parent_id      uuid references public.comments(id) on delete cascade,
  content        text not null check (length(content) between 1 and 4000),
  is_spoiler     boolean not null default false,
  -- checkpoint: libera só p/ quem passou
  min_percent    numeric(5,2) default 0.00,
  likes_count    int not null default 0,
  replies_count  int not null default 0,
  edited_at      timestamptz,
  deleted_at     timestamptz,
  created_at     timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS comments_chapter_idx on public.comments (chapter_id, created_at desc);
CREATE INDEX IF NOT EXISTS comments_parent_idx  on public.comments (parent_id);
CREATE TABLE IF NOT EXISTS public.reactions (
  id           uuid primary key default gen_random_uuid(),
  comment_id   uuid not null references public.comments(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  kind         reaction_kind not null default 'like',
  created_at   timestamptz not null default now(),
  unique (comment_id, user_id)
);

-- Pergunta do anfitrião (poll simples "concordo/discordo/não sei")
CREATE TABLE IF NOT EXISTS public.host_prompts (
  id            uuid primary key default gen_random_uuid(),
  chapter_id    uuid not null references public.chapters(id) on delete cascade,
  question      text not null,
  options       jsonb not null,   -- ["Concordo","Discordo","Ainda não sei"]
  created_at    timestamptz not null default now()
);
CREATE TABLE IF NOT EXISTS public.host_prompt_votes (
  prompt_id   uuid not null references public.host_prompts(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  option_idx  int not null,
  created_at  timestamptz not null default now(),
  primary key (prompt_id, user_id)
);

-- >>> 20260101000700_quiz.sql
-- Source: SDDBD2.md. Generated idempotent migration.
CREATE TABLE IF NOT EXISTS public.quiz_questions (
  id            uuid primary key default gen_random_uuid(),
  chapter_id    uuid not null references public.chapters(id) on delete cascade,
  position      int  not null,
  question      text not null,
  options       jsonb not null,          -- ["A","B","C","D"]
  correct_idx   int  not null,
  explanation   text,
  unique (chapter_id, position)
);
CREATE TABLE IF NOT EXISTS public.quiz_attempts (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  chapter_id    uuid not null references public.chapters(id) on delete cascade,
  score         int  not null,           -- acertos
  total         int  not null,
  duration_ms   int,
  created_at    timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS quiz_attempts_user_idx on public.quiz_attempts (user_id, chapter_id);
CREATE TABLE IF NOT EXISTS public.quiz_answers (
  attempt_id   uuid not null references public.quiz_attempts(id) on delete cascade,
  question_id  uuid not null references public.quiz_questions(id) on delete cascade,
  chosen_idx   int  not null,
  is_correct   boolean not null,
  primary key (attempt_id, question_id)
);

-- >>> 20260101000800_gamification.sql
-- Source: SDDBD2.md. Generated idempotent migration.
-- XP ledger (imutável)
CREATE TABLE IF NOT EXISTS public.xp_events (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  source       xp_source not null,
  amount       int not null check (amount > 0),
  ref_id       uuid,                -- chapter_id, comment_id, attempt_id, ...
  created_at   timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS xp_events_user_idx on public.xp_events (user_id, created_at desc);

-- Saldo materializado
CREATE TABLE IF NOT EXISTS public.user_xp (
  user_id       uuid primary key references public.profiles(id) on delete cascade,
  total_xp      int not null default 0,
  season_xp     int not null default 0,
  season_id     uuid references public.seasons(id),
  updated_at    timestamptz not null default now()
);

-- Streak
CREATE TABLE IF NOT EXISTS public.user_streaks (
  user_id           uuid primary key references public.profiles(id) on delete cascade,
  current_streak    int not null default 0,
  longest_streak    int not null default 0,
  last_activity_at  date,
  updated_at        timestamptz not null default now()
);

-- >>> 20260101000900_polls_and_votes.sql
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

-- >>> 20260101001000_achievements.sql
-- Source: SDDBD2.md. Generated idempotent migration.
CREATE TABLE IF NOT EXISTS public.achievements (
  id           uuid primary key default gen_random_uuid(),
  code         text unique not null,          -- 'first_book', 'streak_4w', 'machado_master'
  title        text not null,
  description  text not null,
  icon_url     text,
  xp_reward    int default 0,
  rule         jsonb not null                 -- {"type":"count","source":"finish_book","gte":1}
);
CREATE TABLE IF NOT EXISTS public.user_achievements (
  user_id         uuid not null references public.profiles(id) on delete cascade,
  achievement_id  uuid not null references public.achievements(id) on delete cascade,
  unlocked_at     timestamptz not null default now(),
  primary key (user_id, achievement_id)
);

-- >>> 20260101001100_notifications.sql
-- Source: SDDBD2.md. Generated idempotent migration.
CREATE TABLE IF NOT EXISTS public.notifications (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  kind         notification_kind not null,
  payload      jsonb not null default '{}'::jsonb,
  read_at      timestamptz,
  created_at   timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS notifications_user_idx on public.notifications (user_id, created_at desc);
CREATE TABLE IF NOT EXISTS public.push_subscriptions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  endpoint      text not null unique,
  p256dh        text not null,
  auth          text not null,
  created_at    timestamptz not null default now()
);

-- >>> 20260101001200_p2_tables.sql
-- Source: SDDBD2.md. Generated idempotent migration.
-- Comentários sincronizados com o vídeo (timestamps do YouTube)
CREATE TABLE IF NOT EXISTS public.video_timed_comments (
  id           uuid primary key default gen_random_uuid(),
  chapter_id   uuid not null references public.chapters(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  video_sec    int  not null,               -- segundo do vídeo
  content      text not null,
  likes_count  int  not null default 0,
  created_at   timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS vtc_chapter_sec_idx on public.video_timed_comments (chapter_id, video_sec);

-- Desafios anuais
CREATE TABLE IF NOT EXISTS public.challenges (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  description  text,
  year         int,
  prompt_rules jsonb not null,
  created_at   timestamptz not null default now()
);
CREATE TABLE IF NOT EXISTS public.user_challenges (
  user_id       uuid not null references public.profiles(id) on delete cascade,
  challenge_id  uuid not null references public.challenges(id) on delete cascade,
  progress      int not null default 0,
  completed_at  timestamptz,
  primary key (user_id, challenge_id)
);

-- Clubes criados por usuários (UGC)
CREATE TABLE IF NOT EXISTS public.user_clubs (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references public.profiles(id) on delete cascade,
  name         text not null,
  slug         text unique not null,
  description  text,
  is_private   boolean not null default false,
  created_at   timestamptz not null default now()
);
CREATE TABLE IF NOT EXISTS public.user_club_members (
  club_id    uuid not null references public.user_clubs(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  role       text not null default 'member',   -- 'owner','moderator','member'
  joined_at  timestamptz not null default now(),
  primary key (club_id, user_id)
);
