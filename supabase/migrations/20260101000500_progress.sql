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
