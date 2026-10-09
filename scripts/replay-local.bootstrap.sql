-- REPLAY-ONLY BOOTSTRAP. This is not a production migration and is never
-- included in Supabase migration history. It supplies only the relations that
-- 20261008214832_add_book_reviews.sql and
-- 20261008214920_add_community_reading_views.sql need for a reduced replay.

create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;

create schema auth;
create schema private;

create function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

-- The community migration references this existing contract. The reduced
-- fixture keeps it invoker-only and deterministic; it is not an auth emulator.
create function public.is_admin()
returns boolean
language sql
stable
security invoker
as $$
  select false;
$$;

grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;

create table public.profiles (
  id uuid primary key,
  role text not null default 'reader'
);

create table public.books (
  id uuid primary key,
  title text not null
);

create table public.seasons (
  id uuid primary key,
  number integer not null,
  title text not null,
  slug text not null,
  book_id uuid not null,
  status text not null,
  starts_at date,
  created_at timestamptz not null default now()
);

create table public.chapters (
  id uuid primary key,
  season_id uuid not null,
  number integer not null,
  title text not null,
  published_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.user_progress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  chapter_id uuid not null,
  status text not null default 'want_to_read',
  percent numeric not null default 0,
  unique (user_id, chapter_id)
);

create table public.host_prompts (
  id uuid primary key,
  chapter_id uuid not null,
  question text not null,
  options jsonb not null
);

create table public.host_prompt_votes (
  prompt_id uuid not null,
  user_id uuid not null,
  option_idx integer not null,
  primary key (prompt_id, user_id)
);

create table public.book_mood_stats (
  book_id uuid primary key,
  mood_counts jsonb,
  pace_percent jsonb,
  plot_vs_character_avg numeric,
  sample_size integer
);

create table public.book_mood_votes (
  book_id uuid not null,
  user_id uuid not null,
  moods text[] not null default '{}',
  pace text,
  primary key (book_id, user_id)
);

create table public.user_clubs (
  id uuid primary key,
  name text not null,
  owner_id uuid not null,
  is_private boolean not null default false
);

create table public.user_club_members (
  club_id uuid not null,
  user_id uuid not null,
  role text not null default 'member',
  primary key (club_id, user_id)
);
