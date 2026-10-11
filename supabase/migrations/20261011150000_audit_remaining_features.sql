-- Remaining audit features. Never edit applied migrations.

-- AUD-08: atomic list insertion and uniqueness.
DELETE FROM public.reading_list_items a USING public.reading_list_items b
WHERE a.id > b.id AND a.list_id = b.list_id AND a.book_id = b.book_id AND a.book_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS reading_list_book_unique ON public.reading_list_items(list_id, book_id) WHERE book_id IS NOT NULL;

CREATE OR REPLACE FUNCTION private.add_book_to_reading_list(p_list_id uuid, p_book_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_user uuid := auth.uid(); v_position int;
BEGIN
  IF v_user IS NULL OR NOT EXISTS (SELECT 1 FROM public.reading_lists l WHERE l.id=p_list_id AND private.can_edit_reading_list(l.id)) THEN
    RETURN jsonb_build_object('ok',false,'message','Você não pode alterar esta lista.');
  END IF;
  PERFORM 1 FROM public.reading_lists WHERE id=p_list_id FOR UPDATE;
  IF EXISTS (SELECT 1 FROM public.reading_list_items WHERE list_id=p_list_id AND book_id=p_book_id) THEN
    RETURN jsonb_build_object('ok',true,'message','Este livro já está na lista.');
  END IF;
  SELECT COALESCE(MAX(position),-1)+1 INTO v_position FROM public.reading_list_items WHERE list_id=p_list_id;
  INSERT INTO public.reading_list_items(list_id,book_id,kind,added_by,position) VALUES(p_list_id,p_book_id,'book'::public.reading_list_item_kind,v_user,v_position);
  RETURN jsonb_build_object('ok',true,'message','Livro adicionado à lista.');
END;
$$;
REVOKE ALL ON FUNCTION private.add_book_to_reading_list(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.add_book_to_reading_list(uuid,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.add_book_to_reading_list(p_list_id uuid,p_book_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $$ SELECT private.add_book_to_reading_list(p_list_id,p_book_id); $$;
REVOKE ALL ON FUNCTION public.add_book_to_reading_list(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.add_book_to_reading_list(uuid,uuid) TO authenticated;

-- AUD-09: owner-only invitation lifecycle. Pending invites never grant membership.
CREATE OR REPLACE FUNCTION private.invite_user_to_club(p_club uuid,p_invited_user uuid,p_expires_at timestamptz)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (SELECT 1 FROM public.user_clubs WHERE id=p_club AND owner_id=auth.uid() AND archived_at IS NULL) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  IF p_invited_user IS NULL OR p_expires_at <= now() THEN RAISE EXCEPTION 'invalid_invitation' USING ERRCODE='23514'; END IF;
  INSERT INTO public.user_club_invitations(club_id,invited_user_id,invited_by,expires_at)
  VALUES(p_club,p_invited_user,auth.uid(),p_expires_at)
  ON CONFLICT (club_id,invited_user_id) WHERE accepted_at IS NULL AND revoked_at IS NULL
  DO UPDATE SET expires_at=EXCLUDED.expires_at, invited_by=EXCLUDED.invited_by
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
CREATE OR REPLACE FUNCTION public.invite_user_to_club(p_club uuid,p_invited_user uuid,p_expires_at timestamptz) RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $$ SELECT private.invite_user_to_club(p_club,p_invited_user,p_expires_at); $$;
REVOKE ALL ON FUNCTION public.invite_user_to_club(uuid,uuid,timestamptz) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.invite_user_to_club(uuid,uuid,timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION private.revoke_club_invitation(p_invitation uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  UPDATE public.user_club_invitations SET revoked_at=now() WHERE id=p_invitation AND invited_by=auth.uid() AND accepted_at IS NULL AND revoked_at IS NULL;
  RETURN FOUND;
END;
$$;
CREATE OR REPLACE FUNCTION public.revoke_club_invitation(p_invitation uuid) RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $$ SELECT private.revoke_club_invitation(p_invitation); $$;
REVOKE ALL ON FUNCTION public.revoke_club_invitation(uuid) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.revoke_club_invitation(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION private.accept_club_invitation(p_invitation uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_club uuid;
BEGIN
  SELECT club_id INTO v_club FROM public.user_club_invitations WHERE id=p_invitation AND invited_user_id=auth.uid() AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > now() FOR UPDATE;
  IF v_club IS NULL THEN RAISE EXCEPTION 'invitation_unavailable' USING ERRCODE='42501'; END IF;
  INSERT INTO public.user_club_members(club_id,user_id,role) VALUES(v_club,auth.uid(),'member') ON CONFLICT DO NOTHING;
  UPDATE public.user_club_invitations SET accepted_at=now() WHERE id=p_invitation;
  RETURN true;
END;
$$;
CREATE OR REPLACE FUNCTION public.accept_club_invitation(p_invitation uuid) RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $$ SELECT private.accept_club_invitation(p_invitation); $$;
REVOKE ALL ON FUNCTION public.accept_club_invitation(uuid) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.accept_club_invitation(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION private.remove_club_member(p_club uuid,p_member uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.user_clubs WHERE id=p_club AND owner_id=auth.uid()) OR p_member=auth.uid() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  DELETE FROM public.user_club_members WHERE club_id=p_club AND user_id=p_member AND role <> 'owner';
  RETURN FOUND;
END;
$$;
CREATE OR REPLACE FUNCTION public.remove_club_member(p_club uuid,p_member uuid) RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $$ SELECT private.remove_club_member(p_club,p_member); $$;
REVOKE ALL ON FUNCTION public.remove_club_member(uuid,uuid) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.remove_club_member(uuid,uuid) TO authenticated;

-- AUD-12: editorial references and explicit spoiler metadata.
ALTER TABLE public.quiz_questions ADD COLUMN IF NOT EXISTS chapter_reference text, ADD COLUMN IF NOT EXISTS spoiler_level integer NOT NULL DEFAULT 0;
DO $$ BEGIN ALTER TABLE public.quiz_questions ADD CONSTRAINT quiz_spoiler_level_valid CHECK (spoiler_level BETWEEN 0 AND 3); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- AUD-13: document the product unit rather than silently calling 28 days four weeks.
UPDATE public.achievements SET code='streak_28d', title='28 dias de leitura', description='Leia em 28 dias diferentes para desbloquear este marco.' WHERE code='streak_4w';

-- AUD-19: report queue and auditable moderation decisions.
CREATE TABLE IF NOT EXISTS public.content_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), reporter_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content_type text NOT NULL CHECK (content_type IN ('comment','timed_comment','journal','post')), content_id uuid NOT NULL,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 3 AND 500), status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','resolved','dismissed')),
  reviewed_by uuid REFERENCES public.profiles(id), reviewed_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS content_reports_queue_idx ON public.content_reports(status,created_at DESC);
ALTER TABLE public.content_reports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS content_reports_insert_own ON public.content_reports;
CREATE POLICY content_reports_insert_own ON public.content_reports FOR INSERT TO authenticated WITH CHECK (reporter_id=(select auth.uid()));
DROP POLICY IF EXISTS content_reports_admin_read ON public.content_reports;
CREATE POLICY content_reports_admin_read ON public.content_reports FOR SELECT TO authenticated USING ((select public.is_admin()));
DROP POLICY IF EXISTS content_reports_admin_update ON public.content_reports;
CREATE POLICY content_reports_admin_update ON public.content_reports FOR UPDATE TO authenticated USING ((select public.is_admin())) WITH CHECK ((select public.is_admin()));

CREATE TABLE IF NOT EXISTS public.editorial_audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), actor_id uuid NOT NULL REFERENCES public.profiles(id), entity_type text NOT NULL, entity_id uuid NOT NULL, action text NOT NULL, changes jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.editorial_audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS editorial_audit_admin_read ON public.editorial_audit_log;
CREATE POLICY editorial_audit_admin_read ON public.editorial_audit_log FOR SELECT TO authenticated USING ((select public.is_admin()));

CREATE OR REPLACE FUNCTION public.report_content(p_content_type text,p_content_id uuid,p_reason text) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_id uuid;
BEGIN
  IF auth.uid() IS NULL OR p_content_type NOT IN ('comment','timed_comment','journal','post') OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'invalid_report' USING ERRCODE='23514'; END IF;
  INSERT INTO public.content_reports(reporter_id,content_type,content_id,reason) VALUES(auth.uid(),p_content_type,p_content_id,btrim(p_reason)) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.report_content(text,uuid,text) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.report_content(text,uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.review_content_report(p_report uuid,p_status text) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NOT public.is_admin() OR p_status NOT IN ('resolved','dismissed') THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  UPDATE public.content_reports SET status=p_status,reviewed_by=auth.uid(),reviewed_at=now() WHERE id=p_report;
  RETURN FOUND;
END;
$$;
REVOKE ALL ON FUNCTION public.review_content_report(uuid,text) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.review_content_report(uuid,text) TO authenticated;

-- AUD-20: presence is proof-backed and distinct from RSVP.
DO $$ BEGIN ALTER TYPE public.xp_source ADD VALUE IF NOT EXISTS 'meeting_attendance'; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
CREATE OR REPLACE FUNCTION public.confirm_meeting_attendance(p_user uuid,p_meeting uuid,p_proof_type text) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NOT public.is_admin() OR p_proof_type NOT IN ('moderator','replay_confirmation') THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  INSERT INTO public.meeting_attendance(user_id,meeting_id,proof_type) VALUES(p_user,p_meeting,p_proof_type) ON CONFLICT(user_id,meeting_id) DO UPDATE SET proof_type=EXCLUDED.proof_type,confirmed_at=now();
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.confirm_meeting_attendance(uuid,uuid,text) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.confirm_meeting_attendance(uuid,uuid,text) TO authenticated;

-- Atomic removal for owners and collaborators.
CREATE OR REPLACE FUNCTION public.remove_reading_list_item(p_list_id uuid,p_item_id uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT private.can_edit_reading_list(p_list_id) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  DELETE FROM public.reading_list_items WHERE id=p_item_id AND list_id=p_list_id;
  RETURN FOUND;
END;
$$;
REVOKE ALL ON FUNCTION public.remove_reading_list_item(uuid,uuid) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.remove_reading_list_item(uuid,uuid) TO authenticated;
