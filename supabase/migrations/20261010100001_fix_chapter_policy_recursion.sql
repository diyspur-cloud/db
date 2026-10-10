-- A policy chapters_read não pode consultar public.chapters diretamente:
-- isso faz o PostgreSQL reavaliar a própria policy e gerar 42P17.
-- O helper é somente leitura, deriva a identidade de auth.uid() e roda com
-- row_security desligado dentro do contexto SECURITY DEFINER.
CREATE OR REPLACE FUNCTION private.can_view_chapter(p_chapter uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' SET row_security = off
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.chapters AS current_chapter
      JOIN public.seasons AS season ON season.id = current_chapter.season_id
     WHERE current_chapter.id = p_chapter
       AND (current_chapter.published_at IS NULL OR current_chapter.published_at <= statement_timestamp())
       AND season.status IN ('active', 'finished')
       AND (
         current_chapter.number = 1
         OR EXISTS (
           SELECT 1
             FROM public.chapters AS previous_chapter
             JOIN public.quiz_attempts AS attempt
               ON attempt.chapter_id = previous_chapter.id
              AND attempt.user_id = (SELECT auth.uid())
            WHERE previous_chapter.season_id = current_chapter.season_id
              AND previous_chapter.number = current_chapter.number - 1
         )
       )
  );
$$;
REVOKE ALL ON FUNCTION private.can_view_chapter(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.can_view_chapter(uuid) TO anon, authenticated;

DROP POLICY IF EXISTS chapters_read ON public.chapters;
CREATE POLICY chapters_read ON public.chapters
  FOR SELECT TO anon, authenticated
  USING ((SELECT public.is_admin()) OR private.can_view_chapter(id));

DROP POLICY IF EXISTS quiz_q_read_auth ON public.quiz_questions;
CREATE POLICY quiz_q_read_auth ON public.quiz_questions
  FOR SELECT TO authenticated
  USING ((SELECT public.is_admin()) OR private.can_view_chapter(chapter_id));

DROP POLICY IF EXISTS meetings_read ON public.meetings;
CREATE POLICY meetings_read ON public.meetings
  FOR SELECT TO anon, authenticated
  USING ((SELECT public.is_admin()) OR private.can_view_chapter(chapter_id));

DROP POLICY IF EXISTS prompts_read ON public.host_prompts;
CREATE POLICY prompts_read ON public.host_prompts
  FOR SELECT TO anon, authenticated
  USING ((SELECT public.is_admin()) OR private.can_view_chapter(chapter_id));

DROP POLICY IF EXISTS vtc_read ON public.video_timed_comments;
CREATE POLICY vtc_read ON public.video_timed_comments
  FOR SELECT TO anon, authenticated
  USING ((SELECT public.is_admin()) OR private.can_view_chapter(chapter_id));

CREATE OR REPLACE FUNCTION private.get_visible_comments()
RETURNS TABLE (
  id uuid,
  chapter_id uuid,
  user_id uuid,
  parent_id uuid,
  created_at timestamptz,
  likes_count integer,
  replies_count integer,
  is_spoiler boolean,
  content text,
  is_locked boolean
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' SET row_security = off
AS $$
  SELECT c.id,
         c.chapter_id,
         c.user_id,
         c.parent_id,
         c.created_at,
         c.likes_count,
         c.replies_count,
         c.is_spoiler,
         CASE WHEN c.is_spoiler AND coalesce(up.percent, 0) < coalesce(c.min_percent, 100)
              THEN NULL::text ELSE c.content END,
         (c.is_spoiler AND coalesce(up.percent, 0) < coalesce(c.min_percent, 100))
    FROM public.comments AS c
    LEFT JOIN public.user_progress AS up
      ON up.chapter_id = c.chapter_id
     AND up.user_id = (SELECT auth.uid())
   WHERE c.deleted_at IS NULL
     AND private.can_view_chapter(c.chapter_id);
$$;
REVOKE ALL ON FUNCTION private.get_visible_comments() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.get_visible_comments() TO anon, authenticated;

COMMENT ON POLICY chapters_read ON public.chapters IS
  'Publication and previous-quiz access are evaluated by private.can_view_chapter to avoid recursive RLS evaluation.';
