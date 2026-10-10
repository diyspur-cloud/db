-- DIYSPUR: invariantes de escrita e spoiler no servidor.
-- Migration incremental: não editar migrations já aplicadas.

-- 1) O acesso de capítulo deve ser igual no RPC público e nas escritas diretas.
CREATE OR REPLACE FUNCTION private.can_view_chapter(p_chapter uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.chapters c
      JOIN public.seasons s ON s.id = c.season_id
     WHERE c.id = p_chapter
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

-- 2) Disponibilidade também é exigida pela Data API; políticas permissivas antigas
-- são removidas, pois policies permissivas combinam por OR.
DROP POLICY IF EXISTS progress_self_write ON public.user_progress;
DROP POLICY IF EXISTS "progress_self_write" ON public.user_progress;
CREATE POLICY progress_self_insert ON public.user_progress
  FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()) AND private.can_view_chapter(chapter_id));
CREATE POLICY progress_self_update ON public.user_progress
  FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()) AND private.can_view_chapter(chapter_id));
CREATE POLICY progress_self_delete ON public.user_progress
  FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS comments_insert_own ON public.comments;
DROP POLICY IF EXISTS comments_insert_auth ON public.comments;
CREATE POLICY comments_insert_accessible ON public.comments
  FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()) AND private.can_view_chapter(chapter_id));

DROP POLICY IF EXISTS vtc_own ON public.video_timed_comments;
CREATE POLICY vtc_insert_accessible ON public.video_timed_comments
  FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()) AND private.can_view_chapter(chapter_id));
CREATE POLICY vtc_update_accessible ON public.video_timed_comments
  FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()) AND private.can_view_chapter(chapter_id))
  WITH CHECK (user_id = (SELECT auth.uid()) AND private.can_view_chapter(chapter_id));
CREATE POLICY vtc_delete_own ON public.video_timed_comments
  FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));

-- 3) Soft delete não deve depender de retornar a linha que deixou de ser visível.
CREATE OR REPLACE FUNCTION public.remove_own_chapter_comment(p_comment_id uuid, p_chapter_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN false; END IF;
  UPDATE public.comments
     SET deleted_at = COALESCE(deleted_at, statement_timestamp())
   WHERE id = p_comment_id AND chapter_id = p_chapter_id AND user_id = v_uid;
  RETURN FOUND;
END;
$$;
REVOKE ALL ON FUNCTION public.remove_own_chapter_comment(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_own_chapter_comment(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_own_chapter_comment_for_edit(p_comment_id uuid, p_chapter_id uuid)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT content FROM public.comments
   WHERE id = p_comment_id AND chapter_id = p_chapter_id
     AND user_id = (SELECT auth.uid()) AND deleted_at IS NULL;
$$;
REVOKE ALL ON FUNCTION public.get_own_chapter_comment_for_edit(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_own_chapter_comment_for_edit(uuid, uuid) TO authenticated;

-- 4) Uma conclusão não pode ser reaberta por um upsert comum.
CREATE OR REPLACE FUNCTION private.prevent_progress_regression()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF OLD.status = 'read' AND NEW.status <> 'read' THEN
    RAISE EXCEPTION 'completed_progress_cannot_regress' USING ERRCODE = '22023';
  END IF;
  IF OLD.status = 'read' AND NEW.percent < 100 THEN
    RAISE EXCEPTION 'completed_progress_cannot_regress' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_prevent_progress_regression ON public.user_progress;
CREATE TRIGGER trg_prevent_progress_regression
  BEFORE UPDATE ON public.user_progress
  FOR EACH ROW EXECUTE FUNCTION private.prevent_progress_regression();

-- 5) Spoiler do comentário no vídeo é uma regra de dados, não de CSS.
ALTER TABLE public.video_timed_comments
  ADD COLUMN IF NOT EXISTS is_spoiler boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS min_percent numeric(5,2) NOT NULL DEFAULT 0;
UPDATE public.video_timed_comments SET min_percent = 100 WHERE is_spoiler = true;
ALTER TABLE public.video_timed_comments DROP CONSTRAINT IF EXISTS video_timed_comments_min_percent_check;
ALTER TABLE public.video_timed_comments ADD CONSTRAINT video_timed_comments_min_percent_check CHECK (min_percent BETWEEN 0 AND 100);

CREATE OR REPLACE FUNCTION public.get_visible_video_timed_comments(p_chapter uuid, p_limit integer DEFAULT 100)
RETURNS TABLE (id uuid, chapter_id uuid, video_sec integer, content text, is_spoiler boolean, is_locked boolean, created_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT c.id, c.chapter_id, c.video_sec,
    CASE WHEN c.is_spoiler AND COALESCE(p.percent, 0) < c.min_percent THEN NULL::text ELSE c.content END,
    c.is_spoiler,
    (c.is_spoiler AND COALESCE(p.percent, 0) < c.min_percent),
    c.created_at
  FROM public.video_timed_comments c
  LEFT JOIN public.user_progress p ON p.chapter_id = c.chapter_id AND p.user_id = (SELECT auth.uid())
  WHERE c.chapter_id = p_chapter
  ORDER BY c.video_sec, c.created_at
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 100);
$$;
REVOKE ALL ON FUNCTION public.get_visible_video_timed_comments(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_visible_video_timed_comments(uuid, integer) TO anon, authenticated;

-- 6) RPC de metadados nunca revela temporadas draft/arquivadas.
CREATE OR REPLACE FUNCTION public.get_season_chapter_access(p_season uuid)
RETURNS TABLE (chapter_id uuid, chapter_number integer, chapter_title text, reading_range text, published_at timestamptz, can_open boolean, requires_quiz boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT c.id, c.number, c.title, c.reading_range, c.published_at,
    private.can_view_chapter(c.id), c.number > 1
  FROM public.chapters c
  JOIN public.seasons s ON s.id = c.season_id
  WHERE c.season_id = p_season
    AND s.status IN ('active', 'finished')
    AND (c.published_at IS NULL OR c.published_at <= statement_timestamp())
  ORDER BY c.number;
$$;
REVOKE ALL ON FUNCTION public.get_season_chapter_access(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_season_chapter_access(uuid) TO anon, authenticated;

-- 7) Remover DML direto de clubes; mutations passam pelas RPCs com versão/estado.
REVOKE INSERT, UPDATE, DELETE ON public.user_clubs FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.user_club_members FROM anon, authenticated;
