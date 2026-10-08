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
