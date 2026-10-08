-- Source: SDDBD2.md. Generated idempotent migration.
-- Extensions
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";
create extension if not exists "vector";        -- P2: recomendações + match entre leitores
create extension if not exists "pg_trgm";       -- busca fuzzy de títulos

-- Enums globais
DO $$ BEGIN CREATE TYPE public.shelf_status AS ENUM ('want_to_read','reading','read','dnf'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.cycle_status AS ENUM ('planned','enrolling','active','finished'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.meeting_status AS ENUM ('scheduled','live','done','cancelled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.meeting_kind AS ENUM ('online','in_person','hybrid'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.user_role AS ENUM ('reader','ambassador','editor','admin'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.reaction_kind AS ENUM ('like','love','fire','clap','thinking'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.xp_source AS ENUM (
  'join_meeting','finish_chapter','comment','quiz_answer','finish_book','streak_bonus'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.notification_kind AS ENUM (
  'new_chapter','meeting_reminder','reply','mention','badge_unlocked','poll_open'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.poll_status AS ENUM ('open','closed'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.proposal_status AS ENUM ('pending','approved','rejected','winner'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE EXTENSION IF NOT EXISTS citext;
