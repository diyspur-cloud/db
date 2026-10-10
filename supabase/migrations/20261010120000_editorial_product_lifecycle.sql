-- DIYSPUR editorial/product lifecycle: clubs, private journal integrity and list concurrency.
-- This migration is additive and does not seed users, content or secrets.

-- -----------------------------------------------------------------------------
-- User-created clubs
-- -----------------------------------------------------------------------------
ALTER TABLE public.user_clubs
  ADD COLUMN IF NOT EXISTS version bigint NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS archived_at timestamptz;

DO $$ BEGIN
  ALTER TABLE public.user_clubs ADD CONSTRAINT user_clubs_name_length
    CHECK (length(btrim(name)) BETWEEN 3 AND 80);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE public.user_clubs ADD CONSTRAINT user_clubs_description_length
    CHECK (description IS NULL OR length(description) <= 2000);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE public.user_club_members ADD CONSTRAINT user_club_member_role_valid
    CHECK (role IN ('owner','moderator','member'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.user_club_invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id uuid NOT NULL REFERENCES public.user_clubs(id) ON DELETE CASCADE,
  invited_user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  invited_by uuid NOT NULL REFERENCES public.profiles(id),
  expires_at timestamptz NOT NULL,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS club_pending_invite_unique
  ON public.user_club_invitations(club_id, invited_user_id)
  WHERE accepted_at IS NULL AND revoked_at IS NULL;
ALTER TABLE public.user_club_invitations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_club_invitations FROM anon, authenticated;
GRANT SELECT ON public.user_club_invitations TO authenticated;
DROP POLICY IF EXISTS club_invitation_read ON public.user_club_invitations;
CREATE POLICY club_invitation_read ON public.user_club_invitations FOR SELECT TO authenticated
  USING (invited_user_id = (SELECT auth.uid()) OR invited_by = (SELECT auth.uid()));

CREATE OR REPLACE FUNCTION private.create_user_club(
  p_name text, p_description text, p_private boolean, p_request_id uuid
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE v_user uuid := auth.uid(); v_existing_owner uuid;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'unauthenticated' USING ERRCODE='42501'; END IF;
  IF p_request_id IS NULL OR p_private IS NULL OR length(btrim(coalesce(p_name,''))) NOT BETWEEN 3 AND 80
     OR length(coalesce(p_description,'')) > 2000 THEN
    RAISE EXCEPTION 'invalid_club' USING ERRCODE='23514';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request_id::text, 0));
  SELECT owner_id INTO v_existing_owner FROM public.user_clubs WHERE id = p_request_id;
  IF FOUND THEN
    IF v_existing_owner <> v_user THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
    RETURN p_request_id;
  END IF;
  INSERT INTO public.user_clubs(id, owner_id, name, slug, description, is_private)
  VALUES (p_request_id, v_user, btrim(p_name), 'clube-' || replace(p_request_id::text, '-', ''),
          nullif(btrim(p_description), ''), p_private);
  INSERT INTO public.user_club_members(club_id, user_id, role) VALUES (p_request_id, v_user, 'owner');
  RETURN p_request_id;
END;
$fn$;
REVOKE ALL ON FUNCTION private.create_user_club(text,text,boolean,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.create_user_club(text,text,boolean,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.create_user_club(
  p_name text, p_description text, p_private boolean, p_request_id uuid
) RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $fn$
  SELECT private.create_user_club(p_name,p_description,p_private,p_request_id)
$fn$;
REVOKE ALL ON FUNCTION public.create_user_club(text,text,boolean,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_user_club(text,text,boolean,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION private.update_user_club(
  p_club uuid, p_version bigint, p_name text, p_description text, p_private boolean
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE v_version bigint;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'unauthenticated' USING ERRCODE='42501'; END IF;
  SELECT version INTO v_version FROM public.user_clubs
    WHERE id=p_club AND owner_id=auth.uid() AND archived_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  IF v_version <> p_version THEN RAISE EXCEPTION 'conflict' USING ERRCODE='40001'; END IF;
  IF length(btrim(coalesce(p_name,''))) NOT BETWEEN 3 AND 80 OR length(coalesce(p_description,'')) > 2000
     OR p_private IS NULL THEN RAISE EXCEPTION 'invalid_club' USING ERRCODE='23514'; END IF;
  UPDATE public.user_clubs SET name=btrim(p_name), description=nullif(btrim(p_description),''),
    is_private=p_private, version=version+1 WHERE id=p_club RETURNING version INTO v_version;
  RETURN v_version;
END;
$fn$;
REVOKE ALL ON FUNCTION private.update_user_club(uuid,bigint,text,text,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.update_user_club(uuid,bigint,text,text,boolean) TO authenticated;
CREATE OR REPLACE FUNCTION public.update_user_club(
  p_club uuid, p_version bigint, p_name text, p_description text, p_private boolean
) RETURNS bigint LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $fn$
  SELECT private.update_user_club(p_club,p_version,p_name,p_description,p_private)
$fn$;
REVOKE ALL ON FUNCTION public.update_user_club(uuid,bigint,text,text,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_user_club(uuid,bigint,text,text,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION private.join_user_club(p_club uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE v_private boolean; v_archived timestamptz;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'unauthenticated' USING ERRCODE='42501'; END IF;
  SELECT is_private, archived_at INTO v_private, v_archived FROM public.user_clubs WHERE id=p_club FOR UPDATE;
  IF NOT FOUND OR v_archived IS NOT NULL OR v_private THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  INSERT INTO public.user_club_members(club_id,user_id,role) VALUES(p_club,auth.uid(),'member') ON CONFLICT DO NOTHING;
  RETURN true;
END;
$fn$;
REVOKE ALL ON FUNCTION private.join_user_club(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.join_user_club(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.join_user_club(p_club uuid) RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $fn$ SELECT private.join_user_club(p_club) $fn$;
REVOKE ALL ON FUNCTION public.join_user_club(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.join_user_club(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION private.leave_user_club(p_club uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'unauthenticated' USING ERRCODE='42501'; END IF;
  IF EXISTS (SELECT 1 FROM public.user_club_members WHERE club_id=p_club AND user_id=auth.uid() AND role='owner')
    THEN RAISE EXCEPTION 'owner_must_archive' USING ERRCODE='42501'; END IF;
  DELETE FROM public.user_club_members WHERE club_id=p_club AND user_id=auth.uid();
  RETURN true;
END;
$fn$;
REVOKE ALL ON FUNCTION private.leave_user_club(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.leave_user_club(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.leave_user_club(p_club uuid) RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $fn$ SELECT private.leave_user_club(p_club) $fn$;
REVOKE ALL ON FUNCTION public.leave_user_club(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.leave_user_club(uuid) TO authenticated;

-- Restrict club reads to public active clubs, owner or member; preserve non-recursive helper.
CREATE OR REPLACE FUNCTION private.can_view_user_club(p_club uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $fn$
  SELECT EXISTS (SELECT 1 FROM public.user_clubs c WHERE c.id=p_club AND c.archived_at IS NULL AND
    (NOT c.is_private OR c.owner_id=auth.uid() OR EXISTS
      (SELECT 1 FROM public.user_club_members m WHERE m.club_id=c.id AND m.user_id=auth.uid())))
$fn$;
REVOKE ALL ON FUNCTION private.can_view_user_club(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.can_view_user_club(uuid) TO anon,authenticated;
DROP POLICY IF EXISTS uclubs_read_public ON public.user_clubs;
DROP POLICY IF EXISTS "uclubs_read_public" ON public.user_clubs;
CREATE POLICY uclubs_read_public ON public.user_clubs FOR SELECT USING (private.can_view_user_club(id));
DROP POLICY IF EXISTS uclub_members_read_visible ON public.user_club_members;
DROP POLICY IF EXISTS uclub_members_read ON public.user_club_members;
CREATE POLICY uclub_members_read_visible ON public.user_club_members FOR SELECT USING (
  user_id=auth.uid() OR EXISTS (SELECT 1 FROM public.user_clubs c WHERE c.id=club_id AND c.owner_id=auth.uid())
  OR private.can_view_user_club(club_id)
);

-- -----------------------------------------------------------------------------
-- Journal integrity and privacy-first read policy
-- -----------------------------------------------------------------------------
ALTER TABLE public.reading_journal_entries
  ADD COLUMN IF NOT EXISTS version bigint NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS shared_club_id uuid REFERENCES public.user_clubs(id) ON DELETE SET NULL;
DO $$ BEGIN
  ALTER TABLE public.reading_journal_entries ADD CONSTRAINT journal_pages_valid_v2
    CHECK ((page_from IS NULL OR page_from >= 1) AND (page_to IS NULL OR page_to >= 1)
      AND (page_from IS NULL OR page_to IS NULL OR page_to >= page_from));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE public.reading_journal_entries ADD CONSTRAINT journal_minutes_valid_v2 CHECK (minutes_read BETWEEN 0 AND 1440);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
UPDATE public.reading_journal_entries SET shared_club_id=NULL WHERE visibility='club' AND shared_club_id IS NULL;
DROP POLICY IF EXISTS journal_read_own ON public.reading_journal_entries;
CREATE POLICY journal_read_own ON public.reading_journal_entries FOR SELECT USING (
  user_id=auth.uid() OR (visibility='public' AND is_spoiler=false)
  OR (visibility='club' AND shared_club_id IS NOT NULL AND EXISTS
    (SELECT 1 FROM public.user_club_members m WHERE m.club_id=shared_club_id AND m.user_id=auth.uid()))
);

-- -----------------------------------------------------------------------------
-- Lists: optimistic concurrency contract and atomic reorder.
-- -----------------------------------------------------------------------------
ALTER TABLE public.reading_lists ADD COLUMN IF NOT EXISTS version bigint NOT NULL DEFAULT 1;
DO $$ BEGIN
  ALTER TABLE public.reading_list_items ADD CONSTRAINT list_item_position_nonnegative_v2 CHECK (position>=0);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
CREATE OR REPLACE FUNCTION private.reorder_reading_list(p_list uuid,p_version bigint,p_item_ids uuid[])
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE v_version bigint; v_count integer;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'unauthenticated' USING ERRCODE='42501'; END IF;
  IF NOT private.can_edit_reading_list(p_list) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  SELECT version INTO v_version FROM public.reading_lists WHERE id=p_list FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found' USING ERRCODE='P0002'; END IF;
  IF v_version<>p_version THEN RAISE EXCEPTION 'conflict' USING ERRCODE='40001'; END IF;
  IF p_item_ids IS NULL OR cardinality(p_item_ids)<>(SELECT count(DISTINCT id) FROM unnest(p_item_ids) x(id)) THEN
    RAISE EXCEPTION 'invalid_order' USING ERRCODE='23514'; END IF;
  SELECT count(*) INTO v_count FROM public.reading_list_items WHERE list_id=p_list;
  IF v_count<>cardinality(p_item_ids) OR EXISTS (SELECT 1 FROM unnest(p_item_ids) x(id)
    WHERE NOT EXISTS (SELECT 1 FROM public.reading_list_items i WHERE i.id=x.id AND i.list_id=p_list))
    THEN RAISE EXCEPTION 'invalid_order' USING ERRCODE='23514'; END IF;
  UPDATE public.reading_list_items i SET position=x.ordinality-1
    FROM unnest(p_item_ids) WITH ORDINALITY x(id,ordinality) WHERE i.id=x.id AND i.list_id=p_list;
  UPDATE public.reading_lists SET version=version+1,updated_at=statement_timestamp() WHERE id=p_list RETURNING version INTO v_version;
  RETURN v_version;
END;
$fn$;
REVOKE ALL ON FUNCTION private.reorder_reading_list(uuid,bigint,uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.reorder_reading_list(uuid,bigint,uuid[]) TO authenticated;
CREATE OR REPLACE FUNCTION public.reorder_reading_list(p_list uuid,p_version bigint,p_item_ids uuid[])
RETURNS bigint LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $fn$ SELECT private.reorder_reading_list(p_list,p_version,p_item_ids) $fn$;
REVOKE ALL ON FUNCTION public.reorder_reading_list(uuid,bigint,uuid[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reorder_reading_list(uuid,bigint,uuid[]) TO authenticated;
