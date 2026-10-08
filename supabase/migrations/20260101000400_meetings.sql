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
