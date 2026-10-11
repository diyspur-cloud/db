-- Replay-safe reconciliation for production schema drift discovered 2026-10-11.
-- Consolidates audited source migrations 20261011130000 and 20261011170000.
-- Preserves the production owner-only milestone guard and restricts the public
-- book-completion RPC to its owner (or trusted service_role). No row deletion.

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
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$ SELECT CASE WHEN (SELECT auth.uid()) IS NULL OR p_user = (SELECT auth.uid()) THEN private.is_book_complete(p_user, p_book_id) ELSE false END; $$;
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
DROP POLICY IF EXISTS user_challenge_prompt_progress_owner ON public.user_challenge_prompt_progress;
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
  SELECT m.id, CASE WHEN m.chapter_id IS NOT NULL THEN EXISTS (SELECT 1 FROM public.user_progress up WHERE up.user_id=p_user AND up.chapter_id=m.chapter_id AND up.status='read'::public.shelf_status) WHEN m.chapter_from IS NOT NULL AND m.chapter_to IS NOT NULL THEN (SELECT COUNT(*) FROM public.chapters c WHERE c.season_id=m.season_id AND c.number BETWEEN m.chapter_from AND m.chapter_to) > 0 AND (SELECT COUNT(*) FROM public.chapters c WHERE c.season_id=m.season_id AND c.number BETWEEN m.chapter_from AND m.chapter_to) <= (SELECT COUNT(*) FROM public.user_progress up JOIN public.chapters c ON c.id=up.chapter_id WHERE up.user_id=p_user AND up.status='read'::public.shelf_status AND c.season_id=m.season_id AND c.number BETWEEN m.chapter_from AND m.chapter_to) WHEN m.page_to IS NOT NULL THEN EXISTS (SELECT 1 FROM public.reading_journal_entries e WHERE e.user_id=p_user AND e.book_id=m.book_id AND e.page_to >= m.page_to) WHEN m.percent_to IS NOT NULL THEN EXISTS (SELECT 1 FROM public.user_progress up JOIN public.chapters c ON c.id=up.chapter_id JOIN public.seasons s ON s.id=c.season_id WHERE up.user_id=p_user AND s.book_id=m.book_id AND up.percent >= m.percent_to) ELSE false END FROM public.milestones m WHERE m.season_id=p_season_id AND p_user = (SELECT auth.uid()) ORDER BY m.position;
$$;
GRANT EXECUTE ON FUNCTION public.get_user_milestone_status(uuid, uuid) TO authenticated;

CREATE TABLE IF NOT EXISTS public.meeting_attendance (user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE, meeting_id uuid NOT NULL REFERENCES public.meetings(id) ON DELETE CASCADE, confirmed_at timestamptz NOT NULL DEFAULT now(), proof_type text, PRIMARY KEY(user_id,meeting_id));
CREATE INDEX IF NOT EXISTS meeting_attendance_meeting_idx ON public.meeting_attendance(meeting_id);

-- Reconciliation layer B01/B02/B03/B04/B05/B06/B15/B17/B19
-- 20261011170000_audit_production_reconciliation.sql
-- Resolves audit findings: B01, B02, B03, B04, B05, B06, B15, B17, B19.
-- Preserves schema immutability by creating an additive incremental migration.

-- =====================================================================
-- B01 & B08: Reconciliar contrato e índices do diário de leitura
-- =====================================================================
ALTER TABLE public.reading_journal_entries
  ADD COLUMN IF NOT EXISTS archived_at timestamptz;

CREATE INDEX IF NOT EXISTS journal_owner_date_id_active_idx
  ON public.reading_journal_entries (user_id, entry_date DESC, id DESC)
  WHERE archived_at IS NULL;

-- Assegurar que leituras públicas/amigos/clube não exibam itens arquivados,
-- enquanto o dono pode ler ativos e arquivados explicitamente.
DROP POLICY IF EXISTS "journal_read_own" ON public.reading_journal_entries;
CREATE POLICY "journal_read_own" ON public.reading_journal_entries FOR SELECT
  USING (
    user_id = (SELECT auth.uid())
    OR (
      archived_at IS NULL
      AND (
        visibility = 'public'
        OR (visibility = 'friends' AND EXISTS (
             SELECT 1 FROM public.follows f
              WHERE f.follower_id = (SELECT auth.uid())
                AND f.followed_id = reading_journal_entries.user_id
                AND f.status = 'accepted'))
        OR (visibility = 'club' AND EXISTS (
             SELECT 1 FROM public.user_club_members m1
             JOIN public.user_club_members m2 ON m1.club_id = m2.club_id
             WHERE m1.user_id = (SELECT auth.uid())
               AND m2.user_id = reading_journal_entries.user_id))
      )
    )
  );

-- =====================================================================
-- B02, B03, B04: Autorização, spoiler e moderação de comentários temporizados
-- =====================================================================
ALTER TABLE public.video_timed_comments
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

