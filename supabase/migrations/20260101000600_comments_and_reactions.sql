-- Source: SDDBD2.md. Generated idempotent migration.
-- Comentários hierárquicos + spoiler por capítulo
CREATE TABLE IF NOT EXISTS public.comments (
  id             uuid primary key default gen_random_uuid(),
  chapter_id     uuid not null references public.chapters(id) on delete cascade,
  user_id        uuid not null references public.profiles(id) on delete cascade,
  parent_id      uuid references public.comments(id) on delete cascade,
  content        text not null check (length(content) between 1 and 4000),
  is_spoiler     boolean not null default false,
  -- checkpoint: libera só p/ quem passou
  min_percent    numeric(5,2) default 0.00,
  likes_count    int not null default 0,
  replies_count  int not null default 0,
  edited_at      timestamptz,
  deleted_at     timestamptz,
  created_at     timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS comments_chapter_idx on public.comments (chapter_id, created_at desc);
CREATE INDEX IF NOT EXISTS comments_parent_idx  on public.comments (parent_id);
CREATE TABLE IF NOT EXISTS public.reactions (
  id           uuid primary key default gen_random_uuid(),
  comment_id   uuid not null references public.comments(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  kind         reaction_kind not null default 'like',
  created_at   timestamptz not null default now(),
  unique (comment_id, user_id)
);

-- Pergunta do anfitrião (poll simples "concordo/discordo/não sei")
CREATE TABLE IF NOT EXISTS public.host_prompts (
  id            uuid primary key default gen_random_uuid(),
  chapter_id    uuid not null references public.chapters(id) on delete cascade,
  question      text not null,
  options       jsonb not null,   -- ["Concordo","Discordo","Ainda não sei"]
  created_at    timestamptz not null default now()
);
CREATE TABLE IF NOT EXISTS public.host_prompt_votes (
  prompt_id   uuid not null references public.host_prompts(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  option_idx  int not null,
  created_at  timestamptz not null default now(),
  primary key (prompt_id, user_id)
);
