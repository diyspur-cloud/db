# SDDBD.md — Supabase Database Development Document (Consolidado)

> **Objetivo:** Guia passo a passo para implementar **toda a camada de backend** do Clube de Leitura (inspirado em Reese + Fable + StoryGraph + leitura.dev) usando **Supabase** (Postgres + Auth + Storage + Realtime + Edge Functions).
>
> **Base de priorização:** `funcionalidades.md`
> - **P0 (MVP):** Livro → capítulos → calendário → vídeo YouTube → comentários → spoiler por capítulo → quiz → progresso → próximo capítulo → link Amazon.
> - **P1:** perfil do leitor, XP, streak, badges, enquetes, ranking, agenda/lembretes.
> - **P2:** votação do próximo livro, histórico de temporadas, comentários sincronizados com vídeo, recomendação personalizada, desafios anuais, clubes criados por usuários, match de leitores, eventos presenciais, painel de estatísticas avançadas.
> - **P3 (Complemento):** metadados ricos (content warnings, moods, pace), diário de leitura, listas personalizadas, buddy reads, milestones, metas anuais, feed social, match entre leitores via embeddings, monetização por assinatura, newsletter, conteúdo extra, atividades/jogos interativos e cards sociais.
>
> **Escopo deste documento consolidado:** cobre **integralmente** o `SDDBD.md` original e o `SDDBD.md — Complemento (Módulos Ausentes)`. Nenhum item é resumido. Nenhum item é repetido. A numeração das migrations preserva a ordem de dependência do documento original e continua no complemento a partir de `20260101001650_*`.

> **Estado de implementação (2026-10-09):** este arquivo nasceu como plano de implementação. O estado real do projeto remoto, das Edge Functions e dos testes está em [`README.md`](./README.md) e [`docs/deployment-status.md`](./docs/deployment-status.md); checkboxes nas fases originais continuam indicando trabalho de produto/front-end, não necessariamente ausência de schema. A extensão `book_reviews`, o contexto de leitura de `user_clubs`, curtidas do diário e regras de backend implementadas estão descritas abaixo e nas migrations versionadas. `user_progress.percent`/`status` é autodeclarado e informativo; uma view anti-spoiler não é uma fronteira de autorização para conteúdo não publicado.

---

## Índice

