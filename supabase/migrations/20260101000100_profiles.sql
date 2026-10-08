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