CREATE OR REPLACE FUNCTION public.get_visible_video_timed_comments(
  p_chapter uuid,
  p_limit integer DEFAULT 100
)
RETURNS TABLE (
  id uuid,
  chapter_id uuid,
  video_sec integer,
  content text,
  is_spoiler boolean,
  is_locked boolean,
  created_at timestamptz
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT
    c.id,
    c.chapter_id,
    c.video_sec,
    CASE
      WHEN c.is_spoiler AND COALESCE(p.percent, 0) < c.min_percent
      THEN NULL::text
      ELSE c.content
    END AS content,
    c.is_spoiler,
    (c.is_spoiler AND COALESCE(p.percent, 0) < c.min_percent) AS is_locked,
    c.created_at
  FROM public.video_timed_comments c
  LEFT JOIN public.user_progress p
    ON p.chapter_id = c.chapter_id
   AND p.user_id = (SELECT auth.uid())
  WHERE c.chapter_id = p_chapter
    AND c.deleted_at IS NULL
    AND ((SELECT public.is_admin()) OR private.can_view_chapter(p_chapter))
  ORDER BY c.video_sec, c.created_at, c.id
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 100);
$$;

REVOKE ALL ON FUNCTION public.get_visible_video_timed_comments(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_visible_video_timed_comments(uuid, integer) TO anon, authenticated;

-- Revogar SELECT direto de content para forçar leitura através da RPC com máscara de spoiler
REVOKE SELECT ON public.video_timed_comments FROM PUBLIC, anon, authenticated;
REVOKE SELECT (content) ON public.video_timed_comments FROM PUBLIC, anon, authenticated;
GRANT SELECT (id, chapter_id, user_id, video_sec, created_at, is_spoiler, min_percent, deleted_at)
  ON public.video_timed_comments TO anon, authenticated;

-- Atualizar view de estatísticas de vídeo excluindo comentários deletados
CREATE OR REPLACE VIEW public.v_video_timed_comment_stats WITH (security_invoker = true) AS
SELECT
  vtc.chapter_id,
  vtc.video_sec,
  count(DISTINCT vtc.user_id) AS distinct_commenters,
  count(*) AS comment_count,
  max(vtc.created_at) AS last_comment_at
FROM public.video_timed_comments vtc
WHERE vtc.deleted_at IS NULL
GROUP BY vtc.chapter_id, vtc.video_sec;

-- B04: Moderação de conteúdo corrigida (sem colunas inexistentes)
CREATE OR REPLACE FUNCTION public.hide_reported_content(p_report uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  r record;
BEGIN
  IF NOT (SELECT public.is_admin()) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT content_type, content_id INTO r
  FROM public.content_reports
  WHERE id = p_report
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF r.content_type = 'comment' THEN
    UPDATE public.comments SET deleted_at = now() WHERE id = r.content_id;
  ELSIF r.content_type = 'timed_comment' THEN
    UPDATE public.video_timed_comments SET deleted_at = now() WHERE id = r.content_id;
  ELSIF r.content_type = 'post' THEN
    UPDATE public.feed_posts SET deleted_at = now() WHERE id = r.content_id;
  ELSIF r.content_type = 'journal' THEN
    UPDATE public.reading_journal_entries SET archived_at = now() WHERE id = r.content_id;
  ELSE
    RAISE EXCEPTION 'invalid_content_type' USING ERRCODE = '22023';
  END IF;

  UPDATE public.content_reports
     SET status = 'resolved',
         reviewed_by = (SELECT auth.uid()),
         reviewed_at = now()
   WHERE id = p_report;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.hide_reported_content(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.hide_reported_content(uuid) TO authenticated;

-- =====================================================================
-- B05: Proteger integridade de resultados derivados em user_challenges
-- =====================================================================
REVOKE INSERT, UPDATE ON public.user_challenges FROM PUBLIC, anon, authenticated;
GRANT INSERT (user_id, challenge_id) ON public.user_challenges TO authenticated;
GRANT DELETE ON public.user_challenges TO authenticated;

DROP POLICY IF EXISTS user_challenges_owner_write ON public.user_challenges;
DROP POLICY IF EXISTS user_challenges_owner_insert ON public.user_challenges;
DROP POLICY IF EXISTS user_challenges_owner_delete ON public.user_challenges;
CREATE POLICY user_challenges_owner_insert ON public.user_challenges
  FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY user_challenges_owner_delete ON public.user_challenges
  FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- =====================================================================
-- B06: Estado explícito de rascunho de capítulo (is_draft)
-- =====================================================================
ALTER TABLE public.chapters
  ADD COLUMN IF NOT EXISTS is_draft boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION private.can_view_chapter(p_chapter uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.chapters c
      JOIN public.seasons s ON s.id = c.season_id
     WHERE c.id = p_chapter
       AND NOT COALESCE(c.is_draft, false)
       AND s.status IN ('active', 'finished')
       AND (c.published_at IS NULL OR c.published_at <= statement_timestamp())
       AND (
         c.number = 1 OR EXISTS (
           SELECT 1 FROM public.chapters previous
           JOIN public.quiz_attempts attempt ON attempt.chapter_id = previous.id
            AND attempt.user_id = (SELECT auth.uid())
          WHERE previous.season_id = c.season_id
            AND previous.number = c.number - 1
       )
    )
  );
$$;

CREATE OR REPLACE FUNCTION public.get_season_chapter_access(p_season uuid)
RETURNS TABLE (
  chapter_id uuid,
  chapter_number integer,
  chapter_title text,
  reading_range text,
  published_at timestamptz,
  can_open boolean,
  requires_quiz boolean
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT
    c.id,
    c.number,
    c.title,
    c.reading_range,
    c.published_at,
    private.can_view_chapter(c.id),
    c.number > 1
  FROM public.chapters c
  JOIN public.seasons s ON s.id = c.season_id
  WHERE c.season_id = p_season
    AND NOT COALESCE(c.is_draft, false)
    AND s.status IN ('active', 'finished')
    AND (c.published_at IS NULL OR c.published_at <= statement_timestamp())
  ORDER BY c.number;
$$;

REVOKE ALL ON FUNCTION public.get_season_chapter_access(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_season_chapter_access(uuid) TO anon, authenticated;

-- =====================================================================
-- B15: Configuração de livro e temporada pelo responsável do clube
-- =====================================================================
CREATE OR REPLACE FUNCTION private.update_user_club(
  p_club uuid,
  p_version bigint,
  p_name text,
  p_description text,
  p_private boolean,
  p_season_id uuid DEFAULT NULL
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $fn$
DECLARE
  v_version bigint;
  v_book uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  SELECT version INTO v_version
    FROM public.user_clubs
   WHERE id = p_club
     AND owner_id = auth.uid()
     AND archived_at IS NULL
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  IF v_version <> p_version THEN
    RAISE EXCEPTION 'conflict' USING ERRCODE = '40001';
  END IF;

  IF length(btrim(coalesce(p_name, ''))) NOT BETWEEN 3 AND 80
     OR length(coalesce(p_description, '')) > 2000
     OR p_private IS NULL THEN
    RAISE EXCEPTION 'invalid_club' USING ERRCODE = '23514';
  END IF;

  IF p_season_id IS NOT NULL THEN
    SELECT book_id INTO v_book FROM public.seasons WHERE id = p_season_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'season_not_found' USING ERRCODE = '23503';
    END IF;
  END IF;

  UPDATE public.user_clubs
     SET name = btrim(p_name),
         description = nullif(btrim(p_description), ''),
         is_private = p_private,
         current_season_id = p_season_id,
         current_book_id = v_book,
         version = version + 1
   WHERE id = p_club
  RETURNING version INTO v_version;

  RETURN v_version;
END;
$fn$;

REVOKE ALL ON FUNCTION private.update_user_club(uuid, bigint, text, text, boolean, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.update_user_club(uuid, bigint, text, text, boolean, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_user_club(
  p_club uuid,
  p_version bigint,
  p_name text,
  p_description text,
  p_private boolean,
  p_season_id uuid DEFAULT NULL
) RETURNS bigint LANGUAGE sql SECURITY INVOKER SET search_path = '' AS $fn$
  SELECT private.update_user_club(p_club, p_version, p_name, p_description, p_private, p_season_id);
$fn$;

REVOKE ALL ON FUNCTION public.update_user_club(uuid, bigint, text, text, boolean, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_user_club(uuid, bigint, text, text, boolean, uuid) TO authenticated;

-- =====================================================================
-- B17: Tabela de Presença em Encontros (meeting_attendance)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.meeting_attendance (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  meeting_id uuid NOT NULL REFERENCES public.meetings(id) ON DELETE CASCADE,
  confirmed_at timestamptz NOT NULL DEFAULT now(),
  proof_type text,
  PRIMARY KEY (user_id, meeting_id)
);

ALTER TABLE public.meeting_attendance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS meeting_attendance_read_own ON public.meeting_attendance;
CREATE POLICY meeting_attendance_read_own ON public.meeting_attendance
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()) OR (SELECT public.is_admin()));

DROP POLICY IF EXISTS meeting_attendance_admin_write ON public.meeting_attendance;
CREATE POLICY meeting_attendance_admin_write ON public.meeting_attendance
  FOR ALL TO authenticated
  USING ((SELECT public.is_admin()))
  WITH CHECK ((SELECT public.is_admin()));

CREATE INDEX IF NOT EXISTS meeting_attendance_meeting_idx
  ON public.meeting_attendance(meeting_id);

GRANT SELECT ON public.meeting_attendance TO authenticated;

-- =====================================================================
-- B19: Índices cobridores para chaves estrangeiras sem cobertura
-- =====================================================================
CREATE INDEX IF NOT EXISTS content_reports_reporter_idx
  ON public.content_reports(reporter_id);

CREATE INDEX IF NOT EXISTS content_reports_reviewer_idx
  ON public.content_reports(reviewed_by);

CREATE INDEX IF NOT EXISTS editorial_audit_actor_idx
  ON public.editorial_audit_log(actor_id);

CREATE INDEX IF NOT EXISTS journal_shared_club_idx
  ON public.reading_journal_entries(shared_club_id);
