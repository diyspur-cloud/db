-- Source: SDDBD2.md. Generated idempotent migration.
-- Extensions adicionais (além das já carregadas em 000)
create extension if not exists "unaccent";     -- busca normalizada em newsletters/feed
create extension if not exists "btree_gin";    -- índices compostos em arrays/jsonb

-- Enums complementares
DO $$ BEGIN CREATE TYPE public.mood_kind AS ENUM (
  'adventurous','emotional','dark','funny','hopeful','informative',
  'inspiring','lighthearted','mysterious','reflective','sad','tense','challenging'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE public.pace_kind AS ENUM ('slow','medium','fast'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.content_warning_severity AS ENUM ('minor','moderate','graphic'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.editorial_pick_kind AS ENUM ('book_of_the_month','editorial_pick','community_pick','staff_pick'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.reading_list_visibility AS ENUM ('private','unlisted','public'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.reading_list_item_kind AS ENUM ('book','chapter','quote','external'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.journal_visibility AS ENUM ('private','friends','club','public'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.feed_post_kind AS ENUM ('quote','review','shelf_update','progress','list','club_invite','link','photo','poll'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.feed_visibility AS ENUM ('public','followers','club','private'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.follow_status AS ENUM ('pending','accepted','blocked'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.member_tier AS ENUM ('free','plus','pro','patron','corporate'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.subscription_status AS ENUM ('trialing','active','past_due','canceled','paused','incomplete'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.payment_provider AS ENUM ('stripe','mercado_pago','pagseguro','manual'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.newsletter_status AS ENUM ('pending','confirmed','unsubscribed','bounced','complained'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.newsletter_frequency AS ENUM ('daily','weekly','monthly','special_only'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.extra_content_kind AS ENUM ('pdf','slides','audio','video','link','spreadsheet','deck','notebook','dataset','template'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.activity_kind AS ENUM ('quiz','crossword','word_search','poll','trivia','flashcards','debate_prompt','drawing_prompt','roleplay','essay_prompt','timed_challenge'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.activity_status AS ENUM ('draft','published','archived'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.social_template_kind AS ENUM ('quote_card','progress_card','milestone_card','review_card','list_card','aura_card','streak_card'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.social_render_status AS ENUM ('queued','rendered','failed','expired'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
