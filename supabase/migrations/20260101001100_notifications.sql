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
