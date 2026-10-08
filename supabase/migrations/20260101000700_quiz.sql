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