1. [Visão geral da arquitetura Supabase](#1-visão-geral-da-arquitetura-supabase)
2. [Estrutura de pastas do projeto](#2-estrutura-de-pastas-do-projeto)
3. [Setup inicial (Fase 0)](#3-setup-inicial-fase-0)
4. [Migrations SQL — Passo a passo](#4-migrations-sql--passo-a-passo)
   - 4.1 [Extensions e Enums](#41-extensions-e-enums)
   - 4.2 [Tabelas P0 — Núcleo editorial](#42-tabelas-p0--núcleo-editorial)
   - 4.3 [Tabelas P0 — Comunidade e Quiz](#43-tabelas-p0--comunidade-e-quiz)
   - 4.4 [Tabelas P1 — Gamificação](#44-tabelas-p1--gamificação)
   - 4.5 [Tabelas P2 — Expansão](#45-tabelas-p2--expansão)
   - 4.6 [Extensions e Enums complementares](#46-extensions-e-enums-complementares)
   - 4.7 [Metadados de Livros e Leitura](#47-metadados-de-livros-e-leitura)
   - 4.8 [Diário de Leitura e Listas Personalizadas](#48-diário-de-leitura-e-listas-personalizadas)
   - 4.9 [Milestones, Estatísticas e Média de Quiz](#49-milestones-estatísticas-e-média-de-quiz)
   - 4.10 [Feed Social, Posts e Match entre Leitores](#410-feed-social-posts-e-match-entre-leitores)
   - 4.11 [Monetização, Membros, Newsletter](#411-monetização-membros-newsletter)
   - 4.12 [Conteúdo Extra, Jogos e Atividades](#412-conteúdo-extra-jogos-e-atividades)
   - 4.13 [Social Render Jobs](#413-social-render-jobs)
5. [Row Level Security (RLS)](#5-row-level-security-rls)
   - 5.1 [RLS Base](#51-rls-base)
   - 5.2 [RLS complementar](#52-rls-complementar)
6. [Funções SQL, Triggers e Views](#6-funções-sql-triggers-e-views)
   - 6.1 [Funções e Triggers base](#61-funções-e-triggers-base)
   - 6.2 [Views base](#62-views-base)
   - 6.3 [Views materializadas e contadores agregados](#63-views-materializadas-e-contadores-agregados)
   - 6.4 [Funções SQL complementares](#64-funções-sql-complementares)
7. [Realtime (canais e publication)](#7-realtime-canais-e-publication)
8. [Storage Buckets e políticas](#8-storage-buckets-e-políticas)
9. [Edge Functions](#9-edge-functions)
10. [Autenticação e Perfis](#10-autenticação-e-perfis)
11. [Seed de dados (Dom Casmurro MVP + Complemento)](#11-seed-de-dados-dom-casmurro-mvp--complemento)
12. [Tipagens TypeScript](#12-tipagens-typescript)
13. [Cliente Supabase (frontend)](#13-cliente-supabase-frontend)
14. [Roadmap de execução (checklist)](#14-roadmap-de-execução-checklist)

---

## 1. Visão geral da arquitetura Supabase

```
┌─────────────────────────────────────────────────────────────────────┐
│                        FRONTEND (Next.js 15)                        │
│        @supabase/supabase-js + @supabase/ssr  (auth, RLS)           │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ HTTPS / WSS
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          SUPABASE                                   │
│  ┌─────────────┐  ┌───────────┐  ┌────────────┐  ┌──────────────┐   │
│  │    Auth     │  │ Postgres  │  │  Storage   │  │  Realtime    │   │
│  │  (JWT/RLS)  │  │  + RLS    │  │ (assets)   │  │ (broadcast)  │   │
│  └─────────────┘  └─────┬─────┘  └────────────┘  └──────────────┘   │
│                         │                                           │
│           ┌─────────────┴──────────────┐                            │
│           │  Edge Functions (Deno)     │                            │
│           │  • quiz-validate           │                            │
│           │  • award-xp                │                            │
│           │  • next-book-vote          │                            │
│           │  • scheduled-reminders     │                            │
│           │  • ai-recommendations      │                            │
│           │  • ai-user-embeddings      │                            │
│           │  • match-readers           │                            │
│           │  • newsletter-dispatch     │                            │
│           │  • stripe-webhook          │                            │
│           │  • social-render-card      │                            │
│           └────────────────────────────┘                            │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ webhooks
                            ▼
        ┌──────────────────────────────────────────────┐
        │ Integrações: Resend, Discord, YouTube,       │
        │ Amazon Afiliados, Google Calendar, Stripe,   │
        │ OpenAI (embeddings)                          │
        └──────────────────────────────────────────────┘
```

---

## 2. Estrutura de pastas do projeto

```
clube-leitura/
├── supabase/
│   ├── config.toml
│   ├── seed.sql
│   ├── seed_complement.sql
│   ├── migrations/
│   │   ├── 20260101000000_extensions_and_enums.sql
│   │   ├── 20260101000100_profiles.sql
│   │   ├── 20260101000200_books_and_authors.sql
│   │   ├── 20260101000300_seasons_and_chapters.sql
│   │   ├── 20260101000400_meetings.sql
│   │   ├── 20260101000500_progress.sql
│   │   ├── 20260101000600_comments_and_reactions.sql
│   │   ├── 20260101000700_quiz.sql
│   │   ├── 20260101000800_gamification.sql
│   │   ├── 20260101000900_polls_and_votes.sql
│   │   ├── 20260101001000_achievements.sql
│   │   ├── 20260101001100_notifications.sql
│   │   ├── 20260101001200_p2_tables.sql
│   │   ├── 20260101001300_rls_policies.sql
│   │   ├── 20260101001400_functions_and_triggers.sql
│   │   ├── 20260101001500_realtime.sql
│   │   ├── 20260101001600_storage.sql
│   │   ├── 20260101001650_extensions_and_enums_complement.sql
│   │   ├── 20260101001650_storage_complement.sql
│   │   ├── 20260101001700_book_metadata_and_reading.sql
│   │   ├── 20260101001800_journal_and_lists.sql
│   │   ├── 20260101001900_milestones_stats_quiz.sql
│   │   ├── 20260101002000_social_feed_and_match.sql
│   │   ├── 20260101002100_monetization_members_newsletter.sql
│   │   ├── 20260101002200_extra_content_and_activities.sql
│   │   ├── 20260101002250_social_render_jobs.sql
│   │   ├── 20260101002300_rls_complement.sql
│   │   ├── 20260101002400_views_and_counters.sql
│   │   ├── 20260101002450_realtime_complement.sql
│   │   └── 20260101002500_functions_complement.sql
│   └── functions/
│       ├── quiz-validate/index.ts
│       ├── award-xp/index.ts
│       ├── vote-next-book/index.ts
│       ├── scheduled-reminders/index.ts
│       ├── ai-recommendations/index.ts
│       ├── ai-user-embeddings/index.ts
│       ├── match-readers/index.ts
│       ├── newsletter-dispatch/index.ts
│       ├── stripe-webhook/index.ts
│       ├── social-render-card/index.ts
│       └── _shared/
│           ├── cors.ts
│           ├── supabaseAdmin.ts
│           └── types.ts
├── src/
│   ├── lib/
│   │   └── supabase/
│   │       ├── client.ts
│   │       ├── server.ts
│   │       ├── middleware.ts
│   │       └── database.types.ts   # gerado via `supabase gen types`
│   └── types/
│       ├── domain.ts
│       └── domain.complement.ts
├── .env.local
└── package.json
```

---

## 3. Setup inicial (Fase 0)

### 3.1 Comandos

```bash
# 1. Instalar Supabase CLI
brew install supabase/tap/supabase     # ou: npm i -g supabase

# 2. Iniciar projeto local
supabase init

# 3. Login e link ao projeto remoto
supabase login
supabase link --project-ref <PROJECT_REF>

# 4. Subir stack local (Docker)
supabase start

# 5. Rodar migrations e seed
supabase db reset
```

### 3.2 `.env.local`

```env
NEXT_PUBLIC_SUPABASE_URL=https://xxxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOi...
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOi...   # apenas servidor
SUPABASE_PROJECT_REF=xxxx

# Integrações
RESEND_API_KEY=re_...
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
AMAZON_AFFILIATE_TAG=clubedolivro-20
YOUTUBE_API_KEY=AIza...
OPENAI_API_KEY=sk-...
STRIPE_SECRET_KEY=sk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

---

## 4. Migrations SQL — Passo a passo

### 4.1 Extensions e Enums

**Arquivo:** `supabase/migrations/20260101000000_extensions_and_enums.sql`

```sql
-- Extensions
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";
create extension if not exists "vector";        -- P2: recomendações + match entre leitores
create extension if not exists "pg_trgm";       -- busca fuzzy de títulos

-- Enums globais
create type shelf_status      as enum ('want_to_read','reading','read','dnf');
create type cycle_status      as enum ('planned','enrolling','active','finished');
create type meeting_status    as enum ('scheduled','live','done','cancelled');
create type meeting_kind      as enum ('online','in_person','hybrid');
create type user_role         as enum ('reader','ambassador','editor','admin');
create type reaction_kind     as enum ('like','love','fire','clap','thinking');
create type xp_source         as enum (
  'join_meeting','finish_chapter','comment','quiz_answer','finish_book','streak_bonus'
);
create type notification_kind as enum (
  'new_chapter','meeting_reminder','reply','mention','badge_unlocked','poll_open'
);
create type poll_status       as enum ('open','closed');
create type proposal_status   as enum ('pending','approved','rejected','winner');
```

### 4.2 Tabelas P0 — Núcleo editorial

**Arquivo:** `supabase/migrations/20260101000100_profiles.sql`

```sql
-- Perfis (1:1 com auth.users)
create table public.profiles (
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
create index profiles_username_idx on public.profiles (username);
create extension if not exists citext;
```

**Arquivo:** `supabase/migrations/20260101000200_books_and_authors.sql`

```sql
create table public.authors (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  slug          text unique not null,
  bio           text,
  photo_url     text,
  website_url   text,
  instagram     text,
  created_at    timestamptz not null default now()
);

create table public.books (
  id                uuid primary key default gen_random_uuid(),
  title             text not null,
  slug              text unique not null,
  author_id         uuid not null references public.authors(id) on delete restrict,
  isbn13            text unique,
  cover_url         text,
  synopsis          text,
  total_chapters    int,
  total_pages       int,
  publication_year  int,
  language          text default 'pt-BR',
  amazon_url        text,
  amazon_affiliate  text,
  ebook_url         text,
  audiobook_url     text,
  tags              text[] default '{}',
  embedding         vector(1536),                -- P2
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index books_slug_idx   on public.books (slug);
create index books_tags_gin   on public.books using gin (tags);
create index books_title_trgm on public.books using gin (title gin_trgm_ops);
```

**Arquivo:** `supabase/migrations/20260101000300_seasons_and_chapters.sql`

```sql
-- Temporadas / Ciclos
create table public.seasons (
  id              uuid primary key default gen_random_uuid(),
  number          int unique not null,
  title           text not null,                 -- "Dom Casmurro"
  slug            text unique not null,
  book_id         uuid not null references public.books(id),
  status          cycle_status not null default 'planned',
  description     text,
  starts_at       date,
  ends_at         date,
  default_time    time default '20:00',
  cover_url       text,
  created_at      timestamptz not null default now()
);

-- Capítulos (unidade completa de produto)
create table public.chapters (
  id               uuid primary key default gen_random_uuid(),
  season_id        uuid not null references public.seasons(id) on delete cascade,
  number           int not null,
  title            text not null,               -- "Capítulos I a V"
  reading_range    text,                        -- "pág. 1–35 · ~25 min"
  youtube_url      text,                        -- replay
  youtube_live_url text,                        -- futura live
  summary          text,
  published_at     timestamptz,
  created_at       timestamptz not null default now(),
  unique (season_id, number)
);
create index chapters_season_idx on public.chapters (season_id, number);
```

### 4.3 Tabelas P0 — Comunidade e Quiz

**Arquivo:** `supabase/migrations/20260101000400_meetings.sql`

```sql
create table public.meetings (
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
create index meetings_schedule_idx on public.meetings (scheduled_at);

-- RSVP
create table public.meeting_rsvps (
  meeting_id  uuid not null references public.meetings(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  attending   boolean not null default true,
  created_at  timestamptz not null default now(),
  primary key (meeting_id, user_id)
);
```

**Arquivo:** `supabase/migrations/20260101000500_progress.sql`

```sql
create table public.user_progress (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  chapter_id    uuid not null references public.chapters (id) on delete cascade,
  status        shelf_status not null default 'want_to_read',
  percent       numeric(5,2) not null default 0.00 check (percent between 0 and 100),
  finished_at   timestamptz,
  started_at    timestamptz default now(),
  updated_at    timestamptz not null default now(),
  unique (user_id, chapter_id)
);
create index user_progress_user_idx on public.user_progress (user_id);
```

#### Semântica de progresso e spoilers (decisão de produto)

`user_progress.status` e `user_progress.percent` são **informações autodeclaradas pelo próprio leitor**, editáveis pelo titular; não existe no cliente uma telemetria confiável que prove leitura efetiva. `percent` serve a painéis pessoais e à preferência de ocultar spoilers da própria conta. Portanto, o bloqueio de spoiler baseado nesse percentual é uma conveniência de UX e **não** um controle de acesso a dados de terceiros, autorização administrativa, assinatura, pagamento ou outra decisão de segurança. A consulta continua restrita ao progresso do `auth.uid()` e às políticas de acesso do conteúdo.

XP por capítulo/livro também é uma recompensa gamificada, não uma permissão ou benefício financeiro: o backend confere a existência do progresso/atividade do titular, fixa os valores de XP e grava a referência uma única vez, mas a conclusão de leitura é autodeclarada. Não usar `status`/`percent` como prova de leitura auditável. Se o produto exigir progresso verificável, será necessário instrumentar um leitor controlado pelo servidor e separar um evento/estado verificado que o cliente não possa escrever; isso não é inferível do esquema atual.

**Arquivo:** `supabase/migrations/20260101000600_comments_and_reactions.sql`

```sql
-- Comentários hierárquicos + spoiler por capítulo
create table public.comments (
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
create index comments_chapter_idx on public.comments (chapter_id, created_at desc);
create index comments_parent_idx  on public.comments (parent_id);

create table public.reactions (
  id           uuid primary key default gen_random_uuid(),
  comment_id   uuid not null references public.comments(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  kind         reaction_kind not null default 'like',
  created_at   timestamptz not null default now(),
  unique (comment_id, user_id)
);

-- Pergunta do anfitrião (poll simples "concordo/discordo/não sei")
create table public.host_prompts (
  id            uuid primary key default gen_random_uuid(),
  chapter_id    uuid not null references public.chapters(id) on delete cascade,
  question      text not null,
  options       jsonb not null,   -- ["Concordo","Discordo","Ainda não sei"]
  created_at    timestamptz not null default now()
);

create table public.host_prompt_votes (
  prompt_id   uuid not null references public.host_prompts(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  option_idx  int not null,
  created_at  timestamptz not null default now(),
  primary key (prompt_id, user_id)
);
```

**Arquivo:** `supabase/migrations/20260101000700_quiz.sql`

```sql
create table public.quiz_questions (
  id            uuid primary key default gen_random_uuid(),
  chapter_id    uuid not null references public.chapters(id) on delete cascade,
  position      int  not null,
  question      text not null,
  options       jsonb not null,          -- ["A","B","C","D"]
  correct_idx   int  not null,
  explanation   text,
  unique (chapter_id, position)
);

create table public.quiz_attempts (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  chapter_id    uuid not null references public.chapters(id) on delete cascade,
  score         int  not null,           -- acertos
  total         int  not null,
  duration_ms   int,
  created_at    timestamptz not null default now()
);
create index quiz_attempts_user_idx on public.quiz_attempts (user_id, chapter_id);

create table public.quiz_answers (
  attempt_id   uuid not null references public.quiz_attempts(id) on delete cascade,
  question_id  uuid not null references public.quiz_questions(id) on delete cascade,
  chosen_idx   int  not null,
  is_correct   boolean not null,
  primary key (attempt_id, question_id)
);
```

### 4.4 Tabelas P1 — Gamificação

**Arquivo:** `supabase/migrations/20260101000800_gamification.sql`

```sql
-- XP ledger (imutável)
create table public.xp_events (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  source       xp_source not null,
  amount       int not null check (amount > 0),
  ref_id       uuid,                -- chapter_id, comment_id, attempt_id, ...
  created_at   timestamptz not null default now()
);
create index xp_events_user_idx on public.xp_events (user_id, created_at desc);

-- Saldo materializado
create table public.user_xp (
  user_id       uuid primary key references public.profiles(id) on delete cascade,
  total_xp      int not null default 0,
  season_xp     int not null default 0,
  season_id     uuid references public.seasons(id),
  updated_at    timestamptz not null default now()
);

-- Streak
create table public.user_streaks (
  user_id           uuid primary key references public.profiles(id) on delete cascade,
  current_streak    int not null default 0,
  longest_streak    int not null default 0,
  last_activity_at  date,
  updated_at        timestamptz not null default now()
);
```

**Arquivo:** `supabase/migrations/20260101000900_polls_and_votes.sql`

```sql
-- Enquete "qual próximo livro?"
create table public.book_polls (
  id            uuid primary key default gen_random_uuid(),
  season_id     uuid references public.seasons(id) on delete cascade,
  title         text not null,
  status        poll_status not null default 'open',
  opens_at      timestamptz not null default now(),
  closes_at     timestamptz not null,
  created_at    timestamptz not null default now()
);

create table public.book_poll_options (
  id           uuid primary key default gen_random_uuid(),
  poll_id      uuid not null references public.book_polls(id) on delete cascade,
  book_id      uuid not null references public.books(id) on delete cascade,
  proposal     text,
  votes_count  int  not null default 0,
  unique (poll_id, book_id)
);

create table public.book_poll_votes (
  poll_id     uuid not null references public.book_polls(id) on delete cascade,
  option_id   uuid not null references public.book_poll_options(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (poll_id, user_id)
);
```

**Arquivo:** `supabase/migrations/20260101001000_achievements.sql`

```sql
create table public.achievements (
  id           uuid primary key default gen_random_uuid(),
  code         text unique not null,          -- 'first_book', 'streak_4w', 'machado_master'
  title        text not null,
  description  text not null,
  icon_url     text,
  xp_reward    int default 0,
  rule         jsonb not null                 -- {"type":"count","source":"finish_book","gte":1}
);

create table public.user_achievements (
  user_id         uuid not null references public.profiles(id) on delete cascade,
  achievement_id  uuid not null references public.achievements(id) on delete cascade,
  unlocked_at     timestamptz not null default now(),
  primary key (user_id, achievement_id)
);
```

**Arquivo:** `supabase/migrations/20260101001100_notifications.sql`

```sql
create table public.notifications (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  kind         notification_kind not null,
  payload      jsonb not null default '{}'::jsonb,
  read_at      timestamptz,
  created_at   timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);

create table public.push_subscriptions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  endpoint      text not null unique,
  p256dh        text not null,
  auth          text not null,
  created_at    timestamptz not null default now()
);
```

### 4.5 Tabelas P2 — Expansão

**Arquivo:** `supabase/migrations/20260101001200_p2_tables.sql`

```sql
-- Comentários sincronizados com o vídeo (timestamps do YouTube)
create table public.video_timed_comments (
  id           uuid primary key default gen_random_uuid(),
  chapter_id   uuid not null references public.chapters(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  video_sec    int  not null,               -- segundo do vídeo
  content      text not null,
  likes_count  int  not null default 0,
  created_at   timestamptz not null default now()
);
create index vtc_chapter_sec_idx on public.video_timed_comments (chapter_id, video_sec);

-- Desafios anuais
create table public.challenges (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  description  text,
  year         int,
  prompt_rules jsonb not null,
  created_at   timestamptz not null default now()
);

create table public.user_challenges (
  user_id       uuid not null references public.profiles(id) on delete cascade,
  challenge_id  uuid not null references public.challenges(id) on delete cascade,
  progress      int not null default 0,
  completed_at  timestamptz,
  primary key (user_id, challenge_id)
);

-- Clubes criados por usuários (UGC)
create table public.user_clubs (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references public.profiles(id) on delete cascade,
  name         text not null,
  slug         text unique not null,
  description  text,
  is_private   boolean not null default false,
  current_book_id    uuid references public.books(id) on delete set null,
  current_season_id  uuid references public.seasons(id) on delete set null,
  current_started_at timestamptz,
  current_ends_at    timestamptz,
  created_at   timestamptz not null default now()
);

create table public.user_club_members (
  club_id    uuid not null references public.user_clubs(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  role       text not null default 'member',   -- 'owner','moderator','member'
  joined_at  timestamptz not null default now(),
  primary key (club_id, user_id)
);

-- Avaliações de livro (extensão aditiva implantada em 2026-10).
create table public.book_reviews (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  rating numeric(3,2) check (rating is null or rating between 0 and 5),
  spice_level integer check (spice_level is null or spice_level between 0 and 5),
  review_text text check (review_text is null or length(review_text) <= 20000),
  contains_spoilers boolean not null default false,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint book_reviews_one_per_user_book unique (book_id, user_id)
);
```

`book_reviews` usa RLS: o público lê apenas conteúdo ativo; o titular/admin pode consultar seu próprio conteúdo removido; escrita é limitada ao titular ou admin. A view comunitária expõe agregados, não PII. Consulte `20261008214832_add_book_reviews.sql` e as migrations posteriores de hardening para grants/policies efetivamente ativos.

### 4.6 Extensions e Enums complementares

**Arquivo:** `supabase/migrations/20260101001650_extensions_and_enums_complement.sql`

```sql
-- Extensions adicionais (além das já carregadas em 000)
create extension if not exists "unaccent";     -- busca normalizada em newsletters/feed
create extension if not exists "btree_gin";    -- índices compostos em arrays/jsonb

-- Enums complementares
create type mood_kind as enum (
  'adventurous','emotional','dark','funny','hopeful','informative',
  'inspiring','lighthearted','mysterious','reflective','sad','tense','challenging'
);

create type pace_kind                 as enum ('slow','medium','fast');
create type content_warning_severity  as enum ('minor','moderate','graphic');
create type editorial_pick_kind       as enum ('book_of_the_month','editorial_pick','community_pick','staff_pick');
create type reading_list_visibility   as enum ('private','unlisted','public');
create type reading_list_item_kind    as enum ('book','chapter','quote','external');
create type journal_visibility        as enum ('private','friends','club','public');
create type feed_post_kind            as enum ('quote','review','shelf_update','progress','list','club_invite','link','photo','poll');
create type feed_visibility           as enum ('public','followers','club','private');
create type follow_status             as enum ('pending','accepted','blocked');
create type member_tier               as enum ('free','plus','pro','patron','corporate');
create type subscription_status       as enum ('trialing','active','past_due','canceled','paused','incomplete');
create type payment_provider          as enum ('stripe','mercado_pago','pagseguro','manual');
create type newsletter_status         as enum ('pending','confirmed','unsubscribed','bounced','complained');
create type newsletter_frequency      as enum ('daily','weekly','monthly','special_only');
create type extra_content_kind        as enum ('pdf','slides','audio','video','link','spreadsheet','deck','notebook','dataset','template');
create type activity_kind             as enum ('quiz','crossword','word_search','poll','trivia','flashcards','debate_prompt','drawing_prompt','roleplay','essay_prompt','timed_challenge');
create type activity_status           as enum ('draft','published','archived');
create type social_template_kind      as enum ('quote_card','progress_card','milestone_card','review_card','list_card','aura_card','streak_card');
create type social_render_status      as enum ('queued','rendered','failed','expired');
```

### 4.7 Metadados de Livros e Leitura

**Arquivo:** `supabase/migrations/20260101001700_book_metadata_and_reading.sql`

```sql
-- =====================================================================
-- 1. Content Warnings estruturados
-- =====================================================================
create table public.content_warnings (
  id             uuid primary key default gen_random_uuid(),
  code           text unique not null,     -- 'violence','grief','abuse','self_harm', ...
  label          text not null,            -- rótulo humano em pt-BR
  description    text,
  category       text,                     -- 'mental_health','violence','identity','substance', ...
  created_at     timestamptz not null default now()
);

create table public.book_content_warnings (
  id              uuid primary key default gen_random_uuid(),
  book_id         uuid not null references public.books(id) on delete cascade,
  warning_id      uuid not null references public.content_warnings(id) on delete cascade,
  severity        content_warning_severity not null default 'moderate',
  is_community    boolean not null default true,   -- true = gerado pela comunidade; false = curadoria editorial
  reported_by     uuid references public.profiles(id) on delete set null,
  community_votes int not null default 1,
  notes           text,
  created_at      timestamptz not null default now(),
  unique (book_id, warning_id)
);
create index bcw_book_idx     on public.book_content_warnings (book_id);
create index bcw_severity_idx on public.book_content_warnings (severity);

-- Votos individuais para recalcular community_votes sem depender de contador
create table public.book_content_warning_votes (
  warning_row_id uuid not null references public.book_content_warnings(id) on delete cascade,
  user_id        uuid not null references public.profiles(id) on delete cascade,
  agrees         boolean not null default true,
  created_at     timestamptz not null default now(),
  primary key (warning_row_id, user_id)
);

-- =====================================================================
-- 2. Mood / Pace / Plot-vs-Character por livro
-- =====================================================================
create table public.book_mood_stats (
  book_id        uuid primary key references public.books(id) on delete cascade,
  mood_counts    jsonb not null default '{}'::jsonb,   -- {"dark": 42, "emotional": 38, ...}
  mood_percent   jsonb not null default '{}'::jsonb,   -- {"dark": 0.42, ...}
  pace_percent   jsonb not null default '{"slow":0,"medium":0,"fast":0}'::jsonb,
  plot_vs_character_avg numeric(3,2) not null default 0.50, -- 0=enredo, 1=personagem
  sample_size    int not null default 0,
  updated_at     timestamptz not null default now()
);

create table public.book_mood_votes (
  book_id      uuid not null references public.books(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  moods        mood_kind[] not null default '{}',
  pace         pace_kind,
  plot_vs_character numeric(3,2) check (plot_vs_character between 0 and 1),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (book_id, user_id)
);
create index bmv_moods_gin on public.book_mood_votes using gin (moods);

-- Rótulos display dos moods (i18n pt-BR)
create table public.mood_labels (
  mood       mood_kind primary key,
  label_pt   text not null,
  color_hex  text not null,
  icon       text
);

-- =====================================================================
-- 3. Escolha editorial (Book of the Month / Destaques)
-- =====================================================================
create table public.editorial_picks (
  id           uuid primary key default gen_random_uuid(),
  book_id      uuid not null references public.books(id) on delete cascade,
  season_id    uuid references public.seasons(id) on delete set null,
  kind         editorial_pick_kind not null default 'book_of_the_month',
  reference_month date not null,             -- primeiro dia do mês de referência
  title        text,                         -- headline editorial
  rationale    text,                         -- "por que escolhemos"
  media_url    text,                         -- vídeo/áudio da curadoria
  is_active    boolean not null default true,
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  unique (kind, reference_month)
);
create index editorial_picks_month_idx on public.editorial_picks (reference_month desc);

-- =====================================================================
-- 4. Buddy Reads (leitura em dupla/trio com checkpoints)
-- =====================================================================
create table public.buddy_reads (
  id            uuid primary key default gen_random_uuid(),
  book_id       uuid not null references public.books(id) on delete cascade,
  season_id     uuid references public.seasons(id) on delete set null,
  title         text,
  owner_id      uuid not null references public.profiles(id) on delete cascade,
  is_private    boolean not null default true,
  max_members   int not null default 3 check (max_members between 2 and 10),
  start_date    date,
  end_date      date,
  created_at    timestamptz not null default now()
);

create table public.buddy_read_members (
  buddy_read_id uuid not null references public.buddy_reads(id) on delete cascade,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  joined_at     timestamptz not null default now(),
  primary key (buddy_read_id, user_id)
);

create table public.buddy_read_checkpoints (
  id             uuid primary key default gen_random_uuid(),
  buddy_read_id  uuid not null references public.buddy_reads(id) on delete cascade,
  position       int not null,
  title          text not null,
  page_from      int,
  page_to        int,
  percent_from   numeric(5,2),
  percent_to     numeric(5,2),
  target_date    date,
  unique (buddy_read_id, position)
);
```

### 4.8 Diário de Leitura e Listas Personalizadas

**Arquivo:** `supabase/migrations/20260101001800_journal_and_lists.sql`

```sql
-- =====================================================================
-- 1. Diário de leitura (texto livre por sessão)
-- =====================================================================
create table public.reading_journal_entries (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles(id) on delete cascade,
  book_id        uuid not null references public.books(id) on delete cascade,
  chapter_id     uuid references public.chapters(id) on delete set null,
  season_id      uuid references public.seasons(id) on delete set null,
  entry_date     date not null default current_date,
  page_from      int,
  page_to        int,
  percent_at     numeric(5,2) check (percent_at between 0 and 100),
  minutes_read   int default 0,
  mood_at_time   mood_kind,
  title          text,
  body           text not null check (length(body) between 1 and 20000),
  visibility     journal_visibility not null default 'private',
  is_spoiler     boolean not null default false,
  min_percent    numeric(5,2) not null default 0.00,
  likes_count    int not null default 0,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index rje_user_date_idx  on public.reading_journal_entries (user_id, entry_date desc);
create index rje_book_idx       on public.reading_journal_entries (book_id);
create index rje_chapter_idx    on public.reading_journal_entries (chapter_id);
create index rje_visibility_idx on public.reading_journal_entries (visibility);

-- Anexos de mídia do diário (fotos, áudios, prints)
create table public.reading_journal_attachments (
  id            uuid primary key default gen_random_uuid(),
  entry_id      uuid not null references public.reading_journal_entries(id) on delete cascade,
  storage_path  text not null,
  mime_type     text not null,
  size_bytes    bigint not null,
  created_at    timestamptz not null default now()
);

-- Uma curtida por leitor/entrada; likes_count é mantido pelo trigger no banco.
create table public.reading_journal_likes (
  entry_id   uuid not null references public.reading_journal_entries(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default statement_timestamp(),
  primary key (entry_id, user_id)
);

-- =====================================================================
-- 2. Listas personalizadas (temáticas, colaborativas e curadas)
-- =====================================================================
create table public.reading_lists (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references public.profiles(id) on delete cascade,
  slug          text unique not null,
  title         text not null,
  description   text,
  cover_url     text,
  visibility    reading_list_visibility not null default 'private',
  is_collaborative boolean not null default false,
  theme         text,                 -- ex: 'Machado de Assis', 'Ficção Científica BR'
  tags          text[] default '{}',
  items_count   int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index rl_owner_idx      on public.reading_lists (owner_id);
create index rl_visibility_idx on public.reading_lists (visibility);
create index rl_tags_gin       on public.reading_lists using gin (tags);

create table public.reading_list_items (
  id           uuid primary key default gen_random_uuid(),
  list_id      uuid not null references public.reading_lists(id) on delete cascade,
  kind         reading_list_item_kind not null default 'book',
  book_id      uuid references public.books(id) on delete cascade,
  chapter_id   uuid references public.chapters(id) on delete cascade,
  external_url text,
  quote_text   text,
  note         text,
  position     int not null default 0,
  added_by     uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now()
);
create index rli_list_idx on public.reading_list_items (list_id, position);

create table public.reading_list_collaborators (
  list_id  uuid not null references public.reading_lists(id) on delete cascade,
  user_id  uuid not null references public.profiles(id) on delete cascade,
  can_edit boolean not null default true,
  added_at timestamptz not null default now(),
  primary key (list_id, user_id)
);

-- =====================================================================
-- 3. "Up Next" (fila de prioridade da estante)
-- =====================================================================
create table public.user_up_next (
  user_id   uuid not null references public.profiles(id) on delete cascade,
  book_id   uuid not null references public.books(id) on delete cascade,
  position  int not null check (position between 1 and 5),
  added_at  timestamptz not null default now(),
  primary key (user_id, book_id),
  unique (user_id, position)
);
```

### 4.9 Milestones, Estatísticas e Média de Quiz

**Arquivo:** `supabase/migrations/20260101001900_milestones_stats_quiz.sql`

```sql
-- =====================================================================
-- 1. Milestones (marcos) — definidos por criador ou automáticos
-- =====================================================================
create table public.milestones (
  id             uuid primary key default gen_random_uuid(),
  chapter_id     uuid references public.chapters(id) on delete cascade,
  season_id      uuid not null references public.seasons(id) on delete cascade,
  book_id        uuid not null references public.books(id) on delete cascade,
  position       int  not null,
  title          text not null,
  description    text,
  kind           text not null default 'auto',  -- 'auto' | 'custom'
  page_from      int,
  page_to        int,
  chapter_from   int,
  chapter_to     int,
  percent_from   numeric(5,2),
  percent_to     numeric(5,2),
  target_date    date,
  xp_reward      int not null default 15,
  created_by     uuid references public.profiles(id) on delete set null,
  created_at     timestamptz not null default now(),
  unique (season_id, position)
);
create index milestones_chapter_idx on public.milestones (chapter_id, position);

create table public.user_milestone_progress (
  user_id       uuid not null references public.profiles(id) on delete cascade,
  milestone_id  uuid not null references public.milestones(id) on delete cascade,
  completed_at  timestamptz,
  xp_awarded    boolean not null default false,
  created_at    timestamptz not null default now(),
  primary key (user_id, milestone_id)
);

-- =====================================================================
-- 2. Média de quizzes (materializada)
-- =====================================================================
create table public.user_quiz_averages (
  user_id           uuid primary key references public.profiles(id) on delete cascade,
  attempts_total    int not null default 0,
  score_sum         int not null default 0,
  total_sum         int not null default 0,
  average_percent   numeric(5,2) not null default 0.00,
  best_percent      numeric(5,2) not null default 0.00,
  last_attempt_at   timestamptz,
  updated_at        timestamptz not null default now()
);

create table public.chapter_quiz_averages (
  chapter_id        uuid primary key references public.chapters(id) on delete cascade,
  attempts_total    int not null default 0,
  average_percent   numeric(5,2) not null default 0.00,
  perfect_count     int not null default 0,
  updated_at        timestamptz not null default now()
);

-- =====================================================================
-- 3. Metas anuais e desafios de leitura
-- =====================================================================
create table public.reading_goals (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles(id) on delete cascade,
  year           int not null,
  target_books   int,
  target_pages   int,
  target_minutes int,
  created_at     timestamptz not null default now(),
  unique (user_id, year)
);

create table public.reading_goal_progress (
  goal_id      uuid primary key references public.reading_goals(id) on delete cascade,
  books_done   int not null default 0,
  pages_done   int not null default 0,
  minutes_done int not null default 0,
  updated_at   timestamptz not null default now()
);

-- =====================================================================
-- 4. Desafios temáticos baseados em prompts
-- =====================================================================
create table public.challenge_prompts (
  id            uuid primary key default gen_random_uuid(),
  challenge_id  uuid not null references public.challenges(id) on delete cascade,
  position      int not null,
  prompt        text not null,             -- "Livro traduzido", "Autor indígena"
  book_id       uuid references public.books(id) on delete set null,
  completed_at  timestamptz,
  completed_by  uuid references public.profiles(id) on delete set null,
  unique (challenge_id, position)
);
```

### 4.10 Feed Social, Posts e Match entre Leitores

**Arquivo:** `supabase/migrations/20260101002000_social_feed_and_match.sql`

```sql
-- =====================================================================
-- 1. Posts livres (feed social)
-- =====================================================================
create table public.feed_posts (
  id             uuid primary key default gen_random_uuid(),
  author_id      uuid not null references public.profiles(id) on delete cascade,
  kind           feed_post_kind not null default 'quote',
  visibility     feed_visibility not null default 'public',
  club_id        uuid references public.user_clubs(id) on delete set null,
  book_id        uuid references public.books(id) on delete set null,
  chapter_id     uuid references public.chapters(id) on delete set null,
  season_id      uuid references public.seasons(id) on delete set null,
  body           text check (length(body) <= 8000),
  quote_text     text,
  link_url       text,
  cover_url      text,
  metadata       jsonb not null default '{}'::jsonb,
  is_spoiler     boolean not null default false,
  min_percent    numeric(5,2) not null default 0.00,
  likes_count    int not null default 0,
  comments_count int not null default 0,
  shares_count   int not null default 0,
  deleted_at     timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index feed_posts_public_idx on public.feed_posts (created_at desc) where deleted_at is null and visibility = 'public';
create index feed_posts_author_idx on public.feed_posts (author_id, created_at desc);
create index feed_posts_club_idx   on public.feed_posts (club_id, created_at desc);
create index feed_posts_book_idx   on public.feed_posts (book_id);

create table public.feed_post_media (
  id           uuid primary key default gen_random_uuid(),
  post_id      uuid not null references public.feed_posts(id) on delete cascade,
  storage_path text not null,
  mime_type    text not null,
  position     int not null default 0,
  created_at   timestamptz not null default now()
);

create table public.feed_post_likes (
  post_id    uuid not null references public.feed_posts(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table public.feed_post_comments (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid not null references public.feed_posts(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  parent_id   uuid references public.feed_post_comments(id) on delete cascade,
  content     text not null check (length(content) between 1 and 4000),
  is_spoiler  boolean not null default false,
  likes_count int not null default 0,
  deleted_at  timestamptz,
  created_at  timestamptz not null default now()
);
create index fpc_post_idx on public.feed_post_comments (post_id, created_at desc);

-- =====================================================================
-- 2. Seguir / amigos (para feed "followers" e match social)
-- =====================================================================
create table public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  followed_id uuid not null references public.profiles(id) on delete cascade,
  status      follow_status not null default 'accepted',
  created_at  timestamptz not null default now(),
  primary key (follower_id, followed_id),
  check (follower_id <> followed_id)
);
create index follows_followed_idx on public.follows (followed_id, status);

-- =====================================================================
-- 3. Preferências de leitura (questionário base do match)
-- =====================================================================
create table public.user_reading_preferences (
  user_id                  uuid primary key references public.profiles(id) on delete cascade,
  favorite_genres          text[] default '{}',
  disliked_genres          text[] default '{}',
  favorite_tropes          text[] default '{}',
  preferred_pacing         pace_kind[] default '{}',
  preferred_moods          mood_kind[] default '{}',
  avoided_content_warnings text[] default '{}',
  annual_goal_books        int default 12,
  annual_goal_pages        int,
  reading_language         text default 'pt-BR',
  updated_at               timestamptz not null default now()
);

-- =====================================================================
-- 4. Match entre leitores (similaridade entre perfis)
-- =====================================================================
create table public.user_reading_embeddings (
  user_id     uuid primary key references public.profiles(id) on delete cascade,
  embedding   vector(1536) not null,
  source_hash text,             -- hash do snapshot de histórico usado para gerar
  updated_at  timestamptz not null default now()
);
create index ure_embedding_idx on public.user_reading_embeddings
  using ivfflat (embedding vector_cosine_ops) with (lists = 100);

create table public.user_match_cache (
  user_id      uuid not null references public.profiles(id) on delete cascade,
  matched_id   uuid not null references public.profiles(id) on delete cascade,
  similarity   numeric(5,4) not null,
  shared_books int not null default 0,
  shared_moods mood_kind[] default '{}',
  computed_at  timestamptz not null default now(),
  primary key (user_id, matched_id),
  check (user_id <> matched_id)
);
create index umc_user_sim_idx on public.user_match_cache (user_id, similarity desc);
```

### 4.11 Monetização, Membros, Newsletter

**Arquivo:** `supabase/migrations/20260101002100_monetization_members_newsletter.sql`

```sql
-- =====================================================================
-- 1. Planos de assinatura / tiers
-- =====================================================================
create table public.membership_plans (
  id              uuid primary key default gen_random_uuid(),
  code            text unique not null,        -- 'free','plus_monthly','plus_annual','patron'
  tier            member_tier not null,
  name            text not null,
  description     text,
  price_cents     int not null default 0,
  currency        text not null default 'BRL',
  interval        text not null default 'month', -- 'month','year','lifetime'
  stripe_price_id text,
  perks           jsonb not null default '[]'::jsonb,  -- [{code,label,description}]
  is_active       boolean not null default true,
  created_at      timestamptz not null default now()
);

-- =====================================================================
-- 2. Assinaturas dos usuários
-- =====================================================================
create table public.user_subscriptions (
  id                       uuid primary key default gen_random_uuid(),
  user_id                  uuid not null references public.profiles(id) on delete cascade,
  plan_id                  uuid not null references public.membership_plans(id) on delete restrict,
  status                   subscription_status not null default 'incomplete',
  provider                 payment_provider not null default 'stripe',
  provider_customer_id     text,
  provider_subscription_id text unique,
  current_period_start     timestamptz,
  current_period_end       timestamptz,
  cancel_at_period_end     boolean not null default false,
  canceled_at              timestamptz,
  trial_end                timestamptz,
  metadata                 jsonb not null default '{}'::jsonb,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);
create index us_user_idx   on public.user_subscriptions (user_id);
create index us_status_idx on public.user_subscriptions (status);

-- Registro bruto de eventos de gateway (auditoria/replay)
create table public.payment_events (
  id             uuid primary key default gen_random_uuid(),
  provider       payment_provider not null,
  event_id       text not null,
  event_type     text not null,
  user_id        uuid references public.profiles(id) on delete set null,
  payload        jsonb not null,
  processed_at   timestamptz,
  created_at     timestamptz not null default now(),
  unique (provider, event_id)
);

-- Benefícios consumidos pelo usuário (ex: desconto aplicado, ebook liberado)
create table public.user_membership_perks (
  user_id     uuid not null references public.profiles(id) on delete cascade,
  perk_code   text not null,
  payload     jsonb not null default '{}'::jsonb,
  granted_at  timestamptz not null default now(),
  expires_at  timestamptz,
  primary key (user_id, perk_code)
);

-- =====================================================================
-- 3. Newsletter (inscrições e disparos)
-- =====================================================================
create table public.newsletter_subscribers (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid references public.profiles(id) on delete set null,
  email                citext not null,
  name                 text,
  status               newsletter_status not null default 'pending',
  frequency            newsletter_frequency not null default 'weekly',
  source               text,                              -- 'site','checkout','import','club'
  tags                 text[] default '{}',
  confirmed_at         timestamptz,
  unsubscribed_at      timestamptz,
  bounce_reason        text,
  provider             text default 'resend',             -- 'resend','substack','klaviyo'
  provider_contact_id  text,
  created_at           timestamptz not null default now(),
  unique (email)
);
create index ns_status_idx on public.newsletter_subscribers (status);

create table public.newsletter_issues (
  id                    uuid primary key default gen_random_uuid(),
  slug                  text unique not null,
  subject               text not null,
  preview_text          text,
  body_markdown         text not null,
  body_html             text,
  scheduled_at          timestamptz,
  sent_at               timestamptz,
  provider_broadcast_id text,
  audience_filter       jsonb not null default '{}'::jsonb,
  created_by            uuid references public.profiles(id) on delete set null,
  created_at            timestamptz not null default now()
);

create table public.newsletter_deliveries (
  issue_id            uuid not null references public.newsletter_issues(id) on delete cascade,
  subscriber_id       uuid not null references public.newsletter_subscribers(id) on delete cascade,
  status              text not null default 'queued',   -- queued,sent,opened,clicked,bounced,complained
  provider_message_id text,
  sent_at             timestamptz,
  opened_at           timestamptz,
  clicked_at          timestamptz,
  primary key (issue_id, subscriber_id)
);

-- =====================================================================
-- 4. Amazon Afiliados — rastreio de cliques
-- =====================================================================
create table public.affiliate_clicks (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references public.profiles(id) on delete set null,
  book_id     uuid references public.books(id) on delete set null,
  target_url  text not null,
  tag         text,
  referrer    text,
  user_agent  text,
  ip_hash     text,
  created_at  timestamptz not null default now()
);
create index ac_book_idx on public.affiliate_clicks (book_id, created_at desc);
```

### 4.12 Conteúdo Extra, Jogos e Atividades

**Arquivo:** `supabase/migrations/20260101002200_extra_content_and_activities.sql`

```sql
-- =====================================================================
-- 1. Materiais complementares (PDFs, slides, planilhas, datasets)
-- =====================================================================
create table public.chapter_extra_content (
  id            uuid primary key default gen_random_uuid(),
  chapter_id    uuid references public.chapters(id) on delete cascade,
  season_id     uuid references public.seasons(id) on delete cascade,
  book_id       uuid references public.books(id) on delete cascade,
  kind          extra_content_kind not null,
  title         text not null,
  description   text,
  storage_path  text,             -- quando hospedado no bucket 'chapter-extras'
  external_url  text,             -- quando for link externo (Notion, Figma, etc.)
  preview_url   text,
  size_bytes    bigint,
  mime_type     text,
  position      int not null default 0,
  is_public     boolean not null default true,
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now()
);
create index cec_chapter_idx on public.chapter_extra_content (chapter_id, position);
create index cec_season_idx  on public.chapter_extra_content (season_id);

-- =====================================================================
-- 2. Atividades / jogos / desafios interativos por capítulo
-- =====================================================================
create table public.chapter_activities (
  id              uuid primary key default gen_random_uuid(),
  chapter_id      uuid not null references public.chapters(id) on delete cascade,
  kind            activity_kind not null,
  status          activity_status not null default 'draft',
  title           text not null,
  instructions    text,
  config          jsonb not null default '{}'::jsonb,   -- definição específica por tipo
  xp_reward       int not null default 20,
  time_limit_sec  int,
  position        int not null default 0,
  available_from  timestamptz,
  available_until timestamptz,
  created_by      uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  unique (chapter_id, position)
);
create index ca_status_idx on public.chapter_activities (status, chapter_id);

create table public.chapter_activity_attempts (
  id            uuid primary key default gen_random_uuid(),
  activity_id   uuid not null references public.chapter_activities(id) on delete cascade,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  score         int,
  max_score     int,
  duration_ms   int,
  result        jsonb not null default '{}'::jsonb,
  submitted_at  timestamptz not null default now()
);
create index caa_user_idx on public.chapter_activity_attempts (user_id, activity_id);

-- =====================================================================
-- 3. "Faça você mesmo" / caderno interativo — respostas livres
-- =====================================================================
create table public.chapter_prompts (
  id           uuid primary key default gen_random_uuid(),
  chapter_id   uuid not null references public.chapters(id) on delete cascade,
  position     int not null,
  prompt       text not null,
  hint         text,
  min_chars    int default 20,
  max_chars    int default 4000,
  created_at   timestamptz not null default now(),
  unique (chapter_id, position)
);

create table public.chapter_prompt_responses (
  prompt_id    uuid not null references public.chapter_prompts(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  response     text not null check (length(response) between 1 and 4000),
  visibility   journal_visibility not null default 'private',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (prompt_id, user_id)
);
```

### 4.13 Social Render Jobs

**Arquivo:** `supabase/migrations/20260101002250_social_render_jobs.sql`

```sql
create table public.social_render_jobs (
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
create index srj_user_idx   on public.social_render_jobs (user_id, created_at desc);
create index srj_status_idx on public.social_render_jobs (status);

alter table public.social_render_jobs enable row level security;
create policy "srj_own_read" on public.social_render_jobs for select
  using (user_id = auth.uid() or public.is_admin());
create policy "srj_own_insert" on public.social_render_jobs for insert
  with check (user_id = auth.uid());
```

---

## 5. Row Level Security (RLS)

### 5.1 RLS Base

**Arquivo:** `supabase/migrations/20260101001300_rls_policies.sql`

```sql
-- Habilitar RLS em todas as tabelas públicas
alter table public.profiles             enable row level security;
alter table public.authors              enable row level security;
alter table public.books                enable row level security;
alter table public.seasons              enable row level security;
alter table public.chapters             enable row level security;
alter table public.meetings             enable row level security;
alter table public.meeting_rsvps        enable row level security;
alter table public.user_progress        enable row level security;
alter table public.comments             enable row level security;
alter table public.reactions            enable row level security;
alter table public.host_prompts         enable row level security;
alter table public.host_prompt_votes    enable row level security;
alter table public.quiz_questions       enable row level security;
alter table public.quiz_attempts        enable row level security;
alter table public.quiz_answers         enable row level security;
alter table public.xp_events            enable row level security;
alter table public.user_xp              enable row level security;
alter table public.user_streaks         enable row level security;
alter table public.book_polls           enable row level security;
alter table public.book_poll_options    enable row level security;
alter table public.book_poll_votes      enable row level security;
alter table public.achievements         enable row level security;
alter table public.user_achievements    enable row level security;
alter table public.notifications        enable row level security;
alter table public.push_subscriptions   enable row level security;
alter table public.video_timed_comments enable row level security;
alter table public.challenges           enable row level security;
alter table public.user_challenges      enable row level security;
alter table public.user_clubs           enable row level security;
alter table public.user_club_members    enable row level security;

-- Helper: admin?
create or replace function public.is_admin() returns boolean language sql stable as $$
  select coalesce((select role = 'admin' from public.profiles where id = auth.uid()), false);
$$;

-- PROFILES
create policy "profiles_select_all" on public.profiles for select using (true);
create policy "profiles_update_own" on public.profiles for update
  using (auth.uid() = id) with check (auth.uid() = id);
create policy "profiles_insert_own" on public.profiles for insert
  with check (auth.uid() = id);

-- CONTEÚDO PÚBLICO (leitura livre, escrita via service_role)
create policy "authors_read"      on public.authors      for select using (true);
create policy "books_read"        on public.books        for select using (true);
create policy "seasons_read"      on public.seasons      for select using (true);
create policy "chapters_read"     on public.chapters     for select using (true);
create policy "meetings_read"     on public.meetings     for select using (true);
create policy "prompts_read"      on public.host_prompts for select using (true);
create policy "achievements_read" on public.achievements for select using (true);
create policy "challenges_read"   on public.challenges   for select using (true);

create policy "authors_admin_write"  on public.authors      for all
  using (public.is_admin()) with check (public.is_admin());
create policy "books_admin_write"    on public.books        for all
  using (public.is_admin()) with check (public.is_admin());
create policy "seasons_admin_write"  on public.seasons      for all
  using (public.is_admin()) with check (public.is_admin());
create policy "chapters_admin_write" on public.chapters     for all
  using (public.is_admin()) with check (public.is_admin());
create policy "meetings_admin_write" on public.meetings     for all
  using (public.is_admin()) with check (public.is_admin());
create policy "prompts_admin_write"  on public.host_prompts for all
  using (public.is_admin()) with check (public.is_admin());

-- PROGRESSO
create policy "progress_self_read"  on public.user_progress for select
  using (auth.uid() = user_id);
create policy "progress_self_write" on public.user_progress for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- COMENTÁRIOS
create policy "comments_read" on public.comments for select using (deleted_at is null);
create policy "comments_insert_auth" on public.comments for insert
  with check (auth.uid() = user_id);
create policy "comments_update_own" on public.comments for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "comments_delete_own_or_admin" on public.comments for delete
  using (auth.uid() = user_id or public.is_admin());

-- REAÇÕES
create policy "reactions_read" on public.reactions for select using (true);
create policy "reactions_own"  on public.reactions for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- QUIZ (perguntas: leitura autenticada; respostas: apenas dono)
create policy "quiz_q_read_auth" on public.quiz_questions for select
  using (auth.role() = 'authenticated');
create policy "quiz_attempt_own" on public.quiz_attempts for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "quiz_answers_own" on public.quiz_answers for all
  using (exists(select 1 from public.quiz_attempts a
                where a.id = attempt_id and a.user_id = auth.uid()))
  with check (exists(select 1 from public.quiz_attempts a
                where a.id = attempt_id and a.user_id = auth.uid()));

-- XP / STREAK (leitura pública agregada, escrita via service_role/trigger)
create policy "xp_events_own_read"     on public.xp_events         for select using (auth.uid() = user_id);
create policy "user_xp_read"           on public.user_xp           for select using (true);
create policy "user_streaks_read"      on public.user_streaks      for select using (true);
create policy "user_achievements_read" on public.user_achievements for select using (true);

-- POLLS
create policy "poll_read"      on public.book_polls        for select using (true);
create policy "poll_opts_read" on public.book_poll_options for select using (true);
create policy "poll_vote_own"  on public.book_poll_votes   for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- NOTIFICAÇÕES
create policy "notif_own" on public.notifications      for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "push_own"  on public.push_subscriptions for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- VIDEO TIMED COMMENTS
create policy "vtc_read" on public.video_timed_comments for select using (true);
create policy "vtc_own"  on public.video_timed_comments for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- CLUBES UGC
create policy "uclubs_read_public" on public.user_clubs for select
  using (not is_private or owner_id = auth.uid());
create policy "uclubs_owner" on public.user_clubs for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
create policy "uclub_members_read" on public.user_club_members for select using (true);
create policy "uclub_members_self" on public.user_club_members for all
  using (auth.uid() = user_id or exists(
    select 1 from public.user_clubs c where c.id = club_id and c.owner_id = auth.uid()
  )) with check (true);
```

### 5.2 RLS complementar

**Arquivo:** `supabase/migrations/20260101002300_rls_complement.sql`

```sql
-- Habilitar RLS em todas as tabelas do complemento
alter table public.content_warnings                 enable row level security;
alter table public.book_content_warnings            enable row level security;
alter table public.book_content_warning_votes       enable row level security;
alter table public.book_mood_stats                  enable row level security;
alter table public.book_mood_votes                  enable row level security;
alter table public.mood_labels                      enable row level security;
alter table public.editorial_picks                  enable row level security;
alter table public.buddy_reads                      enable row level security;
alter table public.buddy_read_members               enable row level security;
alter table public.buddy_read_checkpoints           enable row level security;
alter table public.reading_journal_entries          enable row level security;
alter table public.reading_journal_attachments      enable row level security;
alter table public.reading_lists                    enable row level security;
alter table public.reading_list_items               enable row level security;
alter table public.reading_list_collaborators       enable row level security;
alter table public.user_up_next                     enable row level security;
alter table public.milestones                       enable row level security;
alter table public.user_milestone_progress          enable row level security;
alter table public.user_quiz_averages               enable row level security;
alter table public.chapter_quiz_averages            enable row level security;
alter table public.reading_goals                    enable row level security;
alter table public.reading_goal_progress            enable row level security;
alter table public.challenge_prompts                enable row level security;
alter table public.feed_posts                       enable row level security;
alter table public.feed_post_media                  enable row level security;
alter table public.feed_post_likes                  enable row level security;
alter table public.feed_post_comments               enable row level security;
alter table public.follows                          enable row level security;
alter table public.user_reading_preferences         enable row level security;
alter table public.user_reading_embeddings          enable row level security;
alter table public.user_match_cache                 enable row level security;
alter table public.membership_plans                 enable row level security;
alter table public.user_subscriptions               enable row level security;
alter table public.payment_events                   enable row level security;
alter table public.user_membership_perks            enable row level security;
alter table public.newsletter_subscribers           enable row level security;
alter table public.newsletter_issues                enable row level security;
alter table public.newsletter_deliveries            enable row level security;
alter table public.affiliate_clicks                 enable row level security;
alter table public.chapter_extra_content            enable row level security;
alter table public.chapter_activities               enable row level security;
alter table public.chapter_activity_attempts        enable row level security;
alter table public.chapter_prompts                  enable row level security;
alter table public.chapter_prompt_responses         enable row level security;

-- ============================================================
-- Conteúdo público de catálogo
-- ============================================================
create policy "cw_read"         on public.content_warnings      for select using (true);
create policy "bcw_read"        on public.book_content_warnings for select using (true);
create policy "bcw_admin_write" on public.book_content_warnings for all
  using (public.is_admin()) with check (public.is_admin());
create policy "bcwv_own"        on public.book_content_warning_votes for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "bms_read"        on public.book_mood_stats        for select using (true);
create policy "bmv_read"        on public.book_mood_votes        for select using (true);
create policy "bmv_own"         on public.book_mood_votes        for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "mood_labels_read" on public.mood_labels            for select using (true);
create policy "editorial_read"   on public.editorial_picks        for select using (is_active);
create policy "editorial_admin"  on public.editorial_picks        for all
  using (public.is_admin()) with check (public.is_admin());

-- ============================================================
-- Buddy Reads
-- ============================================================
create policy "buddy_reads_visible" on public.buddy_reads for select
  using (
    not is_private
    or owner_id = auth.uid()
    or exists (select 1 from public.buddy_read_members m
               where m.buddy_read_id = id and m.user_id = auth.uid())
  );
create policy "buddy_reads_owner_write" on public.buddy_reads for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "buddy_members_read" on public.buddy_read_members for select
  using (
    exists (select 1 from public.buddy_reads br
            where br.id = buddy_read_id
              and (not br.is_private or br.owner_id = auth.uid()))
  );
create policy "buddy_members_self_join" on public.buddy_read_members for insert
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.buddy_reads br
                where br.id = buddy_read_id
                  and (not br.is_private or br.owner_id = auth.uid()
                       or exists (select 1 from public.buddy_read_members m2
                                  where m2.buddy_read_id = br.id and m2.user_id = auth.uid())))
  );
create policy "buddy_members_self_leave" on public.buddy_read_members for delete
  using (user_id = auth.uid()
         or exists (select 1 from public.buddy_reads br
                    where br.id = buddy_read_id and br.owner_id = auth.uid()));
create policy "buddy_checkpoints_read" on public.buddy_read_checkpoints for select
  using (
    exists (select 1 from public.buddy_reads br
            where br.id = buddy_read_id
              and (not br.is_private or br.owner_id = auth.uid()
                   or exists (select 1 from public.buddy_read_members m
                              where m.buddy_read_id = br.id and m.user_id = auth.uid())))
  );
create policy "buddy_checkpoints_write" on public.buddy_read_checkpoints for all
  using (
    exists (select 1 from public.buddy_reads br
            where br.id = buddy_read_id and br.owner_id = auth.uid())
  )
  with check (
    exists (select 1 from public.buddy_reads br
            where br.id = buddy_read_id and br.owner_id = auth.uid())
  );

-- ============================================================
-- Diário de leitura
-- ============================================================
create policy "journal_read_own" on public.reading_journal_entries for select
  using (
    user_id = auth.uid()
    or visibility = 'public'
    or (visibility = 'friends' and exists (
         select 1 from public.follows f
          where f.follower_id = auth.uid()
            and f.followed_id = reading_journal_entries.user_id
            and f.status = 'accepted'))
    or (visibility = 'club' and exists (
         select 1 from public.user_club_members m1
         join public.user_club_members m2 on m1.club_id = m2.club_id
         where m1.user_id = auth.uid()
           and m2.user_id = reading_journal_entries.user_id))
  );
create policy "journal_write_own" on public.reading_journal_entries for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "journal_attach_read" on public.reading_journal_attachments for select
  using (
    exists (select 1 from public.reading_journal_entries e
            where e.id = entry_id
              and (e.user_id = auth.uid() or e.visibility = 'public'))
  );
create policy "journal_attach_write" on public.reading_journal_attachments for all
  using (
    exists (select 1 from public.reading_journal_entries e
            where e.id = entry_id and e.user_id = auth.uid())
  )
  with check (
    exists (select 1 from public.reading_journal_entries e
            where e.id = entry_id and e.user_id = auth.uid())
  );

-- ============================================================
-- Listas personalizadas
-- ============================================================
create policy "lists_read" on public.reading_lists for select
  using (
    visibility = 'public'
    or owner_id = auth.uid()
    or exists (select 1 from public.reading_list_collaborators c
               where c.list_id = id and c.user_id = auth.uid())
  );
create policy "lists_owner_write" on public.reading_lists for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "list_items_read" on public.reading_list_items for select
  using (
    exists (select 1 from public.reading_lists l
            where l.id = list_id
              and (l.visibility = 'public'
                   or l.owner_id = auth.uid()
                   or exists (select 1 from public.reading_list_collaborators c
                              where c.list_id = l.id and c.user_id = auth.uid())))
  );
create policy "list_items_write" on public.reading_list_items for all
  using (
    exists (select 1 from public.reading_lists l
            where l.id = list_id
              and (l.owner_id = auth.uid()
                   or (l.is_collaborative and exists (
                        select 1 from public.reading_list_collaborators c
                         where c.list_id = l.id and c.user_id = auth.uid() and c.can_edit))))
  )
  with check (true);
create policy "list_collab_read" on public.reading_list_collaborators for select
  using (
    user_id = auth.uid()
    or exists (select 1 from public.reading_lists l
               where l.id = list_id and l.owner_id = auth.uid())
  );
create policy "list_collab_owner" on public.reading_list_collaborators for all
  using (
    exists (select 1 from public.reading_lists l
            where l.id = list_id and l.owner_id = auth.uid())
  )
  with check (true);

-- Up Next
create policy "up_next_own" on public.user_up_next for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ============================================================
-- Milestones
-- ============================================================
create policy "milestones_read"   on public.milestones              for select using (true);
create policy "milestones_admin"  on public.milestones              for all
  using (public.is_admin()) with check (public.is_admin());
create policy "um_progress_read"  on public.user_milestone_progress for select using (true);
create policy "um_progress_write" on public.user_milestone_progress for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ============================================================
-- Médias de quiz
-- ============================================================
create policy "uqa_read"        on public.user_quiz_averages    for select using (true);
create policy "uqa_admin_write" on public.user_quiz_averages    for all
  using (public.is_admin()) with check (public.is_admin());
create policy "cqa_read"        on public.chapter_quiz_averages for select using (true);

-- ============================================================
-- Metas e desafios
-- ============================================================
create policy "goals_own"              on public.reading_goals         for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "goal_progress_read"     on public.reading_goal_progress for select using (true);
create policy "challenge_prompts_read" on public.challenge_prompts     for select using (true);

-- ============================================================
-- Feed social
-- ============================================================
create policy "feed_posts_read" on public.feed_posts for select
  using (
    deleted_at is null and (
      visibility = 'public'
      or author_id = auth.uid()
      or (visibility = 'followers' and exists (
           select 1 from public.follows f
            where f.follower_id = auth.uid()
              and f.followed_id = feed_posts.author_id
              and f.status = 'accepted'))
      or (visibility = 'club' and exists (
           select 1 from public.user_club_members m
            where m.club_id = feed_posts.club_id and m.user_id = auth.uid()))
    )
  );
create policy "feed_posts_author_write" on public.feed_posts for all
  using (author_id = auth.uid()) with check (author_id = auth.uid());
create policy "feed_media_read" on public.feed_post_media for select
  using (exists (select 1 from public.feed_posts p
                 where p.id = post_id and p.deleted_at is null));
create policy "feed_media_author" on public.feed_post_media for all
  using (exists (select 1 from public.feed_posts p
                 where p.id = post_id and p.author_id = auth.uid()))
  with check (true);
create policy "feed_likes_read"    on public.feed_post_likes    for select using (true);
create policy "feed_likes_own"     on public.feed_post_likes    for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "feed_comments_read" on public.feed_post_comments for select
  using (deleted_at is null);
create policy "feed_comments_write_own" on public.feed_post_comments for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ============================================================
-- Seguir / preferências / embeddings / matches
-- ============================================================
create policy "follows_read"   on public.follows for select using (true);
create policy "follows_own"    on public.follows for all
  using (follower_id = auth.uid()) with check (follower_id = auth.uid());
create policy "prefs_own"      on public.user_reading_preferences for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "embed_own_read" on public.user_reading_embeddings for select
  using (user_id = auth.uid());
create policy "embed_admin"    on public.user_reading_embeddings for all
  using (public.is_admin()) with check (public.is_admin());
create policy "match_read_own" on public.user_match_cache for select
  using (user_id = auth.uid());

-- ============================================================
-- Monetização / Newsletter
-- ============================================================
create policy "plans_read"    on public.membership_plans for select using (is_active);
create policy "plans_admin"   on public.membership_plans for all
  using (public.is_admin()) with check (public.is_admin());
create policy "subs_own_read" on public.user_subscriptions for select
  using (user_id = auth.uid() or public.is_admin());
create policy "subs_admin"    on public.user_subscriptions for all
  using (public.is_admin()) with check (public.is_admin());
create policy "pevents_admin" on public.payment_events for all
  using (public.is_admin()) with check (public.is_admin());
create policy "perks_own"     on public.user_membership_perks for select
  using (user_id = auth.uid() or public.is_admin());

create policy "news_self_read"  on public.newsletter_subscribers for select
  using (user_id = auth.uid() or public.is_admin());
create policy "news_self_write" on public.newsletter_subscribers for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "news_admin"      on public.newsletter_subscribers for all
  using (public.is_admin()) with check (public.is_admin());
create policy "news_issues_read"  on public.newsletter_issues for select
  using (sent_at is not null or public.is_admin());
create policy "news_issues_admin" on public.newsletter_issues for all
  using (public.is_admin()) with check (public.is_admin());
create policy "news_deliv_self" on public.newsletter_deliveries for select
  using (exists (select 1 from public.newsletter_subscribers s
                 where s.id = subscriber_id and s.user_id = auth.uid())
         or public.is_admin());
create policy "news_deliv_admin" on public.newsletter_deliveries for all
  using (public.is_admin()) with check (public.is_admin());

create policy "affiliate_insert_auth" on public.affiliate_clicks for insert
  with check (auth.uid() = user_id or user_id is null);
create policy "affiliate_admin_read" on public.affiliate_clicks for select
  using (public.is_admin());

-- ============================================================
-- Conteúdo extra e atividades
-- ============================================================
create policy "cec_read"  on public.chapter_extra_content for select
  using (is_public or public.is_admin());
create policy "cec_admin" on public.chapter_extra_content for all
  using (public.is_admin()) with check (public.is_admin());
create policy "ca_read"   on public.chapter_activities for select
  using (status = 'published' or public.is_admin());
create policy "ca_admin"  on public.chapter_activities for all
  using (public.is_admin()) with check (public.is_admin());
create policy "caa_own_read"  on public.chapter_activity_attempts for select
  using (user_id = auth.uid() or public.is_admin());
create policy "caa_own_write" on public.chapter_activity_attempts for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "cp_read"  on public.chapter_prompts for select using (true);
create policy "cp_admin" on public.chapter_prompts for all
  using (public.is_admin()) with check (public.is_admin());
create policy "cpr_read" on public.chapter_prompt_responses for select
  using (
    user_id = auth.uid()
    or visibility = 'public'
    or (visibility = 'friends' and exists (
         select 1 from public.follows f
          where f.follower_id = auth.uid()
            and f.followed_id = chapter_prompt_responses.user_id
            and f.status = 'accepted'))
  );
create policy "cpr_own" on public.chapter_prompt_responses for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
```

---

## 6. Funções SQL, Triggers e Views

### 6.1 Funções e Triggers base

**Arquivo:** `supabase/migrations/20260101001400_functions_and_triggers.sql`

#### 6.1.1 Trigger `handle_new_user` → cria profile

```sql
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, username, display_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email,'@',1)),
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email,'@',1)),
    new.raw_user_meta_data->>'avatar_url'
  )
  on conflict (id) do nothing;

  insert into public.user_xp (user_id) values (new.id)
    on conflict do nothing;
  insert into public.user_streaks (user_id) values (new.id)
    on conflict do nothing;
  return new;
end $$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();
```

#### 6.1.2 `award_xp()` — central de pontos

```sql
create or replace function public.award_xp(
  p_user uuid,
  p_source xp_source,
  p_amount int,
  p_ref uuid default null
) returns void language plpgsql security definer as $$
begin
  insert into public.xp_events (user_id, source, amount, ref_id)
  values (p_user, p_source, p_amount, p_ref);

  insert into public.user_xp (user_id, total_xp, updated_at)
  values (p_user, p_amount, now())
  on conflict (user_id) do update
    set total_xp = public.user_xp.total_xp + excluded.total_xp,
        updated_at = now();
end $$;
```

#### 6.1.3 Trigger de reações → `likes_count` em comentários

```sql
create or replace function public.bump_comment_likes()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    update public.comments set likes_count = likes_count + 1 where id = new.comment_id;
  elsif tg_op = 'DELETE' then
    update public.comments set likes_count = likes_count - 1 where id = old.comment_id;
  end if;
  return null;
end $$;

create trigger trg_comment_likes
after insert or delete on public.reactions
for each row execute function public.bump_comment_likes();
```

#### 6.1.4 Trigger de respostas → `replies_count`

```sql
create or replace function public.bump_comment_replies()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' and new.parent_id is not null then
    update public.comments set replies_count = replies_count + 1 where id = new.parent_id;
  elsif tg_op = 'DELETE' and old.parent_id is not null then
    update public.comments set replies_count = replies_count - 1 where id = old.parent_id;
  end if;
  return null;
end $$;

create trigger trg_comment_replies
after insert or delete on public.comments
for each row execute function public.bump_comment_replies();
```

#### 6.1.5 Streak updater

```sql
create or replace function public.touch_streak()
returns trigger language plpgsql as $$
declare
  v_user uuid;
  v_last date;
  v_today date := current_date;
  v_curr int;
  v_long int;
begin
  -- quem gerou atividade?
  if tg_table_name = 'user_progress' then v_user := new.user_id;
  elsif tg_table_name = 'xp_events'   then v_user := new.user_id;
  else return null; end if;

  select last_activity_at, current_streak, longest_streak
    into v_last, v_curr, v_long
  from public.user_streaks where user_id = v_user for update;

  if v_last = v_today then return null; end if;

  if v_last = v_today - 1 then
    v_curr := coalesce(v_curr,0) + 1;
  else
    v_curr := 1;
  end if;
  v_long := greatest(coalesce(v_long,0), v_curr);

  update public.user_streaks
     set current_streak = v_curr,
         longest_streak = v_long,
         last_activity_at = v_today,
         updated_at = now()
   where user_id = v_user;

  return null;
end $$;

create trigger trg_streak_progress
after insert or update on public.user_progress
for each row execute function public.touch_streak();

create trigger trg_streak_xp
after insert on public.xp_events
for each row execute function public.touch_streak();
```

#### 6.1.6 Função SQL de matching de livros (P2)

```sql
create or replace function public.match_books(
  query_embedding vector(1536),
  match_threshold float,
  match_count int
) returns table (id uuid, title text, similarity float)
language sql stable as $$
  select b.id, b.title, 1 - (b.embedding <=> query_embedding) as similarity
  from public.books b
  where b.embedding is not null
    and 1 - (b.embedding <=> query_embedding) > match_threshold
  order by b.embedding <=> query_embedding
  limit match_count;
$$;
```

### 6.2 Views base

**Arquivo:** `supabase/migrations/20260101001400_functions_and_triggers.sql` (continuação)

#### 6.2.1 View: progresso agregado por capítulo (para o "milestone panel")

```sql
create or replace view public.v_chapter_audience as
select
  c.id                                  as chapter_id,
  c.season_id,
  count(*) filter (where p.status = 'read')             as finished_count,
  count(*) filter (where p.status = 'reading')          as reading_count,
  count(*) filter (where p.status = 'want_to_read')     as not_started_count,
  round(avg(p.percent)::numeric, 2)                     as avg_percent
from public.chapters c
left join public.user_progress p on p.chapter_id = c.id
group by c.id, c.season_id;
```

#### 6.2.2 View: ranking da temporada

```sql
create or replace view public.v_season_ranking as
select
  ux.season_id,
  ux.user_id,
  p.username,
  p.display_name,
  p.avatar_url,
  ux.season_xp,
  row_number() over (partition by ux.season_id order by ux.season_xp desc) as position
from public.user_xp ux
join public.profiles p on p.id = ux.user_id
where ux.season_id is not null;
```

#### 6.2.3 View: comentários com lock anti-spoiler

Este lock usa `user_progress.percent` autodeclarado do próprio leitor. É um recurso de autocontrole de spoilers, não prova de leitura nem boundary de autorização; a view é invoker e as policies continuam sendo a proteção de acesso entre usuários.

```sql
create or replace view public.v_comments_visible as
select
  c.id, c.chapter_id, c.user_id, c.parent_id, c.created_at, c.likes_count,
  c.replies_count, c.is_spoiler,
  case
    when c.is_spoiler and coalesce(up.percent,0) < c.min_percent then null
    else c.content
  end as content,
  case
    when c.is_spoiler and coalesce(up.percent,0) < c.min_percent then true
    else false
  end as is_locked
from public.comments c
left join public.user_progress up
  on up.chapter_id = c.chapter_id and up.user_id = auth.uid()
where c.deleted_at is null;
```

### 6.3 Views materializadas e contadores agregados

**Arquivo:** `supabase/migrations/20260101002400_views_and_counters.sql`

```sql
-- =====================================================================
-- 1. Contagem de respostas da enquete por opção ("Concordo/Discordo/Não sei")
-- =====================================================================
create or replace view public.v_host_prompt_results as
select
  hp.id                                              as prompt_id,
  hp.chapter_id,
  hp.question,
  hp.options,
  coalesce(sum(case when v.option_idx = 0 then 1 else 0 end), 0) as option_0_count,
  coalesce(sum(case when v.option_idx = 1 then 1 else 0 end), 0) as option_1_count,
  coalesce(sum(case when v.option_idx = 2 then 1 else 0 end), 0) as option_2_count,
  count(v.user_id)                                              as total_votes
from public.host_prompts hp
left join public.host_prompt_votes v on v.prompt_id = hp.id
group by hp.id, hp.chapter_id, hp.question, hp.options;

-- =====================================================================
-- 2. Pessoas que comentaram cada trecho do vídeo
-- =====================================================================
create or replace view public.v_video_timed_comment_stats as
select
  vtc.chapter_id,
  vtc.video_sec,
  count(distinct vtc.user_id)              as distinct_commenters,
  count(*)                                 as comment_count,
  max(vtc.created_at)                      as last_comment_at
from public.video_timed_comments vtc
group by vtc.chapter_id, vtc.video_sec;
create index if not exists vtc_sec_idx on public.video_timed_comments (chapter_id, video_sec);

-- =====================================================================
-- 3. Estatísticas por livro (humor, pace, ratings)
-- =====================================================================
create materialized view public.mv_book_community_stats as
select
  b.id                                                as book_id,
  coalesce(bms.mood_percent, '{}'::jsonb)             as mood_percent,
  coalesce(bms.pace_percent, '{"slow":0,"medium":0,"fast":0}'::jsonb) as pace_percent,
  bms.plot_vs_character_avg,
  bms.sample_size,
  coalesce(avg(br.rating), 0)                         as avg_rating,
  count(br.id)                                        as ratings_count,
  coalesce(avg(br.spice_level), 0)                    as avg_spice_level
from public.books b
left join public.book_mood_stats bms on bms.book_id = b.id
left join public.book_reviews br on br.book_id = b.id
group by b.id, bms.mood_percent, bms.pace_percent, bms.plot_vs_character_avg, bms.sample_size;
create unique index mv_book_community_stats_pk on public.mv_book_community_stats (book_id);

-- =====================================================================
-- 4. Estatísticas de usuário (para dashboard de stats)
-- =====================================================================
create or replace view public.v_user_reading_overview as
select
  p.id                                                     as user_id,
  count(distinct up.id) filter (where up.status = 'read')  as books_read,
  count(distinct up.id) filter (where up.status = 'reading') as books_reading,
  count(distinct up.id) filter (where up.status = 'want_to_read') as books_want,
  count(distinct up.id) filter (where up.status = 'dnf')   as books_dnf,
  coalesce(sum(rje.minutes_read), 0)                       as total_minutes,
  coalesce(count(distinct rje.entry_date), 0)              as reading_days,
  coalesce(sum(case when rje.entry_date = current_date then 1 else 0 end), 0) as read_today
from public.profiles p
left join public.user_progress up on up.user_id = p.id
left join public.reading_journal_entries rje on rje.user_id = p.id
group by p.id;

-- =====================================================================
-- 5. Ranking de clube (não-competitivo — usado para painel de progresso)
-- =====================================================================
create or replace view public.v_club_progress_panel as
select
  ucm.club_id,
  count(*) filter (where up.status = 'read')         as finished_count,
  count(*) filter (where up.status = 'reading')      as reading_count,
  count(*) filter (where up.status = 'want_to_read') as not_started_count,
  coalesce(round(avg(up.percent)::numeric, 2), 0)    as avg_percent
from public.user_club_members ucm
left join public.user_progress up
  on up.user_id = ucm.user_id
 and up.chapter_id in (select id from public.chapters c
                       join public.seasons s on s.id = c.season_id
                       join public.user_clubs uc on uc.id = ucm.club_id
                       where s.book_id = (select current_book_id
                                          from public.clubs c2
                                          where c2.id = ucm.club_id))
group by ucm.club_id;

-- =====================================================================
-- 6. Contadores agregados para o feed ("X pessoas comentaram este trecho")
-- =====================================================================
create or replace view public.v_feed_post_counters as
select
  fp.id                                as post_id,
  fp.likes_count,
  fp.comments_count,
  fp.shares_count,
  count(fpl.user_id)                   as fresh_likes_count,
  count(fpc.id)                        as fresh_comments_count
from public.feed_posts fp
left join public.feed_post_likes fpl on fpl.post_id = fp.id
left join public.feed_post_comments fpc on fpc.post_id = fp.id and fpc.deleted_at is null
where fp.deleted_at is null
group by fp.id, fp.likes_count, fp.comments_count, fp.shares_count;

-- =====================================================================
-- 7. View: match de leitores com interesses parecidos
-- =====================================================================
create or replace function public.get_reader_matches(p_user uuid, p_limit int default 20)
returns table (
  matched_id   uuid,
  username     citext,
  display_name text,
  avatar_url   text,
  similarity   numeric,
  shared_books int,
  shared_moods text[]
)
language sql stable as $$
  select
    umc.matched_id,
    p.username,
    p.display_name,
    p.avatar_url,
    umc.similarity,
    umc.shared_books,
    array(select unnest(umc.shared_moods)::text)
  from public.user_match_cache umc
  join public.profiles p on p.id = umc.matched_id
  where umc.user_id = p_user
  order by umc.similarity desc
  limit p_limit;
$$;
```

### 6.4 Funções SQL complementares

**Arquivo:** `supabase/migrations/20260101002500_functions_complement.sql`

```sql
-- =====================================================================
-- 1. Atualização materializada das médias de quiz a cada tentativa
-- =====================================================================
create or replace function public.refresh_user_quiz_averages()
returns trigger language plpgsql security definer as $$
declare
  v_user uuid := new.user_id;
begin
  insert into public.user_quiz_averages (
    user_id, attempts_total, score_sum, total_sum, average_percent,
    best_percent, last_attempt_at, updated_at
  )
  select
    v_user,
    count(*),
    coalesce(sum(score), 0),
    coalesce(sum(total), 0),
    case when coalesce(sum(total),0) = 0 then 0
         else round((sum(score)::numeric / sum(total)::numeric) * 100, 2) end,
    coalesce(max(case when total = 0 then 0
                      else round((score::numeric / total::numeric) * 100, 2) end), 0),
    max(created_at),
    now()
  from public.quiz_attempts
  where user_id = v_user
  on conflict (user_id) do update
    set attempts_total  = excluded.attempts_total,
        score_sum       = excluded.score_sum,
        total_sum       = excluded.total_sum,
        average_percent = excluded.average_percent,
        best_percent    = excluded.best_percent,
        last_attempt_at = excluded.last_attempt_at,
        updated_at      = now();
  return null;
end $$;

create trigger trg_refresh_user_quiz_averages
after insert on public.quiz_attempts
for each row execute function public.refresh_user_quiz_averages();

-- Média por capítulo
create or replace function public.refresh_chapter_quiz_averages()
returns trigger language plpgsql security definer as $$
declare
  v_chapter uuid := new.chapter_id;
begin
  insert into public.chapter_quiz_averages (
    chapter_id, attempts_total, average_percent, perfect_count, updated_at
  )
  select
    v_chapter,
    count(*),
    case when coalesce(sum(total),0) = 0 then 0
         else round((sum(score)::numeric / sum(total)::numeric) * 100, 2) end,
    count(*) filter (where score = total),
    now()
  from public.quiz_attempts
  where chapter_id = v_chapter
  on conflict (chapter_id) do update
    set attempts_total  = excluded.attempts_total,
        average_percent = excluded.average_percent,
        perfect_count   = excluded.perfect_count,
        updated_at      = now();
  return null;
end $$;

create trigger trg_refresh_chapter_quiz_averages
after insert on public.quiz_attempts
for each row execute function public.refresh_chapter_quiz_averages();

-- =====================================================================
-- 2. Recalcular book_mood_stats a partir dos votos
-- =====================================================================
create or replace function public.refresh_book_mood_stats(p_book uuid)
returns void language plpgsql security definer as $$
declare
  v_total int;
  v_mood  jsonb := '{}'::jsonb;
  v_pace  jsonb := '{"slow":0,"medium":0,"fast":0}'::jsonb;
  v_pvc   numeric := 0.50;
begin
  select count(*) into v_total from public.book_mood_votes where book_id = p_book;
  if v_total = 0 then
    insert into public.book_mood_stats (book_id, mood_counts, mood_percent, pace_percent,
                                        plot_vs_character_avg, sample_size, updated_at)
    values (p_book, '{}'::jsonb, '{}'::jsonb, v_pace, 0.50, 0, now())
    on conflict (book_id) do update
      set mood_counts = '{}'::jsonb,
          mood_percent = '{}'::jsonb,
          pace_percent = v_pace,
          plot_vs_character_avg = 0.50,
          sample_size = 0,
          updated_at = now();
    return;
  end if;

  -- contagem por mood
  select jsonb_object_agg(m, c)
    into v_mood
  from (
    select m::text as m, count(*) as c
    from public.book_mood_votes bmv, unnest(bmv.moods) m
    where bmv.book_id = p_book
    group by m
  ) t;

  -- contagem por pace
  select jsonb_build_object(
    'slow',   coalesce(count(*) filter (where pace = 'slow'),0),
    'medium', coalesce(count(*) filter (where pace = 'medium'),0),
    'fast',   coalesce(count(*) filter (where pace = 'fast'),0)
  ) into v_pace
  from public.book_mood_votes where book_id = p_book;

  select coalesce(avg(plot_vs_character), 0.50)
    into v_pvc
  from public.book_mood_votes
  where book_id = p_book and plot_vs_character is not null;

  insert into public.book_mood_stats (book_id, mood_counts, mood_percent, pace_percent,
                                      plot_vs_character_avg, sample_size, updated_at)
  values (
    p_book,
    coalesce(v_mood, '{}'::jsonb),
    (select coalesce(jsonb_object_agg(key, round((value::numeric / v_total), 4)), '{}'::jsonb)
       from jsonb_each_text(coalesce(v_mood,'{}'::jsonb))),
    (select jsonb_build_object(
       'slow',   round((coalesce((v_pace->>'slow')::numeric,   0) / v_total), 4),
       'medium', round((coalesce((v_pace->>'medium')::numeric, 0) / v_total), 4),
       'fast',   round((coalesce((v_pace->>'fast')::numeric,   0) / v_total), 4))),
    round(v_pvc, 2),
    v_total,
    now()
  )
  on conflict (book_id) do update
    set mood_counts = excluded.mood_counts,
        mood_percent = excluded.mood_percent,
        pace_percent = excluded.pace_percent,
        plot_vs_character_avg = excluded.plot_vs_character_avg,
        sample_size = excluded.sample_size,
        updated_at = now();
end $$;

create or replace function public.trg_refresh_book_mood_stats()
returns trigger language plpgsql as $$
begin
  perform public.refresh_book_mood_stats(coalesce(new.book_id, old.book_id));
  return null;
end $$;

create trigger trg_bmv_refresh
after insert or update or delete on public.book_mood_votes
for each row execute function public.trg_refresh_book_mood_stats();

-- =====================================================================
-- 3. Recalcular community_votes de content warnings
-- =====================================================================
create or replace function public.refresh_content_warning_votes()
returns trigger language plpgsql security definer as $$
declare
  v_row uuid := coalesce(new.warning_row_id, old.warning_row_id);
begin
  update public.book_content_warnings
     set community_votes = (
       select count(*) from public.book_content_warning_votes
        where warning_row_id = v_row and agrees = true
     ) - (
       select count(*) from public.book_content_warning_votes
        where warning_row_id = v_row and agrees = false
     )
   where id = v_row;
  return null;
end $$;

create trigger trg_bcwv_refresh
after insert or update or delete on public.book_content_warning_votes
for each row execute function public.refresh_content_warning_votes();

-- =====================================================================
-- 4. Contadores do feed
-- =====================================================================
create or replace function public.bump_feed_post_counters()
returns trigger language plpgsql as $$
begin
  if tg_table_name = 'feed_post_likes' then
    if tg_op = 'INSERT' then
      update public.feed_posts set likes_count = likes_count + 1 where id = new.post_id;
    elsif tg_op = 'DELETE' then
      update public.feed_posts set likes_count = greatest(likes_count - 1, 0) where id = old.post_id;
    end if;
  elsif tg_table_name = 'feed_post_comments' then
    if tg_op = 'INSERT' then
      update public.feed_posts set comments_count = comments_count + 1 where id = new.post_id;
    elsif tg_op = 'DELETE' then
      update public.feed_posts set comments_count = greatest(comments_count - 1, 0) where id = old.post_id;
    end if;
  end if;
  return null;
end $$;

create trigger trg_feed_likes_counters
after insert or delete on public.feed_post_likes
for each row execute function public.bump_feed_post_counters();

create trigger trg_feed_comments_counters
after insert or delete on public.feed_post_comments
for each row execute function public.bump_feed_post_counters();

-- =====================================================================
-- 5. Contadores do diário (likes em entradas públicas)
-- =====================================================================
create or replace function public.bump_journal_likes()
returns trigger language plpgsql as $$
begin
  if tg_table_name = 'feed_post_likes' then
    return null;
  end if;
  return null;
end $$;

-- =====================================================================
-- 6. Milestones automáticos por capítulo
-- =====================================================================
create or replace function public.generate_milestones_for_season(p_season uuid)
returns void language plpgsql security definer as $$
declare
  v_book       uuid;
  v_chapter    record;
  v_position   int := 0;
begin
  select book_id into v_book from public.seasons where id = p_season;
  if v_book is null then return; end if;

  for v_chapter in
    select id, number, title from public.chapters
     where season_id = p_season
     order by number
  loop
    v_position := v_position + 1;
    insert into public.milestones (
      chapter_id, season_id, book_id, position, title, description, kind
    )
    values (
      v_chapter.id, p_season, v_book, v_position,
      format('Marco %s — %s', v_position, v_chapter.title),
      'Marco gerado automaticamente a partir do capítulo.',
      'auto'
    )
    on conflict (season_id, position) do nothing;
  end loop;
end $$;

-- =====================================================================
-- 7. Recalcular metas anuais
-- =====================================================================
create or replace function public.refresh_reading_goal_progress()
returns trigger language plpgsql security definer as $$
declare
  v_user uuid := coalesce(new.user_id, old.user_id);
  v_year int := extract(year from current_date)::int;
  v_goal uuid;
begin
  select id into v_goal from public.reading_goals
   where user_id = v_user and year = v_year;
  if v_goal is null then return null; end if;

  insert into public.reading_goal_progress (goal_id, books_done, pages_done, minutes_done, updated_at)
  select
    v_goal,
    (select count(*) from public.user_progress
       where user_id = v_user and status = 'read'
         and finished_at >= make_date(v_year,1,1)),
    (select coalesce(sum(page_to - page_from), 0) from public.reading_journal_entries
       where user_id = v_user and entry_date >= make_date(v_year,1,1)),
    (select coalesce(sum(minutes_read), 0) from public.reading_journal_entries
       where user_id = v_user and entry_date >= make_date(v_year,1,1)),
    now()
  on conflict (goal_id) do update
    set books_done   = excluded.books_done,
        pages_done   = excluded.pages_done,
        minutes_done = excluded.minutes_done,
        updated_at   = now();
  return null;
end $$;

create trigger trg_goal_progress_refresh
after insert or update or delete on public.user_progress
for each row execute function public.refresh_reading_goal_progress();

create trigger trg_goal_progress_refresh_journal
after insert or update or delete on public.reading_journal_entries
for each row execute function public.refresh_reading_goal_progress();

-- =====================================================================
-- 8. Gerar embeddings do usuário (a partir do histórico)
-- =====================================================================
-- A função abaixo apenas monta o texto fonte; a chamada ao provedor
-- de embeddings é feita pela Edge Function `ai-user-embeddings`.
create or replace function public.build_user_reading_snapshot(p_user uuid)
returns text language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'title', b.title,
           'moods', bmv.moods,
           'pace',  bmv.pace,
           'rating', br.rating,
           'review', br.review_text
         ))::text, '[]')
  from public.user_progress up
  join public.chapters c on c.id = up.chapter_id
  join public.seasons  s on s.id = c.season_id
  join public.books    b on b.id = s.book_id
  left join public.book_mood_votes bmv on bmv.book_id = b.id and bmv.user_id = p_user
  left join public.book_reviews    br  on br.book_id  = b.id and br.user_id  = p_user
  where up.user_id = p_user;
$$;

-- =====================================================================
-- 9. RPC: match de leitores (similaridade de embeddings)
-- =====================================================================
create or replace function public.match_readers(
  query_embedding vector(1536),
  match_threshold float,
  match_count     int,
  p_user          uuid
) returns table (
  user_id      uuid,
  username     citext,
  display_name text,
  avatar_url   text,
  similarity   float
)
language sql stable as $$
  select
    ure.user_id,
    p.username,
    p.display_name,
    p.avatar_url,
    1 - (ure.embedding <=> query_embedding) as similarity
  from public.user_reading_embeddings ure
  join public.profiles p on p.id = ure.user_id
  where ure.user_id <> p_user
    and ure.embedding is not null
    and 1 - (ure.embedding <=> query_embedding) > match_threshold
  order by ure.embedding <=> query_embedding
  limit match_count;
$$;
```

---

## 7. Realtime (canais e publication)

**Arquivo:** `supabase/migrations/20260101001500_realtime.sql`

```sql
-- Adicionar tabelas à publicação realtime
alter publication supabase_realtime add table public.comments;
alter publication supabase_realtime add table public.reactions;
alter publication supabase_realtime add table public.video_timed_comments;
alter publication supabase_realtime add table public.notifications;
alter publication supabase_realtime add table public.book_poll_votes;
alter publication supabase_realtime add table public.host_prompt_votes;
```

**Arquivo:** `supabase/migrations/20260101002450_realtime_complement.sql`

```sql
alter publication supabase_realtime add table public.feed_posts;
alter publication supabase_realtime add table public.feed_post_likes;
alter publication supabase_realtime add table public.feed_post_comments;
alter publication supabase_realtime add table public.reading_journal_entries;
alter publication supabase_realtime add table public.reading_list_items;
alter publication supabase_realtime add table public.user_match_cache;
alter publication supabase_realtime add table public.newsletter_issues;
alter publication supabase_realtime add table public.book_content_warning_votes;
alter publication supabase_realtime add table public.book_mood_votes;
```

**Canais no frontend (base):**

| Canal | Uso |
|---|---|
| `comments:chapter:{chapter_id}` | comentários em tempo real por capítulo |
| `reactions:comment:{comment_id}` | reações |
| `video:{chapter_id}` | comentários sincronizados com o vídeo |
| `notifications:{user_id}` | notificações pessoais |
| `poll:{poll_id}` | votos em enquetes |

**Canais adicionais do frontend (complemento):**

| Canal | Uso |
|---|---|
| `feed:public` | novos posts do feed público |
| `feed:user:{user_id}` | posts de quem o usuário segue |
| `journal:{user_id}` | diário de leitura (próprio ou de amigos) |
| `matches:{user_id}` | atualizações de match entre leitores |
| `book:{book_id}:moods` | votos de humor/ritmo em tempo real |
| `newsletter:issues` | novas edições publicadas |

---

## 8. Storage Buckets e políticas

**Arquivo:** `supabase/migrations/20260101001600_storage.sql`

```sql
insert into storage.buckets (id, name, public) values
  ('avatars',       'avatars',       true),
  ('book-covers',   'book-covers',   true),
  ('manuscripts',   'manuscripts',   false),  -- Fellowship (P2)
  ('meeting-slides','meeting-slides',true);

-- Avatares: usuário edita o próprio
create policy "avatars_read" on storage.objects for select
  using (bucket_id = 'avatars');
create policy "avatars_write" on storage.objects for insert
  with check (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);
create policy "avatars_update" on storage.objects for update
  using (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

-- Capas: admin
create policy "covers_read" on storage.objects for select
  using (bucket_id = 'book-covers');
create policy "covers_admin" on storage.objects for all
  using (bucket_id = 'book-covers' and public.is_admin());
```

**Arquivo:** `supabase/migrations/20260101001650_storage_complement.sql`

```sql
insert into storage.buckets (id, name, public) values
  ('journal-media',    'journal-media',    false),
  ('chapter-extras',   'chapter-extras',   false),
  ('feed-media',       'feed-media',       true),
  ('newsletter-assets','newsletter-assets',true),
  ('social-cards',     'social-cards',     true),
  ('ebooks',           'ebooks',           false)
on conflict (id) do nothing;

-- Diário: usuário só acessa o próprio diretório (paths = user_id/...)
create policy "journal_media_own_read" on storage.objects for select
  using (
    bucket_id = 'journal-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
create policy "journal_media_own_write" on storage.objects for insert
  with check (
    bucket_id = 'journal-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
create policy "journal_media_own_update" on storage.objects for update
  using (
    bucket_id = 'journal-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- Extras de capítulo: leitura por qualquer autenticado; escrita admin
create policy "chapter_extras_read_auth" on storage.objects for select
  using (bucket_id = 'chapter-extras' and auth.role() = 'authenticated');
create policy "chapter_extras_admin_write" on storage.objects for all
  using (bucket_id = 'chapter-extras' and public.is_admin())
  with check (bucket_id = 'chapter-extras' and public.is_admin());

-- Feed media: leitura pública; escrita pelo autor
create policy "feed_media_read" on storage.objects for select
  using (bucket_id = 'feed-media');
create policy "feed_media_author_write" on storage.objects for insert
  with check (
    bucket_id = 'feed-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
create policy "feed_media_author_update" on storage.objects for update
  using (
    bucket_id = 'feed-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- Assets de newsletter: leitura pública; escrita admin
create policy "newsletter_assets_read" on storage.objects for select
  using (bucket_id = 'newsletter-assets');
create policy "newsletter_assets_admin" on storage.objects for all
  using (bucket_id = 'newsletter-assets' and public.is_admin())
  with check (bucket_id = 'newsletter-assets' and public.is_admin());

-- Cards sociais: leitura pública; escrita pelo autor
create policy "social_cards_read" on storage.objects for select
  using (bucket_id = 'social-cards');
create policy "social_cards_author_write" on storage.objects for insert
  with check (
    bucket_id = 'social-cards'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- Ebooks: leitura autenticada com URL assinada; upload admin
create policy "ebooks_read_auth" on storage.objects for select
  using (bucket_id = 'ebooks' and auth.role() = 'authenticated');
create policy "ebooks_admin_write" on storage.objects for all
  using (bucket_id = 'ebooks' and public.is_admin())
  with check (bucket_id = 'ebooks' and public.is_admin());
```

---

## 9. Edge Functions

### 9.1 `quiz-validate`

**Arquivo:** `supabase/functions/quiz-validate/index.ts`

```ts
import { serve } from "https://deno.land/std@0.200.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { cors } from "../_shared/cors.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return cors();

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization")! } } },
  );

  const { chapter_id, answers } = await req.json(); // answers: [{question_id, chosen_idx}]
  const { data: user } = await supabase.auth.getUser();
  if (!user?.user) return cors(new Response("unauth", { status: 401 }));

  const { data: questions } = await supabase
    .from("quiz_questions").select("id, correct_idx").eq("chapter_id", chapter_id);

  let score = 0;
  const detail = (questions ?? []).map((q) => {
    const a = answers.find((x: any) => x.question_id === q.id);
    const is_correct = a && a.chosen_idx === q.correct_idx;
    if (is_correct) score++;
    return { question_id: q.id, chosen_idx: a?.chosen_idx ?? -1, is_correct };
  });

  const { data: attempt } = await supabase
    .from("quiz_attempts")
    .insert({ user_id: user.user.id, chapter_id, score, total: questions!.length })
    .select().single();

  if (attempt) {
    await supabase.from("quiz_answers").insert(
      detail.map((d) => ({ ...d, attempt_id: attempt.id })),
    );
    // XP proporcional
    await supabase.rpc("award_xp", {
      p_user: user.user.id, p_source: "quiz_answer",
      p_amount: 50, p_ref: attempt.id,
    });
  }

  return cors(Response.json({ score, total: questions!.length, detail }));
});
```

### 9.2 `award-xp`

**Arquivo:** `supabase/functions/award-xp/index.ts`

```ts
import { serve } from "https://deno.land/std@0.200.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { cors } from "../_shared/cors.ts";

const XP: Record<string, number> = {
  join_meeting: 10,
  finish_chapter: 20,
  comment: 30,
  quiz_answer: 50,
  finish_book: 100,
  streak_bonus: 25,
};

serve(async (req) => {
  if (req.method === "OPTIONS") return cors();
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { source, ref_id } = await req.json();
  const { data: { user } } = await supabase.auth.getUser(
    req.headers.get("Authorization")?.replace("Bearer ", "") ?? "",
  );
  if (!user) return cors(new Response("unauth", { status: 401 }));

  const amount = XP[source] ?? 0;
  await supabase.rpc("award_xp", {
    p_user: user.id, p_source: source, p_amount: amount, p_ref: ref_id,
  });
  return cors(Response.json({ ok: true, amount }));
});
```

### 9.3 `vote-next-book`

**Arquivo:** `supabase/functions/vote-next-book/index.ts`

```ts
import { serve } from "https://deno.land/std@0.200.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { cors } from "../_shared/cors.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return cors();
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { poll_id, option_id } = await req.json();
  const auth = req.headers.get("Authorization")?.replace("Bearer ", "") ?? "";
  const { data: { user } } = await supabase.auth.getUser(auth);
  if (!user) return cors(new Response("unauth", { status: 401 }));

  await supabase.from("book_poll_votes").upsert(
    { poll_id, option_id, user_id: user.id },
    { onConflict: "poll_id,user_id" },
  );

  // Recontagem
  const { count } = await supabase
    .from("book_poll_votes")
    .select("*", { count: "exact", head: true })
    .eq("option_id", option_id);
  await supabase.from("book_poll_options")
    .update({ votes_count: count ?? 0 }).eq("id", option_id);

  return cors(Response.json({ ok: true, votes: count }));
});
```

### 9.4 `scheduled-reminders` (cron via `pg_cron` + `pg_net`)

**Arquivo:** `supabase/functions/scheduled-reminders/index.ts`

```ts
import { serve } from "https://deno.land/std@0.200.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async () => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const now = new Date();
  const in48h = new Date(now.getTime() + 48 * 3600_000).toISOString();

  const { data: meetings } = await supabase
    .from("meetings").select("*")
    .gte("scheduled_at", now.toISOString())
    .lte("scheduled_at", in48h);

  for (const m of meetings ?? []) {
    const { data: rsvps } = await supabase
      .from("meeting_rsvps").select("user_id").eq("meeting_id", m.id);
    for (const r of rsvps ?? []) {
      await supabase.from("notifications").insert({
        user_id: r.user_id, kind: "meeting_reminder",
        payload: { meeting_id: m.id, title: m.title, at: m.scheduled_at },
      });
    }
  }
  return Response.json({ ok: true });
});
```

### 9.5 `ai-recommendations` (P2)

**Arquivo:** `supabase/functions/ai-recommendations/index.ts`

```ts
import { serve } from "https://deno.land/std@0.200.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import OpenAI from "https://esm.sh/openai@4";
import { cors } from "../_shared/cors.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return cors();
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { user_id } = await req.json();

  const { data: history } = await supabase
    .from("user_progress").select("chapters(season_id, seasons(title))")
    .eq("user_id", user_id).eq("status", "read");

  const openai = new OpenAI({ apiKey: Deno.env.get("OPENAI_API_KEY")! });
  const embed = await openai.embeddings.create({
    model: "text-embedding-3-small",
    input: JSON.stringify(history),
  });
  const vector = embed.data[0].embedding;

  const { data: books } = await supabase.rpc("match_books", {
    query_embedding: vector, match_threshold: 0.72, match_count: 5,
  });

  return cors(Response.json({ books }));
});
```

### 9.6 `ai-user-embeddings`

**Arquivo:** `supabase/functions/ai-user-embeddings/index.ts`

```ts
import { serve } from "https://deno.land/std@0.200.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import OpenAI from "https://esm.sh/openai@4";
import { cors } from "../_shared/cors.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return cors();
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { user_id } = await req.json();

  const { data: snapshot } = await supabase
    .rpc("build_user_reading_snapshot", { p_user: user_id });

  const openai = new OpenAI({ apiKey: Deno.env.get("OPENAI_API_KEY")! });
  const embed = await openai.embeddings.create({
    model: "text-embedding-3-small",
    input: snapshot ?? "[]",
  });
  const vector = embed.data[0].embedding;

  await supabase.from("user_reading_embeddings").upsert(
    {
      user_id,
      embedding: vector as unknown as string,
      source_hash: String(snapshot).length.toString(36),
      updated_at: new Date().toISOString(),
    },
    { onConflict: "user_id" },
  );

  return cors(Response.json({ ok: true, dims: vector.length }));
});
```

### 9.7 `match-readers`

**Arquivo:** `supabase/functions/match-readers/index.ts`

```ts
import { serve } from "https://deno.land/std@0.200.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { cors } from "../_shared/cors.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return cors();
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { user_id, threshold = 0.75, limit = 20 } = await req.json();

  const { data: me } = await supabase
    .from("user_reading_embeddings")
    .select("embedding")
    .eq("user_id", user_id)
    .single();

  if (!me) return cors(Response.json({ ok: false, reason: "no_embedding" }));

  const { data: matches } = await supabase.rpc("match_readers", {
    query_embedding: me.embedding,
    match_threshold: threshold,
    match_count: limit,
    p_user: user_id,
  });

  for (const m of matches ?? []) {
    await supabase.from("user_match_cache").upsert(
      {
        user_id,
        matched_id: m.user_id,
        similarity: m.similarity,
        shared_books: 0,
        shared_moods: [],
        computed_at: new Date().toISOString(),
      },
      { onConflict: "user_id,matched_id" },
    );
  }

  return cors(Response.json({ matches }));
});
```

### 9.8 `newsletter-dispatch`

**Arquivo:** `supabase/functions/newsletter-dispatch/index.ts`

```ts
import { serve } from "https://deno.land/std@0.200.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Resend } from "https://esm.sh/resend@3";
import { cors } from "../_shared/cors.ts";

const resend = new Resend(Deno.env.get("RESEND_API_KEY")!);

serve(async (req) => {
  if (req.method === "OPTIONS") return cors();
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { issue_id } = await req.json();

  const { data: issue } = await supabase
    .from("newsletter_issues").select("*").eq("id", issue_id).single();
  if (!issue) return cors(new Response("not found", { status: 404 }));

  const { data: subs } = await supabase
    .from("newsletter_subscribers")
    .select("id, email, name")
    .eq("status", "confirmed");

  for (const s of subs ?? []) {
    const { data: sendRes, error } = await resend.emails.send({
      from: "Clube de Leitura <news@clubeleitura.app>",
      to: s.email,
      subject: issue.subject,
      html: issue.body_html ?? `<pre>${issue.body_markdown}</pre>`,
    });
    await supabase.from("newsletter_deliveries").upsert(
      {
        issue_id,
        subscriber_id: s.id,
        status: error ? "bounced" : "sent",
        provider_message_id: sendRes?.id,
        sent_at: new Date().toISOString(),
      },
      { onConflict: "issue_id,subscriber_id" },
    );
  }

  await supabase.from("newsletter_issues")
    .update({ sent_at: new Date().toISOString() })
    .eq("id", issue_id);

  return cors(Response.json({ ok: true, sent: (subs ?? []).length }));
});
```

### 9.9 `stripe-webhook`

**Arquivo:** `supabase/functions/stripe-webhook/index.ts`

```ts
import { serve } from "https://deno.land/std@0.200.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@14?target=denonext";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2024-06-20",
});

serve(async (req) => {
  const sig = req.headers.get("stripe-signature")!;
  const raw = await req.text();
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      raw,
      sig,
      Deno.env.get("STRIPE_WEBHOOK_SECRET")!,
    );
  } catch (_e) {
    return new Response("invalid signature", { status: 400 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { error: insErr } = await supabase.from("payment_events").insert({
    provider: "stripe",
    event_id: event.id,
    event_type: event.type,
    payload: event as unknown as Record<string, unknown>,
    processed_at: new Date().toISOString(),
  });
  if (insErr) return new Response("duplicate", { status: 200 });

  const obj = event.data.object as Record<string, any>;
  if (event.type.startsWith("customer.subscription.")) {
    const { data: plan } = await supabase
      .from("membership_plans")
      .select("id")
      .eq("stripe_price_id", obj.items?.data?.[0]?.price?.id)
      .maybeSingle();

    await supabase.from("user_subscriptions").upsert(
      {
        provider_subscription_id: obj.id,
        provider_customer_id: obj.customer,
        plan_id: plan?.id,
        status: obj.status,
        current_period_start: new Date(obj.current_period_start * 1000).toISOString(),
        current_period_end: new Date(obj.current_period_end * 1000).toISOString(),
        cancel_at_period_end: obj.cancel_at_period_end,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "provider_subscription_id" },
    );
  }

  return new Response("ok", { status: 200 });
});
```

### 9.10 `social-render-card`

**Arquivo:** `supabase/functions/social-render-card/index.ts`

```ts
import { serve } from "https://deno.land/std@0.200.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { cors } from "../_shared/cors.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return cors();
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { user_id, kind, payload } = await req.json();

  // Enfileira uma renderização para consumo de worker/next-gen render
  const { data, error } = await supabase
    .from("social_render_jobs")
    .insert({
      user_id,
      kind,
      payload,
      status: "queued",
    })
    .select()
    .single();

  if (error) return cors(new Response(error.message, { status: 400 }));

  // Placeholder: a renderização real pode ser feita por worker externo
  // (ex.: Chromium headless via Browserless, Cloudflare Images, ou Vercel OG).
  return cors(Response.json({ ok: true, job: data }));
});
```

### 9.11 `_shared/cors.ts`

```ts
export const cors = (res?: Response) => {
  const headers = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  };
  if (!res) return new Response("ok", { headers });
  const newRes = new Response(res.body, res);
  Object.entries(headers).forEach(([k, v]) => newRes.headers.set(k, v));
  return newRes;
};
```

### 9.12 Deploy das Edge Functions

```bash
supabase functions deploy quiz-validate
supabase functions deploy award-xp
supabase functions deploy vote-next-book
supabase functions deploy scheduled-reminders --no-verify-jwt
supabase functions deploy ai-recommendations
supabase functions deploy ai-user-embeddings
supabase functions deploy match-readers
supabase functions deploy newsletter-dispatch
supabase functions deploy stripe-webhook --no-verify-jwt
supabase functions deploy social-render-card

# Secrets
supabase secrets set RESEND_API_KEY=... DISCORD_WEBHOOK_URL=... OPENAI_API_KEY=...
supabase secrets set STRIPE_SECRET_KEY=... STRIPE_WEBHOOK_SECRET=...
```

### 9.13 Cron (via `pg_cron`)

```sql
select cron.schedule(
  'reminders-every-hour',
  '0 * * * *',
  $$ select net.http_post(
       url := 'https://<ref>.functions.supabase.co/scheduled-reminders',
       headers := '{"Authorization":"Bearer <service_role>"}'::jsonb
     ); $$
);
```

---

## 10. Autenticação e Perfis

- **Providers:** Email/senha + Magic Link + Google + GitHub.
- **Sessão:** cookies httpOnly via `@supabase/ssr` (Next.js).
- **Trigger `handle_new_user`** cria `profiles`, `user_xp`, `user_streaks`.
- **Onboarding** (`profiles.onboarding_done = false`): captura `username`, `display_name`, `level`, `lgpd_consent`.

---

## 11. Seed de dados (Dom Casmurro MVP + Complemento)

### 11.1 Seed base (MVP)

**Arquivo:** `supabase/seed.sql`

```sql
-- Autor
insert into public.authors (id, name, slug, bio) values
  ('11111111-1111-1111-1111-111111111111',
   'Machado de Assis','machado-de-assis','Escritor brasileiro (1839–1908).');

-- Livro
insert into public.books (id, title, slug, author_id, isbn13, total_chapters, total_pages, publication_year, amazon_url, tags, synopsis)
values
  ('22222222-2222-2222-2222-222222222222',
   'Dom Casmurro','dom-casmurro',
   '11111111-1111-1111-1111-111111111111',
   '9788535910663', 148, 256, 1899,
   'https://www.amazon.com.br/dp/8535910663?tag=clubedolivro-20',
   array['Literatura Brasileira','Realismo','Clássico'],
   'Bentinho, Capitu e o ciúme que atravessa gerações.');

-- Temporada
insert into public.seasons (id, number, title, slug, book_id, status, starts_at, ends_at)
values
  ('33333333-3333-3333-3333-333333333333', 1, 'Dom Casmurro','t1-dom-casmurro',
   '22222222-2222-2222-2222-222222222222','active', current_date, current_date + interval '35 days');

-- 5 capítulos (blocos)
insert into public.chapters (season_id, number, title, reading_range, youtube_url, summary)
values
  ('33333333-3333-3333-3333-333333333333',1,'Capítulos I a V','pág. 1–35 · ~25 min','https://youtu.be/...','Do trem ao seminário.'),
  ('33333333-3333-3333-3333-333333333333',2,'Capítulos VI a X','pág. 36–70 · ~28 min',null,'A promessa e o seminário.'),
  ('33333333-3333-3333-3333-333333333333',3,'Capítulos XI a XV','pág. 71–110 · ~30 min',null,'Capitu e o primeiro ciúme.'),
  ('33333333-3333-3333-3333-333333333333',4,'Capítulos XVI a XX','pág. 111–160 · ~35 min',null,'O casamento.'),
  ('33333333-3333-3333-3333-333333333333',5,'Capítulos XXI a fim','pág. 161–256 · ~45 min',null,'Ezequiel e o desfecho.');

-- Quiz do Cap. 1
insert into public.quiz_questions (chapter_id, position, question, options, correct_idx, explanation)
select c.id, 1, 'Quem narra Dom Casmurro?',
       '["Capitu","Bentinho","José Dias","Ezequiel"]'::jsonb, 1,
       'Bentinho é o narrador em primeira pessoa.'
from public.chapters c where c.number = 1;

-- Pergunta do anfitrião do Cap. 3
insert into public.host_prompts (chapter_id, question, options)
select c.id, 'José Dias realmente estava tentando ajudar Bentinho?',
       '["Concordo","Discordo","Ainda não sei"]'::jsonb
from public.chapters c where c.number = 3;

-- Conquistas padrão
insert into public.achievements (code, title, description, rule, xp_reward) values
  ('first_book','Primeiro livro','Concluiu o primeiro livro do clube.',
    '{"type":"count","source":"finish_book","gte":1}'::jsonb, 50),
  ('streak_4w','4 semanas seguidas','Manteve streak de 4 semanas.',
    '{"type":"streak","gte":28}'::jsonb, 100),
  ('machado_master','Mestre do Machado','Concluiu todas as obras de Machado na plataforma.',
    '{"type":"author_complete","author":"machado-de-assis"}'::jsonb, 200);
```

### 11.2 Seed complementar

**Arquivo:** `supabase/seed_complement.sql`

```sql
-- =====================================================================
-- 1. Content Warnings padrão
-- =====================================================================
insert into public.content_warnings (code, label, description, category) values
  ('violence','Violência','Cenas de violência física ou verbal.','violence'),
  ('grief','Luto','Morte de personagens ou luto explícito.','mental_health'),
  ('abuse','Abuso','Abuso físico, psicológico ou emocional.','violence'),
  ('self_harm','Autolesão','Referências a autolesão ou suicídio.','mental_health'),
  ('racism','Racismo','Comentários ou estruturas racistas.','identity'),
  ('sexism','Machismo','Comentários ou estruturas misóginas.','identity'),
  ('mental_illness','Doença mental','Retrato de transtornos mentais.','mental_health'),
  ('adultery','Adultério','Relacionamentos extraconjugais.','relationships'),
  ('classism','Classismo','Preconceito de classe.','identity'),
  ('gaslighting','Gaslighting','Manipulação psicológica.','mental_health');

-- CW do Dom Casmurro
insert into public.book_content_warnings (book_id, warning_id, severity, is_community, community_votes, notes)
select
  '22222222-2222-2222-2222-222222222222',
  cw.id,
  'moderate',
  false,
  0,
  'Presente no núcleo do romance.'
from public.content_warnings cw
where cw.code in ('adultery','gaslighting','sexism','classism');

-- =====================================================================
-- 2. Mood labels (pt-BR)
-- =====================================================================
insert into public.mood_labels (mood, label_pt, color_hex, icon) values
  ('adventurous','Aventureiro','#F59E0B','compass'),
  ('emotional','Emocionante','#EC4899','heart'),
  ('dark','Sombrio','#1F2937','moon'),
  ('funny','Divertido','#FBBF24','smile'),
  ('hopeful','Esperançoso','#10B981','sunrise'),
  ('informative','Informativo','#3B82F6','info'),
  ('inspiring','Inspirador','#8B5CF6','sparkles'),
  ('lighthearted','Descontraído','#34D399','feather'),
  ('mysterious','Misterioso','#6D28D9','search'),
  ('reflective','Reflexivo','#0EA5E9','brain'),
  ('sad','Triste','#64748B','cloud-rain'),
  ('tense','Tenso','#DC2626','alert'),
  ('challenging','Desafiador','#7C3AED','mountain');

-- =====================================================================
-- 3. Escolha editorial do mês
-- =====================================================================
insert into public.editorial_picks (
  book_id, season_id, kind, reference_month, title, rationale, is_active
) values (
  '22222222-2222-2222-2222-222222222222',
  '33333333-3333-3333-3333-333333333333',
  'book_of_the_month',
  date_trunc('month', current_date)::date,
  'Dom Casmurro — a dúvida que nos constitui',
  'Escolhemos reler Machado porque a pergunta sobre Capitu continua sendo, antes de tudo, uma pergunta sobre nós.',
  true
);

-- =====================================================================
-- 4. Mood stats baseline (vazio, será preenchido por votos)
-- =====================================================================
insert into public.book_mood_stats (book_id) values
  ('22222222-2222-2222-2222-222222222222')
on conflict (book_id) do nothing;

-- =====================================================================
-- 5. Milestones automáticos para a temporada 1
-- =====================================================================
select public.generate_milestones_for_season('33333333-3333-3333-3333-333333333333');

-- =====================================================================
-- 6. Conteúdo extra de exemplo
-- =====================================================================
insert into public.chapter_extra_content (chapter_id, kind, title, description, external_url, position, is_public)
select c.id, 'pdf', 'Guia de leitura — Capítulos I a V',
       'Perguntas para discussão em grupo e citações marcantes.',
       'https://exemplo.clube/guia-cap1.pdf', 1, true
from public.chapters c where c.number = 1;

insert into public.chapter_extra_content (chapter_id, kind, title, description, external_url, position, is_public)
select c.id, 'slides', 'Slides do encontro ao vivo',
       'Deck usado na discussão síncrona.',
       'https://exemplo.clube/slides-cap1.pdf', 2, true
from public.chapters c where c.number = 1;

-- =====================================================================
-- 7. Atividade interativa de exemplo
-- =====================================================================
insert into public.chapter_activities (chapter_id, kind, status, title, instructions, config, xp_reward, position)
select
  c.id, 'crossword', 'published',
  'Palavras cruzadas — personagens do romance',
  'Complete as lacunas com os nomes dos personagens.',
  jsonb_build_object(
    'rows', 5, 'cols', 5,
    'words', jsonb_build_array(
      jsonb_build_object('word','BENTINHO','row',0,'col',0,'dir','h'),
      jsonb_build_object('word','CAPITU','row',2,'col',0,'dir','h')
    )
  ),
  25, 1
from public.chapters c where c.number = 1;

-- =====================================================================
-- 8. Prompt de caderno interativo
-- =====================================================================
insert into public.chapter_prompts (chapter_id, position, prompt, hint, min_chars, max_chars)
select c.id, 1,
       'Qual sua hipótese sobre o ciúme de Bentinho antes de terminar o capítulo?',
       'Não há resposta certa — anote sua leitura.',
       20, 2000
from public.chapters c where c.number = 3;

-- =====================================================================
-- 9. Planos de assinatura
-- =====================================================================
insert into public.membership_plans (code, tier, name, description, price_cents, interval, perks) values
  ('free','free','Leitor','Acesso ao ciclo atual e à comunidade.',
   0, 'month',
   '[]'::jsonb),
  ('plus_monthly','plus','Plus (mensal)','Acesso antecipado, listas ilimitadas, badges premium.',
   1990, 'month',
   '[{"code":"early_access","label":"Acesso antecipado"},{"code":"unlimited_lists","label":"Listas ilimitadas"},{"code":"premium_badges","label":"Badges premium"}]'::jsonb),
  ('plus_annual','plus','Plus (anual)','Tudo do Plus com 2 meses de desconto.',
   19900, 'year',
   '[{"code":"early_access","label":"Acesso antecipado"},{"code":"unlimited_lists","label":"Listas ilimitadas"},{"code":"premium_badges","label":"Badges premium"},{"code":"annual_discount","label":"Desconto anual"}]'::jsonb),
  ('patron','patron','Patrono','Apoia o clube e recebe menções no podcast.',
   4990, 'month',
   '[{"code":"patron_credit","label":"Créditos no podcast"},{"code":"shop_discount","label":"Desconto na loja"}]'::jsonb);

-- =====================================================================
-- 10. Conquistas específicas (complementando o seed original)
-- =====================================================================
insert into public.achievements (code, title, description, rule, xp_reward) values
  ('brazilian_lit_expert','Especialista em Literatura Brasileira',
   'Leu 5 ou mais obras de autores brasileiros no clube.',
   '{"type":"genre_count","genre":"Literatura Brasileira","gte":5}'::jsonb, 150),
  ('five_books','Cinco livros lidos',
   'Concluiu 5 livros no clube.',
   '{"type":"count","source":"finish_book","gte":5}'::jsonb, 100),
  ('perfect_quiz','100% no quiz',
   'Acertou todas as perguntas de um quiz.',
   '{"type":"perfect_quiz","gte":1}'::jsonb, 75)
on conflict (code) do nothing;

-- =====================================================================
-- 11. Newsletter de exemplo (não disparada)
-- =====================================================================
insert into public.newsletter_issues (slug, subject, preview_text, body_markdown, audience_filter, created_by)
select
  'boas-vindas-t1',
  'Bem-vindo ao Clube — Temporada Dom Casmurro',
  'Começamos a leitura dia 1º. Veja como funciona.',
  E'# Bem-vindo ao Clube\n\nNesta temporada lemos **Dom Casmurro**.\n\n- Leia em blocos.\n- Marque o progresso.\n- Comente sem spoilers.',
  '{"tags":["welcome"]}'::jsonb,
  (select id from public.profiles where role = 'admin' limit 1);
```

---

## 12. Tipagens TypeScript

Gerar tipos automáticos:

```bash
supabase gen types typescript --linked > src/lib/supabase/database.types.ts
```

### 12.1 `domain.ts` (base)

**Arquivo:** `src/types/domain.ts`

```ts
export type ShelfStatus = 'want_to_read' | 'reading' | 'read' | 'dnf';
export type CycleStatus = 'planned' | 'enrolling' | 'active' | 'finished';
export type MeetingKind = 'online' | 'in_person' | 'hybrid';
export type MeetingStatus = 'scheduled' | 'live' | 'done' | 'cancelled';
export type ReactionKind = 'like' | 'love' | 'fire' | 'clap' | 'thinking';
export type XpSource =
  | 'join_meeting' | 'finish_chapter' | 'comment'
  | 'quiz_answer' | 'finish_book' | 'streak_bonus';

export interface Profile {
  id: string;
  username: string;
  display_name: string;
  avatar_url?: string | null;
  bio?: string | null;
  role: 'reader' | 'ambassador' | 'editor' | 'admin';
  level?: 'estudante' | 'junior' | 'pleno' | 'senior' | 'lideranca' | null;
  onboarding_done: boolean;
}

export interface Chapter {
  id: string;
  season_id: string;
  number: number;
  title: string;
  reading_range?: string | null;
  youtube_url?: string | null;
  summary?: string | null;
}

export interface CommentVisible {
  id: string;
  chapter_id: string;
  user_id: string;
  parent_id: string | null;
  created_at: string;
  likes_count: number;
  replies_count: number;
  is_spoiler: boolean;
  is_locked: boolean;
  content: string | null;
}

export interface QuizQuestion { id: string; chapter_id: string; question: string; options: string[]; }
export interface QuizAnswerIn { question_id: string; chosen_idx: number; }
export interface QuizAttemptResult { score: number; total: number; detail: { question_id: string; is_correct: boolean }[]; }
```

### 12.2 `domain.complement.ts` (complemento)

**Arquivo:** `src/types/domain.complement.ts`

```ts
export type MoodKind =
  | 'adventurous' | 'emotional' | 'dark' | 'funny' | 'hopeful'
  | 'informative' | 'inspiring' | 'lighthearted' | 'mysterious'
  | 'reflective' | 'sad' | 'tense' | 'challenging';

export type PaceKind = 'slow' | 'medium' | 'fast';
export type ContentWarningSeverity = 'minor' | 'moderate' | 'graphic';
export type EditorialPickKind =
  | 'book_of_the_month' | 'editorial_pick' | 'community_pick' | 'staff_pick';
export type ReadingListVisibility = 'private' | 'unlisted' | 'public';
export type ReadingListItemKind = 'book' | 'chapter' | 'quote' | 'external';
export type JournalVisibility = 'private' | 'friends' | 'club' | 'public';
export type FeedPostKind =
  | 'quote' | 'review' | 'shelf_update' | 'progress' | 'list'
  | 'club_invite' | 'link' | 'photo' | 'poll';
export type FeedVisibility = 'public' | 'followers' | 'club' | 'private';
export type FollowStatus = 'pending' | 'accepted' | 'blocked';
export type MemberTier = 'free' | 'plus' | 'pro' | 'patron' | 'corporate';
export type SubscriptionStatus =
  | 'trialing' | 'active' | 'past_due' | 'canceled' | 'paused' | 'incomplete';
export type PaymentProvider = 'stripe' | 'mercado_pago' | 'pagseguro' | 'manual';
export type NewsletterStatus =
  | 'pending' | 'confirmed' | 'unsubscribed' | 'bounced' | 'complained';
export type NewsletterFrequency = 'daily' | 'weekly' | 'monthly' | 'special_only';
export type ExtraContentKind =
  | 'pdf' | 'slides' | 'audio' | 'video' | 'link' | 'spreadsheet'
  | 'deck' | 'notebook' | 'dataset' | 'template';
export type ActivityKind =
  | 'quiz' | 'crossword' | 'word_search' | 'poll' | 'trivia'
  | 'flashcards' | 'debate_prompt' | 'drawing_prompt' | 'roleplay'
  | 'essay_prompt' | 'timed_challenge';
export type ActivityStatus = 'draft' | 'published' | 'archived';
export type SocialTemplateKind =
  | 'quote_card' | 'progress_card' | 'milestone_card'
  | 'review_card' | 'list_card' | 'aura_card' | 'streak_card';
export type SocialRenderStatus = 'queued' | 'rendered' | 'failed' | 'expired';

export interface ContentWarning {
  id: string;
  code: string;
  label: string;
  description?: string | null;
  category?: string | null;
}

export interface BookContentWarning {
  id: string;
  book_id: string;
  warning_id: string;
  severity: ContentWarningSeverity;
  is_community: boolean;
  community_votes: number;
  notes?: string | null;
}

export interface BookMoodStats {
  book_id: string;
  mood_counts: Record<MoodKind, number>;
  mood_percent: Partial<Record<MoodKind, number>>;
  pace_percent: Record<PaceKind, number>;
  plot_vs_character_avg: number;
  sample_size: number;
}

export interface EditorialPick {
  id: string;
  book_id: string;
  season_id?: string | null;
  kind: EditorialPickKind;
  reference_month: string; // YYYY-MM-DD
  title?: string | null;
  rationale?: string | null;
  media_url?: string | null;
  is_active: boolean;
}

export interface ReadingJournalEntry {
  id: string;
  user_id: string;
  book_id: string;
  chapter_id?: string | null;
  season_id?: string | null;
  entry_date: string;
  page_from?: number | null;
  page_to?: number | null;
  percent_at?: number | null;
  minutes_read?: number | null;
  mood_at_time?: MoodKind | null;
  title?: string | null;
  body: string;
  visibility: JournalVisibility;
  is_spoiler: boolean;
  min_percent: number;
  likes_count: number;
  created_at: string;
  updated_at: string;
}

export interface ReadingList {
  id: string;
  owner_id: string;
  slug: string;
  title: string;
  description?: string | null;
  cover_url?: string | null;
  visibility: ReadingListVisibility;
  is_collaborative: boolean;
  theme?: string | null;
  tags: string[];
  items_count: number;
}

export interface ReadingListItem {
  id: string;
  list_id: string;
  kind: ReadingListItemKind;
  book_id?: string | null;
  chapter_id?: string | null;
  external_url?: string | null;
  quote_text?: string | null;
  note?: string | null;
  position: number;
}

export interface Milestone {
  id: string;
  chapter_id?: string | null;
  season_id: string;
  book_id: string;
  position: number;
  title: string;
  description?: string | null;
  kind: 'auto' | 'custom';
  page_from?: number | null;
  page_to?: number | null;
  chapter_from?: number | null;
  chapter_to?: number | null;
  percent_from?: number | null;
  percent_to?: number | null;
  target_date?: string | null;
  xp_reward: number;
}

export interface UserQuizAverage {
  user_id: string;
  attempts_total: number;
  score_sum: number;
  total_sum: number;
  average_percent: number;
  best_percent: number;
  last_attempt_at?: string | null;
}

export interface FeedPost {
  id: string;
  author_id: string;
  kind: FeedPostKind;
  visibility: FeedVisibility;
  club_id?: string | null;
  book_id?: string | null;
  chapter_id?: string | null;
  season_id?: string | null;
  body?: string | null;
  quote_text?: string | null;
  link_url?: string | null;
  cover_url?: string | null;
  metadata: Record<string, unknown>;
  is_spoiler: boolean;
  min_percent: number;
  likes_count: number;
  comments_count: number;
  shares_count: number;
  created_at: string;
  updated_at: string;
}

export interface ReaderMatch {
  matched_id: string;
  username: string;
  display_name: string;
  avatar_url?: string | null;
  similarity: number;
  shared_books: number;
  shared_moods: MoodKind[];
}

export interface MembershipPlan {
  id: string;
  code: string;
  tier: MemberTier;
  name: string;
  description?: string | null;
  price_cents: number;
  currency: string;
  interval: 'month' | 'year' | 'lifetime';
  stripe_price_id?: string | null;
  perks: Array<{ code: string; label: string; description?: string }>;
  is_active: boolean;
}

export interface UserSubscription {
  id: string;
  user_id: string;
  plan_id: string;
  status: SubscriptionStatus;
  provider: PaymentProvider;
  current_period_start?: string | null;
  current_period_end?: string | null;
  cancel_at_period_end: boolean;
}

export interface NewsletterSubscriber {
  id: string;
  user_id?: string | null;
  email: string;
  name?: string | null;
  status: NewsletterStatus;
  frequency: NewsletterFrequency;
  source?: string | null;
  tags: string[];
  confirmed_at?: string | null;
  unsubscribed_at?: string | null;
}

export interface ChapterExtraContent {
  id: string;
  chapter_id?: string | null;
  season_id?: string | null;
  book_id?: string | null;
  kind: ExtraContentKind;
  title: string;
  description?: string | null;
  storage_path?: string | null;
  external_url?: string | null;
  preview_url?: string | null;
  size_bytes?: number | null;
  mime_type?: string | null;
  position: number;
  is_public: boolean;
}

export interface ChapterActivity {
  id: string;
  chapter_id: string;
  kind: ActivityKind;
  status: ActivityStatus;
  title: string;
  instructions?: string | null;
  config: Record<string, unknown>;
  xp_reward: number;
  time_limit_sec?: number | null;
  position: number;
  available_from?: string | null;
  available_until?: string | null;
}

export interface ChapterPrompt {
  id: string;
  chapter_id: string;
  position: number;
  prompt: string;
  hint?: string | null;
  min_chars: number;
  max_chars: number;
}

export interface ChapterPromptResponse {
  prompt_id: string;
  user_id: string;
  response: string;
  visibility: JournalVisibility;
  created_at: string;
  updated_at: string;
}

export interface SocialRenderJob {
  id: string;
  user_id: string;
  kind: SocialTemplateKind;
  payload: Record<string, unknown>;
  status: SocialRenderStatus;
  image_url?: string | null;
  error?: string | null;
  created_at: string;
  rendered_at?: string | null;
}
```

---

## 13. Cliente Supabase (frontend)

### 13.1 Browser client — `src/lib/supabase/client.ts`

```ts
import { createBrowserClient } from "@supabase/ssr";
import type { Database } from "./database.types";

export const supabase = createBrowserClient<Database>(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
);
```

### 13.2 Server client — `src/lib/supabase/server.ts`

```ts
import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import type { Database } from "./database.types";

export async function getServerSupabase() {
  const store = await cookies();
  return createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => store.getAll(),
        setAll: (list) => list.forEach(({ name, value, options }) =>
          store.set(name, value, options)),
      },
    },
  );
}
```

### 13.3 Middleware — `src/lib/supabase/middleware.ts`

```ts
import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

export async function updateSession(req: NextRequest) {
  const res = NextResponse.next({ request: req });
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => req.cookies.getAll(),
        setAll: (list) => list.forEach(({ name, value, options }) =>
          res.cookies.set(name, value, options)),
      },
    },
  );
  await supabase.auth.getUser();
  return res;
}
```

### 13.4 Chamadas-chave (exemplos)

```ts
// Comentários visíveis (com anti-spoiler aplicado pela view)
const { data: comments } = await supabase
  .from("v_comments_visible")
  .select("*")
  .eq("chapter_id", chapterId)
  .order("created_at", { ascending: true });

// Criar comentário
await supabase.from("comments").insert({
  chapter_id: chapterId, content, is_spoiler: false, min_percent: 0,
});

// Reagir
await supabase.from("reactions").upsert(
  { comment_id, user_id, kind: "like" },
  { onConflict: "comment_id,user_id" },
);

// Quiz (via Edge Function)
const res = await fetch(`${url}/functions/v1/quiz-validate`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
  body: JSON.stringify({ chapter_id, answers }),
});

// Real-time de comentários
supabase.channel(`comments:chapter:${chapterId}`)
  .on("postgres_changes",
      { event: "INSERT", schema: "public", table: "comments",
        filter: `chapter_id=eq.${chapterId}` },
      (payload) => console.log("novo comentário", payload.new))
  .subscribe();
```

---

## 14. Roadmap de execução (checklist)

### Fase 1 — Fundação (semana 1)
- [ ] `supabase init` + link
- [ ] Aplicar migration `000_extensions_and_enums.sql`
- [ ] Aplicar migrations `001` a `003` (profiles, books, seasons, chapters)
- [ ] Habilitar Auth (Email + Google)
- [ ] Aplicar trigger `handle_new_user`
- [ ] Gerar types (`database.types.ts`)

### Fase 2 — Núcleo P0 (semanas 2–3)
- [ ] Migration `004_meetings` + `005_progress`
- [ ] Migration `006_comments_and_reactions` + `007_quiz`
- [ ] Aplicar `013_rls_policies`
- [ ] Aplicar `014_functions_and_triggers` (XP, streak, counters)
- [ ] Aplicar `014_views` (v_comments_visible, v_chapter_audience)
- [ ] Deploy Edge Function `quiz-validate`
- [ ] Seed `Dom Casmurro` (livro + 5 capítulos + quiz + prompt)
- [ ] Criar canal realtime `comments:chapter:*`

### Fase 3 — Gamificação P1 (semanas 4–5)
- [ ] Migration `008_gamification` (`xp_events`, `user_xp`, `user_streaks`)
- [ ] Migration `009_polls_and_votes`
- [ ] Migration `010_achievements`
- [ ] Migration `011_notifications`
- [ ] Deploy `award-xp` + `vote-next-book`
- [ ] Habilitar Realtime em `notifications`
- [ ] View `v_season_ranking`

### Fase 4 — Expansão P2 (semanas 6)
- [ ] Migration `012_p2_tables` (`video_timed_comments`, `challenges`, `user_clubs`)
- [ ] Habilitar `pgvector` e coluna `embedding` em `books`
- [ ] Deploy `ai-recommendations` + RPC `match_books`
- [ ] Deploy `scheduled-reminders` + `pg_cron`
- [ ] Bucket `manuscripts` + RLS
- [ ] Painel de estatísticas avançadas (views materializadas)

### Fase 5 — Metadados ricos e curadoria (semana 7)
- [ ] Aplicar `20260101001650_extensions_and_enums_complement.sql`
- [ ] Aplicar `20260101001700_book_metadata_and_reading.sql`
- [ ] Popular `content_warnings` e `mood_labels` (seed complementar)
- [ ] Aplicar `editorial_picks` e testar rotação mensal
- [ ] RLS de `book_content_warnings` e `book_mood_votes`
- [ ] Trigger `refresh_book_mood_stats` em produção
- [ ] Expor `v_host_prompt_results` no frontend (contagem "Concordo/Discordo/Não sei")
- [ ] Expor `v_video_timed_comment_stats` no player do YouTube

### Fase 6 — Diário e listas (semana 8)
- [ ] Aplicar `20260101001800_journal_and_lists.sql`
- [ ] Bucket `journal-media` + políticas
- [x] Habilitar `reading_journal_entries` no Realtime (tabela consta na publicação remota; teste end-to-end de Auth ainda depende de ambiente isolado)
- [ ] UI de diário (entrada por dia, mídia, mood)
- [ ] UI de listas (criar, colaborar, compartilhar)
- [ ] UI de "Up Next" (máx. 5 livros)
- [ ] Testes RLS de `journal_visibility = 'friends'` com seguidores mútuos

### Fase 7 — Milestones e estatísticas (semana 9)
- [ ] Aplicar `20260101001900_milestones_stats_quiz.sql`
- [ ] Rodar `generate_milestones_for_season` para todas as temporadas ativas
- [ ] Triggers `refresh_user_quiz_averages` e `refresh_chapter_quiz_averages`
- [ ] Expor médias na UI de perfil e de capítulo
- [ ] Popular `reading_goals` e verificar `refresh_reading_goal_progress`
- [ ] Adicionar prompts de desafio (`challenge_prompts`)

### Fase 8 — Feed, seguidores e match (semana 10)
- [ ] Aplicar `20260101002000_social_feed_and_match.sql`
- [ ] Bucket `feed-media`
- [ ] Realtime em `feed_posts`, `feed_post_likes`, `feed_post_comments`
- [ ] Deploy `ai-user-embeddings` + `match-readers`
- [ ] Habilitar `match_readers` RPC e `user_match_cache`
- [ ] UI do feed com filtros (público / seguindo / clubes)
- [ ] UI de match de leitores

### Fase 9 — Monetização e newsletter (semana 11)
- [ ] Aplicar `20260101002100_monetization_members_newsletter.sql`
- [ ] Deploy `stripe-webhook` com `STRIPE_WEBHOOK_SECRET`
- [ ] Popular `membership_plans` (seed complementar)
- [ ] Deploy `newsletter-dispatch`
- [ ] Bucket `newsletter-assets`
- [ ] Rastreio de cliques de afiliado (`affiliate_clicks`)
- [ ] Webhook de cancelamento e downgrade

### Fase 10 — Conteúdo extra, jogos e social cards (semana 12)
- [ ] Aplicar `20260101002200_extra_content_and_activities.sql`
- [ ] Aplicar `20260101002250_social_render_jobs.sql`
- [ ] Bucket `chapter-extras`
- [ ] Deploy `social-render-card`
- [ ] Bucket `social-cards`
- [ ] UI de atividades (`crossword`, `quiz`, `flashcards`, `poll`, ...)
- [ ] UI de caderno interativo (`chapter_prompt_responses`)
- [ ] Módulo de geração de cards para redes sociais

### Fase 11 — Consolidação (semana 13)
- [ ] Aplicar `20260101002300_rls_complement.sql`
- [ ] Aplicar `20260101002400_views_and_counters.sql`
- [ ] Aplicar `20260101002450_realtime_complement.sql`
- [ ] Aplicar `20260101002500_functions_complement.sql`
- [ ] Refresh de `mv_book_community_stats` (job `pg_cron`)
- [ ] Auditar índices (`explain analyze` em feed, match, quiz)
- [ ] Testes RLS cruzados entre: diário, listas, feed, match, newsletter
- [ ] Atualizar `database.types.ts` (gerar via `supabase gen types`)
- [ ] Atualizar `domain.ts` com o arquivo `domain.complement.ts`

### Validação final
- [ ] Testes RLS (`supabase test db`) com múltiplos usuários
- [ ] Testes de Edge Functions (`supabase functions serve` + `curl`)
- [ ] Auditoria de índice (`explain analyze` nas queries críticas)
- [ ] Backup automático + monitoramento (`pg_stat_statements`)
- [ ] Documentar contratos no OpenAPI/Swagger interno

---

## Resumo consolidado do que este SDDBD entrega

| Camada | Conteúdo |
|---|---|
| **Migrations** | 29 arquivos SQL cobrindo P0 → P3, RLS, triggers, views, Realtime, Storage |
| **Metadados ricos** | `content_warnings`, `book_content_warnings`, `book_mood_votes`, `book_mood_stats`, `mood_labels`, `editorial_picks` |
| **Leitura pessoal** | `reading_journal_entries`, `reading_journal_attachments`, `reading_journal_likes`, `reading_lists`, `reading_list_items`, `reading_list_collaborators`, `user_up_next`, `buddy_reads` |
| **Gamificação e stats** | `xp_events`, `user_xp`, `user_streaks`, `milestones`, `user_milestone_progress`, `user_quiz_averages`, `chapter_quiz_averages`, `reading_goals`, `reading_goal_progress`, `challenge_prompts` |
| **Comunidade e social** | `comments`, `reactions`, `host_prompts`, `video_timed_comments`, `feed_posts`, `feed_post_media`, `feed_post_likes`, `feed_post_comments`, `follows`, `user_reading_preferences`, `user_reading_embeddings`, `user_match_cache` |
| **Monetização e newsletter** | `membership_plans`, `user_subscriptions`, `payment_events`, `user_membership_perks`, `newsletter_subscribers`, `newsletter_issues`, `newsletter_deliveries`, `affiliate_clicks` |
| **Conteúdo extra e jogos** | `chapter_extra_content`, `chapter_activities`, `chapter_activity_attempts`, `chapter_prompts`, `chapter_prompt_responses`, `social_render_jobs` |
| **Agregações** | `v_chapter_audience`, `v_season_ranking`, `v_comments_visible`, `v_host_prompt_results`, `v_video_timed_comment_stats`, `mv_book_community_stats`, `v_user_reading_overview`, `v_club_progress_panel`, `v_feed_post_counters` |
| **RPCs** | `match_books`, `match_readers`, `build_user_reading_snapshot`, `refresh_book_mood_stats`, `generate_milestones_for_season`, `refresh_reading_goal_progress`, `refresh_user_quiz_averages`, `refresh_chapter_quiz_averages`, `refresh_content_warning_votes`, `get_reader_matches` |
| **Edge Functions** | `quiz-validate`, `award-xp`, `vote-next-book`, `scheduled-reminders`, `ai-recommendations`, `ai-user-embeddings`, `match-readers`, `newsletter-dispatch`, `stripe-webhook`, `social-render-card`, `generate-book-embeddings` |
| **Buckets** | `avatars`, `book-covers`, `manuscripts`, `meeting-slides`, `journal-media`, `chapter-extras`, `feed-media`, `newsletter-assets`, `social-cards`, `ebooks` |
| **Anti-spoiler** | View `v_comments_visible` + coluna `min_percent` + validação por `user_progress.percent` |
| **Gamificação** | Ledger `xp_events` + saldo `user_xp` + `user_streaks` + `achievements` |
| **Integrações** | Webhooks (Resend, Discord, Google Calendar, Stripe), cron via `pg_cron`/`pg_net` |
| **Tipagem** | `src/lib/supabase/database.types.ts` gerado a partir do schema remoto em 2026-10-09 + `domain.ts` + `domain.complement.ts` |
| **Cliente** | `client.ts`, `server.ts`, `middleware.ts` (Next.js 15 + @supabase/ssr) |
| **Seed** | `seed.sql` (MVP Dom Casmurro) + `seed_complement.sql` (moods, CWs, editorial, milestones, extras, atividades, prompts, planos, conquistas, newsletter) |
| **Roadmap** | Fases 1 a 11 com checklist por arquivo |

Este `SDDBD.md` é o documento **executável definitivo**: cada bloco acima vira um arquivo real na pasta `supabase/`. Comece pelo **Fase 1** do roadmap e siga em ordem — a ordem das migrations foi desenhada para que cada arquivo dependa apenas dos anteriores.
