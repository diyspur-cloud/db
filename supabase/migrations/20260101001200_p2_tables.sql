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
