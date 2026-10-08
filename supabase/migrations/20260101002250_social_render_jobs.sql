-- Source: SDDBD2.md. Generated idempotent migration.
CREATE TABLE IF NOT EXISTS public.social_render_jobs (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  kind         social_template_kind not null,
  payload      jsonb not null default '{}'::jsonb,
  status       social_render_status not null default 'queued',
  image_url    text,
  error        text,
  created_at   timestamptz not null default now(),
  rendered_at  timestamptz
);
CREATE INDEX IF NOT EXISTS srj_user_idx   on public.social_render_jobs (user_id, created_at desc);
CREATE INDEX IF NOT EXISTS srj_status_idx on public.social_render_jobs (status);

alter table public.social_render_jobs enable row level security;
DROP POLICY IF EXISTS "srj_own_read" ON public.social_render_jobs;
CREATE POLICY "srj_own_read" ON public.social_render_jobs for select
  using (user_id = auth.uid() or public.is_admin());
DROP POLICY IF EXISTS "srj_own_insert" ON public.social_render_jobs;
CREATE POLICY "srj_own_insert" ON public.social_render_jobs for insert
  with check (user_id = auth.uid());
