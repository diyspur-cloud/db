-- Reforça o contrato de publicação sem reescrever migrations históricas.
-- NULL em published_at é legado já publicado; timestamps futuros continuam ocultos.
-- A partir do capítulo 2, a leitura exige tentativa persistida do capítulo anterior.

DROP POLICY IF EXISTS seasons_read ON public.seasons;
CREATE POLICY seasons_read ON public.seasons
  FOR SELECT TO anon, authenticated
  USING (
    (SELECT public.is_admin())
    OR status IN ('active', 'finished')
  );

DROP POLICY IF EXISTS chapters_read ON public.chapters;
CREATE POLICY chapters_read ON public.chapters
  FOR SELECT TO anon, authenticated
  USING (
    (SELECT public.is_admin())
    OR (
      (published_at IS NULL OR published_at <= statement_timestamp())
      AND EXISTS (
        SELECT 1
          FROM public.seasons AS season
         WHERE season.id = chapters.season_id
           AND season.status IN ('active', 'finished')
      )
      AND (
        chapters.number = 1
        OR EXISTS (
          SELECT 1
            FROM public.chapters AS previous_chapter
            JOIN public.quiz_attempts AS attempt
              ON attempt.chapter_id = previous_chapter.id
             AND attempt.user_id = (SELECT auth.uid())
           WHERE previous_chapter.season_id = chapters.season_id
             AND previous_chapter.number = chapters.number - 1
        )
      )
    )
  );

DROP POLICY IF EXISTS quiz_q_read_auth ON public.quiz_questions;
CREATE POLICY quiz_q_read_auth ON public.quiz_questions
  FOR SELECT TO authenticated
  USING (
    (SELECT public.is_admin())
    OR EXISTS (
      SELECT 1
        FROM public.chapters AS chapter
        JOIN public.seasons AS season ON season.id = chapter.season_id
       WHERE chapter.id = quiz_questions.chapter_id
         AND (chapter.published_at IS NULL OR chapter.published_at <= statement_timestamp())
         AND season.status IN ('active', 'finished')
         AND (
           chapter.number = 1
           OR EXISTS (
             SELECT 1
               FROM public.chapters AS previous_chapter
               JOIN public.quiz_attempts AS attempt
                 ON attempt.chapter_id = previous_chapter.id
                AND attempt.user_id = (SELECT auth.uid())
              WHERE previous_chapter.season_id = chapter.season_id
                AND previous_chapter.number = chapter.number - 1
           )
         )
    )
  );

DROP POLICY IF EXISTS meetings_read ON public.meetings;
CREATE POLICY meetings_read ON public.meetings
  FOR SELECT TO anon, authenticated
  USING (
    (SELECT public.is_admin())
    OR EXISTS (
      SELECT 1
        FROM public.chapters AS chapter
        JOIN public.seasons AS season ON season.id = chapter.season_id
       WHERE chapter.id = meetings.chapter_id
         AND (chapter.published_at IS NULL OR chapter.published_at <= statement_timestamp())
         AND season.status IN ('active', 'finished')
         AND (
           chapter.number = 1
           OR EXISTS (
             SELECT 1
               FROM public.chapters AS previous_chapter
               JOIN public.quiz_attempts AS attempt
                 ON attempt.chapter_id = previous_chapter.id
                AND attempt.user_id = (SELECT auth.uid())
              WHERE previous_chapter.season_id = chapter.season_id
                AND previous_chapter.number = chapter.number - 1
           )
         )
    )
  );

DROP POLICY IF EXISTS prompts_read ON public.host_prompts;
CREATE POLICY prompts_read ON public.host_prompts
  FOR SELECT TO anon, authenticated
  USING (
    (SELECT public.is_admin())
    OR EXISTS (
      SELECT 1
        FROM public.chapters AS chapter
        JOIN public.seasons AS season ON season.id = chapter.season_id
       WHERE chapter.id = host_prompts.chapter_id
         AND (chapter.published_at IS NULL OR chapter.published_at <= statement_timestamp())
         AND season.status IN ('active', 'finished')
         AND (
           chapter.number = 1
           OR EXISTS (
             SELECT 1
               FROM public.chapters AS previous_chapter
               JOIN public.quiz_attempts AS attempt
                 ON attempt.chapter_id = previous_chapter.id
                AND attempt.user_id = (SELECT auth.uid())
              WHERE previous_chapter.season_id = chapter.season_id
                AND previous_chapter.number = chapter.number - 1
           )
         )
    )
  );

