-- Restrict public/authenticated reads of content scheduled for the future.
-- Legacy rows with published_at NULL remain visible for compatibility with the
-- current seed/content contract; an explicit published_at in the future is not.
-- Admin access remains governed by the existing chapters_admin_write policy.

DROP POLICY IF EXISTS "chapters_read" ON public.chapters;
CREATE POLICY "chapters_read" ON public.chapters
  FOR SELECT TO anon, authenticated
  USING (
    (published_at IS NULL OR published_at <= statement_timestamp())
    AND EXISTS (
      SELECT 1
        FROM public.seasons AS season
       WHERE season.id = chapters.season_id
         AND season.status IN ('active', 'finished')
    )
  );

-- Authenticated readers may fetch question text/options only for chapters that
-- are currently available. Correct answers remain column-revoked and are
-- returned only by the quiz validation Edge Function.
DROP POLICY IF EXISTS "quiz_q_read_auth" ON public.quiz_questions;
CREATE POLICY "quiz_q_read_auth" ON public.quiz_questions
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1
      FROM public.chapters AS chapter
      JOIN public.seasons AS season ON season.id = chapter.season_id
     WHERE chapter.id = quiz_questions.chapter_id
       AND (chapter.published_at IS NULL OR chapter.published_at <= statement_timestamp())
       AND season.status IN ('active', 'finished')
  ));

-- Do not expose a meeting associated with a chapter that is not yet available.
DROP POLICY IF EXISTS "meetings_read" ON public.meetings;
CREATE POLICY "meetings_read" ON public.meetings
  FOR SELECT TO anon, authenticated
  USING (
    chapter_id IS NULL OR EXISTS (
      SELECT 1
        FROM public.chapters AS chapter
        JOIN public.seasons AS season ON season.id = chapter.season_id
       WHERE chapter.id = meetings.chapter_id
         AND (chapter.published_at IS NULL OR chapter.published_at <= statement_timestamp())
         AND season.status IN ('active', 'finished')
    )
  );

-- The comments view is backed by this narrowly-scoped SECURITY DEFINER helper.
-- Preserve the existing spoiler threshold behavior while excluding comments
-- linked to future/unpublished-season chapters at the database boundary.
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
     AND season.status IN ('active', 'finished');
$$;
REVOKE ALL ON FUNCTION private.get_visible_comments() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.get_visible_comments() TO anon, authenticated;

COMMENT ON POLICY "chapters_read" ON public.chapters IS
  'Publicly readable chapters belong to active/finished seasons and are legacy-unscheduled (published_at NULL) or already published; future timestamps remain hidden.';
