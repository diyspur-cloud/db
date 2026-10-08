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