DROP POLICY IF EXISTS vtc_read ON public.video_timed_comments;
CREATE POLICY vtc_read ON public.video_timed_comments
  FOR SELECT TO anon, authenticated
  USING (
    (SELECT public.is_admin())
    OR EXISTS (
      SELECT 1
        FROM public.chapters AS chapter
        JOIN public.seasons AS season ON season.id = chapter.season_id
       WHERE chapter.id = video_timed_comments.chapter_id
         AND (chapter.published_at IS NULL OR chapter.published_at <= statement_timestamp())
         AND season.status IN ('active', 'finished')
         AND (
           chapter.number = 1
           OR EXISTS (
             SELECT 1
               FROM public.chapters AS previous_chapter
               JOIN public.quiz_attempts AS attempt
                 ON attempt.chapter_id = previous_chapter.id
                AND attempt.user_id = (SELECT auth.uid())
              WHERE previous_chapter.season_id = chapter.season_id
                AND previous_chapter.number = chapter.number - 1
           )
         )
    )
  );

DROP POLICY IF EXISTS poll_read ON public.book_polls;
CREATE POLICY poll_read ON public.book_polls
  FOR SELECT TO anon, authenticated
  USING ((SELECT public.is_admin()) OR (status IN ('open', 'closed') AND opens_at <= statement_timestamp()));

DROP POLICY IF EXISTS poll_opts_read ON public.book_poll_options;
CREATE POLICY poll_opts_read ON public.book_poll_options
  FOR SELECT TO anon, authenticated
  USING (EXISTS (
    SELECT 1 FROM public.book_polls AS poll
     WHERE poll.id = book_poll_options.poll_id
       AND ((SELECT public.is_admin()) OR (poll.status IN ('open', 'closed') AND poll.opens_at <= statement_timestamp()))
  ));

-- Mantém a view do feed como única origem de spoilers; o filtro de publicação
-- também é aplicado pelo helper SECURITY DEFINER no schema privado.
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
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
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
    JOIN public.chapters AS chapter ON chapter.id = c.chapter_id
    JOIN public.seasons AS season ON season.id = chapter.season_id
   WHERE c.deleted_at IS NULL
     AND (chapter.published_at IS NULL OR chapter.published_at <= statement_timestamp())
     AND season.status IN ('active', 'finished')
     AND (
       (SELECT public.is_admin())
       OR chapter.number = 1
       OR EXISTS (
         SELECT 1
           FROM public.chapters AS previous_chapter
           JOIN public.quiz_attempts AS attempt
             ON attempt.chapter_id = previous_chapter.id
            AND attempt.user_id = (SELECT auth.uid())
          WHERE previous_chapter.season_id = chapter.season_id
            AND previous_chapter.number = chapter.number - 1
       )
     );
$$;
REVOKE ALL ON FUNCTION private.get_visible_comments() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.get_visible_comments() TO anon, authenticated;

COMMENT ON POLICY chapters_read ON public.chapters IS
  'Public content is limited to active/finished seasons, published timestamps, and the previous-chapter quiz gate; admins retain editorial visibility.';
COMMENT ON POLICY quiz_q_read_auth ON public.quiz_questions IS
  'Question text/options are available only for an accessible chapter; correct_idx remains unavailable to clients.';
COMMENT ON POLICY vtc_read ON public.video_timed_comments IS
  'Timed comments follow the same publication and chapter-progress boundary as the chapter video.';

-- A página pode explicar o bloqueio sem receber resumo, vídeo, comentários ou
-- perguntas. A função só retorna metadados de capítulos já publicados de uma
-- temporada pública; o conteúdo continua submetido às policies acima.
CREATE OR REPLACE FUNCTION public.get_chapter_access(p_chapter uuid)
RETURNS TABLE (
  chapter_id uuid,
  chapter_number integer,
  chapter_title text,
  season_id uuid,
  season_slug text,
  season_title text,
  can_open boolean,
  requires_quiz boolean
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  WITH current_chapter AS (
    SELECT c.id, c.number, c.title, c.season_id, s.slug, s.title AS season_title,
           s.status, c.published_at
      FROM public.chapters AS c
      JOIN public.seasons AS s ON s.id = c.season_id
     WHERE c.id = p_chapter
       AND s.status IN ('active', 'finished')
       AND (c.published_at IS NULL OR c.published_at <= statement_timestamp())
  )
  SELECT c.id,
         c.number,
         c.title,
         c.season_id,
         c.slug,
         c.season_title,
         (
           (SELECT public.is_admin())
           OR c.number = 1
           OR EXISTS (
             SELECT 1
               FROM public.chapters AS previous_chapter
               JOIN public.quiz_attempts AS attempt
                 ON attempt.chapter_id = previous_chapter.id
                AND attempt.user_id = (SELECT auth.uid())
              WHERE previous_chapter.season_id = c.season_id
                AND previous_chapter.number = c.number - 1
           )
         ),
         c.number > 1
    FROM current_chapter AS c;
$$;
REVOKE ALL ON FUNCTION public.get_chapter_access(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_chapter_access(uuid) TO anon, authenticated;
