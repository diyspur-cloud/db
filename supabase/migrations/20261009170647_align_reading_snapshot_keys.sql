-- O snapshot permanece invoker-only e só aceita o histórico do próprio leitor.
-- O filtro de review apagada é uma proteção do baseline e fica documentado
-- como diferença técnica da serialização literal do anexo.

CREATE OR REPLACE FUNCTION public.build_user_reading_snapshot(p_user uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'title', b.title,
        'moods', bmv.moods,
        'pace', bmv.pace,
        'rating', br.rating,
        'review', br.review_text
      )
      ORDER BY b.title, b.id, up.id
    )::text,
    '[]'
  )
    FROM public.user_progress AS up
    JOIN public.chapters AS c
      ON c.id = up.chapter_id
    JOIN public.seasons AS s
      ON s.id = c.season_id
    JOIN public.books AS b
      ON b.id = s.book_id
    LEFT JOIN public.book_mood_votes AS bmv
      ON bmv.book_id = b.id
     AND bmv.user_id = p_user
    LEFT JOIN public.book_reviews AS br
      ON br.book_id = b.id
     AND br.user_id = p_user
     AND br.deleted_at IS NULL
   WHERE up.user_id = p_user
     AND (auth.uid() IS NULL OR auth.uid() = p_user);
$$;

REVOKE ALL ON FUNCTION public.build_user_reading_snapshot(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.build_user_reading_snapshot(uuid)
  TO authenticated, service_role;
