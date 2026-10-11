-- Incremental audit fixes. Existing migrations remain immutable.

ALTER TABLE public.reading_journal_entries ADD COLUMN IF NOT EXISTS archived_at timestamptz;
CREATE INDEX IF NOT EXISTS reading_journal_entries_active_idx ON public.reading_journal_entries(user_id, entry_date DESC) WHERE archived_at IS NULL;

CREATE OR REPLACE FUNCTION private.is_book_complete(p_user uuid, p_book_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_total int; v_read int;
BEGIN
  SELECT COUNT(*) INTO v_total FROM public.chapters c JOIN public.seasons s ON s.id = c.season_id WHERE s.book_id = p_book_id;
  SELECT COUNT(DISTINCT c.id) INTO v_read FROM public.user_progress up JOIN public.chapters c ON c.id = up.chapter_id JOIN public.seasons s ON s.id = c.season_id WHERE up.user_id = p_user AND s.book_id = p_book_id AND up.status = 'read'::public.shelf_status;
  RETURN v_total > 0 AND v_read >= v_total;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_book_complete(p_user uuid, p_book_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$ SELECT private.is_book_complete(p_user, p_book_id); $$;
REVOKE ALL ON FUNCTION public.is_book_complete(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_book_complete(uuid, uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION private.refresh_reading_goal_progress()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_user uuid := COALESCE(NEW.user_id, OLD.user_id); v_year int := EXTRACT(YEAR FROM CURRENT_DATE)::int; v_goal uuid; v_books int;
BEGIN
  SELECT id INTO v_goal FROM public.reading_goals WHERE user_id = v_user AND year = v_year;
  IF v_goal IS NULL THEN RETURN NULL; END IF;
  SELECT COUNT(*) INTO v_books FROM (SELECT DISTINCT s.book_id FROM public.user_progress up JOIN public.chapters c ON c.id=up.chapter_id JOIN public.seasons s ON s.id=c.season_id WHERE up.user_id=v_user AND up.status='read'::public.shelf_status AND up.finished_at >= make_date(v_year,1,1) AND private.is_book_complete(v_user,s.book_id)) books;
  INSERT INTO public.reading_goal_progress(goal_id,books_done,pages_done,minutes_done,updated_at)
  SELECT v_goal, v_books,
    (SELECT COALESCE(SUM(CASE WHEN page_from IS NOT NULL AND page_to IS NOT NULL AND page_to >= page_from THEN page_to-page_from+1 ELSE 0 END),0) FROM public.reading_journal_entries WHERE user_id=v_user AND entry_date >= make_date(v_year,1,1)),
    (SELECT COALESCE(SUM(minutes_read),0) FROM public.reading_journal_entries WHERE user_id=v_user AND entry_date >= make_date(v_year,1,1)), statement_timestamp()
  ON CONFLICT (goal_id) DO UPDATE SET books_done=EXCLUDED.books_done,pages_done=EXCLUDED.pages_done,minutes_done=EXCLUDED.minutes_done,updated_at=statement_timestamp();
  RETURN NULL;
END;
$$;

CREATE TABLE IF NOT EXISTS public.user_challenge_prompt_progress (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  prompt_id uuid NOT NULL REFERENCES public.challenge_prompts(id) ON DELETE CASCADE,
  completed_at timestamptz,
  PRIMARY KEY (user_id, prompt_id)
);
ALTER TABLE public.user_challenge_prompt_progress ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_challenge_prompt_progress_owner ON public.user_challenge_prompt_progress FOR ALL USING (user_id = (select auth.uid())) WITH CHECK (user_id = (select auth.uid()));

CREATE OR REPLACE FUNCTION private.recompute_challenge_progress(p_user uuid, p_challenge_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE total_count int; done_count int;
BEGIN
  SELECT COUNT(*) INTO total_count FROM public.challenge_prompts WHERE challenge_id=p_challenge_id;
  IF total_count=0 THEN RETURN; END IF;
  SELECT COUNT(*) INTO done_count FROM public.user_challenge_prompt_progress u JOIN public.challenge_prompts p ON p.id=u.prompt_id WHERE u.user_id=p_user AND p.challenge_id=p_challenge_id AND u.completed_at IS NOT NULL;
  UPDATE public.user_challenges SET progress=ROUND((done_count::numeric/total_count)*100)::int, completed_at=CASE WHEN done_count=total_count THEN COALESCE(completed_at,now()) ELSE NULL END WHERE user_id=p_user AND challenge_id=p_challenge_id;
END;
$$;

CREATE OR REPLACE FUNCTION private.sync_challenges_from_progress() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE prompt record; challenge_id uuid; user_id uuid := COALESCE(NEW.user_id, OLD.user_id);
BEGIN
  FOR prompt IN SELECT p.id,p.challenge_id FROM public.challenge_prompts p JOIN public.chapters c ON c.id=COALESCE(NEW.chapter_id,OLD.chapter_id) JOIN public.seasons s ON s.id=c.season_id WHERE p.book_id=s.book_id LOOP
    INSERT INTO public.user_challenge_prompt_progress(user_id,prompt_id,completed_at) VALUES(user_id,prompt.id,CASE WHEN TG_OP <> 'DELETE' AND NEW.status='read'::public.shelf_status THEN now() ELSE NULL END) ON CONFLICT(user_id,prompt_id) DO UPDATE SET completed_at=EXCLUDED.completed_at;
    challenge_id := prompt.challenge_id;
    PERFORM private.recompute_challenge_progress(user_id, challenge_id);
  END LOOP;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS sync_challenges_after_progress ON public.user_progress;
CREATE TRIGGER sync_challenges_after_progress AFTER INSERT OR UPDATE OR DELETE ON public.user_progress FOR EACH ROW EXECUTE FUNCTION private.sync_challenges_from_progress();

CREATE OR REPLACE FUNCTION public.get_user_milestone_status(p_user uuid, p_season_id uuid)
RETURNS TABLE(milestone_id uuid, completed boolean) LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT m.id, CASE WHEN m.chapter_id IS NOT NULL THEN EXISTS (SELECT 1 FROM public.user_progress up WHERE up.user_id=p_user AND up.chapter_id=m.chapter_id AND up.status='read'::public.shelf_status) WHEN m.chapter_from IS NOT NULL AND m.chapter_to IS NOT NULL THEN (SELECT COUNT(*) FROM public.chapters c WHERE c.season_id=m.season_id AND c.number BETWEEN m.chapter_from AND m.chapter_to) > 0 AND (SELECT COUNT(*) FROM public.chapters c WHERE c.season_id=m.season_id AND c.number BETWEEN m.chapter_from AND m.chapter_to) <= (SELECT COUNT(*) FROM public.user_progress up JOIN public.chapters c ON c.id=up.chapter_id WHERE up.user_id=p_user AND up.status='read'::public.shelf_status AND c.season_id=m.season_id AND c.number BETWEEN m.chapter_from AND m.chapter_to) WHEN m.page_to IS NOT NULL THEN EXISTS (SELECT 1 FROM public.reading_journal_entries e WHERE e.user_id=p_user AND e.book_id=m.book_id AND e.page_to >= m.page_to) WHEN m.percent_to IS NOT NULL THEN EXISTS (SELECT 1 FROM public.user_progress up JOIN public.chapters c ON c.id=up.chapter_id JOIN public.seasons s ON s.id=c.season_id WHERE up.user_id=p_user AND s.book_id=m.book_id AND up.percent >= m.percent_to) ELSE false END FROM public.milestones m WHERE m.season_id=p_season_id ORDER BY m.position;
$$;
GRANT EXECUTE ON FUNCTION public.get_user_milestone_status(uuid, uuid) TO authenticated;

CREATE TABLE IF NOT EXISTS public.meeting_attendance (user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE, meeting_id uuid NOT NULL REFERENCES public.meetings(id) ON DELETE CASCADE, confirmed_at timestamptz NOT NULL DEFAULT now(), proof_type text, PRIMARY KEY(user_id,meeting_id));
CREATE INDEX IF NOT EXISTS meeting_attendance_meeting_idx ON public.meeting_attendance(meeting_id);
