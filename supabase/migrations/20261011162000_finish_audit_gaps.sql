-- Final audit gap closure. Applied as a new incremental migration.

ALTER TABLE public.reading_list_items ADD COLUMN IF NOT EXISTS archived_at timestamptz;
DROP INDEX IF EXISTS public.reading_list_book_unique;
CREATE UNIQUE INDEX IF NOT EXISTS reading_list_book_active_unique ON public.reading_list_items(list_id, book_id) WHERE book_id IS NOT NULL AND archived_at IS NULL;
CREATE INDEX IF NOT EXISTS reading_list_items_active_idx ON public.reading_list_items(list_id, position) WHERE archived_at IS NULL;

CREATE OR REPLACE FUNCTION private.milestone_is_complete(p_user uuid,p_milestone uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE m record; total_count int; read_count int;
BEGIN
  SELECT * INTO m FROM public.milestones WHERE id=p_milestone;
  IF NOT FOUND THEN RETURN false; END IF;
  IF m.chapter_id IS NOT NULL THEN RETURN EXISTS (SELECT 1 FROM public.user_progress WHERE user_id=p_user AND chapter_id=m.chapter_id AND status='read'::public.shelf_status); END IF;
  IF m.chapter_from IS NOT NULL AND m.chapter_to IS NOT NULL THEN
    SELECT COUNT(*) INTO total_count FROM public.chapters WHERE season_id=m.season_id AND number BETWEEN m.chapter_from AND m.chapter_to;
    SELECT COUNT(*) INTO read_count FROM public.user_progress up JOIN public.chapters c ON c.id=up.chapter_id WHERE up.user_id=p_user AND up.status='read'::public.shelf_status AND c.season_id=m.season_id AND c.number BETWEEN m.chapter_from AND m.chapter_to;
    RETURN total_count > 0 AND read_count >= total_count;
  END IF;
  IF m.page_to IS NOT NULL THEN RETURN EXISTS (SELECT 1 FROM public.reading_journal_entries WHERE user_id=p_user AND book_id=m.book_id AND page_to >= m.page_to); END IF;
  IF m.percent_to IS NOT NULL THEN RETURN EXISTS (SELECT 1 FROM public.user_progress up JOIN public.chapters c ON c.id=up.chapter_id JOIN public.seasons s ON s.id=c.season_id WHERE up.user_id=p_user AND s.book_id=m.book_id AND up.percent >= m.percent_to); END IF;
  RETURN false;
END;
$$;
REVOKE ALL ON FUNCTION private.milestone_is_complete(uuid,uuid) FROM PUBLIC,anon,authenticated; GRANT EXECUTE ON FUNCTION private.milestone_is_complete(uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION private.sync_user_milestone_progress(p_user uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE m record; done boolean;
BEGIN
  FOR m IN SELECT ms.id FROM public.milestones ms JOIN public.seasons s ON s.id=ms.season_id WHERE s.status IN ('active','finished') LOOP
    done := private.milestone_is_complete(p_user,m.id);
    INSERT INTO public.user_milestone_progress(user_id,milestone_id,completed_at,xp_awarded) VALUES(p_user,m.id,CASE WHEN done THEN now() ELSE NULL END,false)
    ON CONFLICT(user_id,milestone_id) DO UPDATE SET completed_at=CASE WHEN EXCLUDED.completed_at IS NOT NULL AND public.user_milestone_progress.completed_at IS NULL THEN EXCLUDED.completed_at ELSE public.user_milestone_progress.completed_at END;
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION private.sync_user_milestone_progress(uuid) FROM PUBLIC,anon,authenticated; GRANT EXECUTE ON FUNCTION private.sync_user_milestone_progress(uuid) TO service_role;
DO $$ DECLARE u uuid; BEGIN FOR u IN SELECT DISTINCT user_id FROM public.user_progress UNION SELECT DISTINCT user_id FROM public.reading_journal_entries LOOP PERFORM private.sync_user_milestone_progress(u); END LOOP; END $$;

CREATE OR REPLACE FUNCTION public.get_user_milestone_status(p_user uuid,p_season_id uuid) RETURNS TABLE(milestone_id uuid,completed boolean) LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$ SELECT m.id, private.milestone_is_complete(p_user,m.id) FROM public.milestones m WHERE m.season_id=p_season_id ORDER BY m.position $$;
REVOKE ALL ON FUNCTION public.get_user_milestone_status(uuid,uuid) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.get_user_milestone_status(uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION private.add_book_to_reading_list(p_list_id uuid,p_book_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_user uuid:=auth.uid(); v_position int;
BEGIN
  IF v_user IS NULL OR NOT EXISTS (SELECT 1 FROM public.reading_lists l WHERE l.id=p_list_id AND private.can_edit_reading_list(l.id)) THEN RETURN jsonb_build_object('ok',false,'message','Você não pode alterar esta lista.'); END IF;
  PERFORM 1 FROM public.reading_lists WHERE id=p_list_id FOR UPDATE;
  IF EXISTS (SELECT 1 FROM public.reading_list_items WHERE list_id=p_list_id AND book_id=p_book_id AND archived_at IS NULL) THEN RETURN jsonb_build_object('ok',true,'message','Este livro já está na lista.'); END IF;
  SELECT COALESCE(MAX(position),-1)+1 INTO v_position FROM public.reading_list_items WHERE list_id=p_list_id AND archived_at IS NULL;
  INSERT INTO public.reading_list_items(list_id,book_id,kind,added_by,position) VALUES(p_list_id,p_book_id,'book'::public.reading_list_item_kind,v_user,v_position);
  RETURN jsonb_build_object('ok',true,'message','Livro adicionado à lista.');
END; $$;

CREATE OR REPLACE FUNCTION public.remove_reading_list_item(p_list_id uuid,p_item_id uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT private.can_edit_reading_list(p_list_id) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  UPDATE public.reading_list_items SET archived_at=now() WHERE id=p_item_id AND list_id=p_list_id AND archived_at IS NULL; RETURN FOUND;
END; $$;
CREATE OR REPLACE FUNCTION public.restore_reading_list_item(p_list_id uuid,p_item_id uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT private.can_edit_reading_list(p_list_id) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  UPDATE public.reading_list_items SET archived_at=NULL WHERE id=p_item_id AND list_id=p_list_id AND archived_at IS NOT NULL; RETURN FOUND;
END; $$;
REVOKE ALL ON FUNCTION public.restore_reading_list_item(uuid,uuid) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.restore_reading_list_item(uuid,uuid) TO authenticated;

UPDATE public.quiz_questions q SET chapter_reference=COALESCE(q.chapter_reference,c.reading_range) FROM public.chapters c WHERE c.id=q.chapter_id AND q.chapter_reference IS NULL;
CREATE INDEX IF NOT EXISTS club_invites_invited_user_idx ON public.user_club_invitations(invited_user_id,created_at DESC);
CREATE INDEX IF NOT EXISTS club_invites_invited_by_idx ON public.user_club_invitations(invited_by,created_at DESC);

CREATE OR REPLACE FUNCTION public.hide_reported_content(p_report uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE r record;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  SELECT content_type,content_id INTO r FROM public.content_reports WHERE id=p_report FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF r.content_type='comment' THEN UPDATE public.comments SET deleted_at=now() WHERE id=r.content_id;
  ELSIF r.content_type='timed_comment' THEN UPDATE public.video_timed_comments SET is_locked=true WHERE id=r.content_id;
  ELSIF r.content_type='post' THEN UPDATE public.feed_posts SET deleted_at=now() WHERE id=r.content_id;
  ELSIF r.content_type='journal' THEN UPDATE public.reading_journal_entries SET archived_at=now() WHERE id=r.content_id;
  END IF;
  UPDATE public.content_reports SET status='resolved',reviewed_by=auth.uid(),reviewed_at=now() WHERE id=p_report;
  RETURN true;
END; $$;
REVOKE ALL ON FUNCTION public.hide_reported_content(uuid) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.hide_reported_content(uuid) TO authenticated;
