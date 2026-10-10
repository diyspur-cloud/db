-- Hardening incremental for the functional audit.
-- This migration is intentionally self-contained and does not replay the drifted baseline.

-- A reader may edit profile text/onboarding, but level is derived from progress and XP.
REVOKE UPDATE (level) ON TABLE public.profiles FROM anon, authenticated;

-- The evaluator mutates privileged tables and is only an internal service operation.
REVOKE EXECUTE ON FUNCTION public.evaluate_user_achievements(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.evaluate_user_achievements(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.evaluate_user_achievements(p_user uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  achievement_row record;
  eligible boolean;
  event_id uuid;
  active_season uuid;
  completed_books integer;
  total_machado_books integer;
  completed_machado_books integer;
  brazilian_books integer;
BEGIN
  IF p_user IS NULL THEN RETURN; END IF;

  SELECT s.id INTO active_season
    FROM public.seasons AS s
   WHERE s.status = 'active'::public.cycle_status
   ORDER BY s.starts_at DESC NULLS LAST, s.created_at DESC, s.id
   LIMIT 1;

  SELECT COUNT(*) INTO completed_books
    FROM (
      SELECT s.book_id
        FROM public.user_progress AS up
        JOIN public.chapters AS c ON c.id = up.chapter_id AND up.status = 'read'
        JOIN public.seasons AS s ON s.id = c.season_id
        JOIN public.books AS b ON b.id = s.book_id
       WHERE up.user_id = p_user
       GROUP BY s.book_id, b.total_chapters
      HAVING COUNT(DISTINCT c.id) >= COALESCE(NULLIF(MAX(b.total_chapters), 0), COUNT(DISTINCT c.id))
    ) AS finished;

  SELECT COUNT(*) INTO total_machado_books
    FROM public.books AS b
    JOIN public.authors AS a ON a.id = b.author_id
   WHERE lower(a.slug) = 'machado-de-assis';

  SELECT COUNT(*) INTO completed_machado_books
    FROM (
      SELECT s.book_id
        FROM public.user_progress AS up
        JOIN public.chapters AS c ON c.id = up.chapter_id AND up.status = 'read'
        JOIN public.seasons AS s ON s.id = c.season_id
        JOIN public.books AS b ON b.id = s.book_id
        JOIN public.authors AS a ON a.id = b.author_id
       WHERE up.user_id = p_user AND lower(a.slug) = 'machado-de-assis'
       GROUP BY s.book_id, b.total_chapters
      HAVING COUNT(DISTINCT c.id) >= COALESCE(NULLIF(MAX(b.total_chapters), 0), COUNT(DISTINCT c.id))
    ) AS finished_machado;

  SELECT COUNT(*) INTO brazilian_books
    FROM (
      SELECT s.book_id
        FROM public.user_progress AS up
        JOIN public.chapters AS c ON c.id = up.chapter_id AND up.status = 'read'
        JOIN public.seasons AS s ON s.id = c.season_id
        JOIN public.books AS b ON b.id = s.book_id
       WHERE up.user_id = p_user
         AND EXISTS (SELECT 1 FROM unnest(COALESCE(b.tags, ARRAY[]::text[])) AS tag WHERE lower(tag) = lower('Literatura Brasileira'))
       GROUP BY s.book_id, b.total_chapters
      HAVING COUNT(DISTINCT c.id) >= COALESCE(NULLIF(MAX(b.total_chapters), 0), COUNT(DISTINCT c.id))
    ) AS finished_brazilian;

  FOR achievement_row IN
    SELECT id, code, xp_reward, rule
      FROM public.achievements
  LOOP
    eligible := false;
    IF achievement_row.code = 'perfect_quiz' THEN
      SELECT EXISTS (
        SELECT 1 FROM public.quiz_attempts
         WHERE user_id = p_user AND total > 0 AND score = total
      ) INTO eligible;
    ELSIF achievement_row.code = 'first_book' THEN
      eligible := completed_books >= 1;
    ELSIF achievement_row.code = 'five_books' THEN
      eligible := completed_books >= 5;
    ELSIF achievement_row.code = 'streak_4w' THEN
      SELECT COALESCE(us.current_streak, 0) >= 28 OR COALESCE(us.longest_streak, 0) >= 28
        INTO eligible FROM public.user_streaks AS us WHERE us.user_id = p_user;
      eligible := COALESCE(eligible, false);
    ELSIF achievement_row.code = 'machado_master' THEN
      eligible := total_machado_books > 0 AND completed_machado_books = total_machado_books;
    ELSIF achievement_row.code = 'brazilian_lit_expert' THEN
      eligible := brazilian_books >= 5;
    END IF;

    IF eligible THEN
      INSERT INTO public.user_achievements(user_id, achievement_id)
      VALUES (p_user, achievement_row.id)
      ON CONFLICT (user_id, achievement_id) DO NOTHING;
      IF FOUND AND COALESCE(achievement_row.xp_reward, 0) > 0 THEN
        INSERT INTO public.xp_events(user_id, source, amount, ref_id)
        VALUES (p_user, 'achievement'::public.xp_source, achievement_row.xp_reward, achievement_row.id)
        ON CONFLICT (user_id, source, ref_id) WHERE ref_id IS NOT NULL DO NOTHING
        RETURNING id INTO event_id;
        IF event_id IS NOT NULL THEN
          INSERT INTO public.user_xp(user_id, total_xp, season_xp, season_id, updated_at)
          VALUES (p_user, achievement_row.xp_reward,
                  CASE WHEN active_season IS NULL THEN 0 ELSE achievement_row.xp_reward END,
                  active_season, statement_timestamp())
          ON CONFLICT (user_id) DO UPDATE SET
            total_xp = public.user_xp.total_xp + EXCLUDED.total_xp,
            season_xp = CASE
              WHEN active_season IS NULL THEN public.user_xp.season_xp
              WHEN public.user_xp.season_id IS DISTINCT FROM active_season THEN EXCLUDED.season_xp
              ELSE public.user_xp.season_xp + EXCLUDED.season_xp
            END,
            season_id = COALESCE(active_season, public.user_xp.season_id),
            updated_at = statement_timestamp();
        END IF;
      END IF;
    END IF;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.evaluate_user_achievements(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.evaluate_user_achievements(uuid) TO service_role;

-- One quiz reward per user/chapter, while attempts themselves remain historical.
CREATE OR REPLACE FUNCTION public.award_xp(
  p_user uuid,
  p_source public.xp_source,
  p_amount integer,
  p_ref uuid DEFAULT NULL::uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_event_id uuid;
  v_active_season uuid;
  v_quiz_chapter uuid;
BEGIN
  IF p_user IS NULL OR p_source IS NULL OR p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'invalid XP award' USING ERRCODE = '22023';
  END IF;

  IF p_source = 'quiz_answer'::public.xp_source THEN
    SELECT qa.chapter_id INTO v_quiz_chapter
      FROM public.quiz_attempts AS qa
     WHERE qa.id = p_ref AND qa.user_id = p_user;
    IF v_quiz_chapter IS NULL THEN
      RAISE EXCEPTION 'quiz attempt not owned by user' USING ERRCODE = '42501';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(p_user::text || ':' || v_quiz_chapter::text, 0));
    IF EXISTS (
      SELECT 1
        FROM public.xp_events AS xe
        JOIN public.quiz_attempts AS prior ON prior.id = xe.ref_id
       WHERE xe.user_id = p_user
         AND xe.source = 'quiz_answer'::public.xp_source
         AND prior.chapter_id = v_quiz_chapter
    ) THEN
      RETURN;
    END IF;
  END IF;

  INSERT INTO public.xp_events(user_id, source, amount, ref_id)
  VALUES (p_user, p_source, p_amount, p_ref)
  ON CONFLICT (user_id, source, ref_id) WHERE ref_id IS NOT NULL DO NOTHING
  RETURNING id INTO v_event_id;
  IF v_event_id IS NULL THEN RETURN; END IF;

  SELECT s.id INTO v_active_season
    FROM public.seasons AS s
   WHERE s.status = 'active'::public.cycle_status
   ORDER BY s.starts_at DESC NULLS LAST, s.created_at DESC, s.id
   LIMIT 1;
  INSERT INTO public.user_xp(user_id, total_xp, season_xp, season_id, updated_at)
  VALUES (p_user, p_amount, CASE WHEN v_active_season IS NULL THEN 0 ELSE p_amount END, v_active_season, statement_timestamp())
  ON CONFLICT (user_id) DO UPDATE SET
    total_xp = public.user_xp.total_xp + EXCLUDED.total_xp,
    season_xp = CASE
      WHEN v_active_season IS NULL THEN public.user_xp.season_xp
      WHEN public.user_xp.season_id IS DISTINCT FROM v_active_season THEN EXCLUDED.season_xp
      ELSE public.user_xp.season_xp + EXCLUDED.season_xp
    END,
    season_id = COALESCE(v_active_season, public.user_xp.season_id),
    updated_at = statement_timestamp();

  IF p_source <> 'achievement'::public.xp_source THEN
    PERFORM public.evaluate_user_achievements(p_user);
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.award_xp(uuid, public.xp_source, integer, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.award_xp(uuid, public.xp_source, integer, uuid) TO service_role;
