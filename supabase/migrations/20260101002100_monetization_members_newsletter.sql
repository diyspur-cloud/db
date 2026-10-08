-- Source: SDDBD2.md. Generated idempotent migration.
-- =====================================================================
-- 1. Planos de assinatura / tiers
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.membership_plans (
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
CREATE TABLE IF NOT EXISTS public.user_subscriptions (
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
CREATE INDEX IF NOT EXISTS us_user_idx   on public.user_subscriptions (user_id);
CREATE INDEX IF NOT EXISTS us_status_idx on public.user_subscriptions (status);

-- Registro bruto de eventos de gateway (auditoria/replay)
CREATE TABLE IF NOT EXISTS public.payment_events (
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
CREATE TABLE IF NOT EXISTS public.user_membership_perks (
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
CREATE TABLE IF NOT EXISTS public.newsletter_subscribers (
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
CREATE INDEX IF NOT EXISTS ns_status_idx on public.newsletter_subscribers (status);
CREATE TABLE IF NOT EXISTS public.newsletter_issues (
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
CREATE TABLE IF NOT EXISTS public.newsletter_deliveries (
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
CREATE TABLE IF NOT EXISTS public.affiliate_clicks (
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
CREATE INDEX IF NOT EXISTS ac_book_idx on public.affiliate_clicks (book_id, created_at desc);
