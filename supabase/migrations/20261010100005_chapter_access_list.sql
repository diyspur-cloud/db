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
  SELECT c.id,
         c.number,
         c.title,
         c.reading_range,
         c.published_at,
         private.can_view_chapter(c.id),
         c.number > 1
    FROM public.chapters AS c
   WHERE c.season_id = p_season
     AND (c.published_at IS NULL OR c.published_at <= statement_timestamp())
   ORDER BY c.number;
$$;
REVOKE ALL ON FUNCTION public.get_season_chapter_access(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_season_chapter_access(uuid) TO anon, authenticated;
