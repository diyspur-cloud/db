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
BEGIN
  IF p_user IS NULL THEN RETURN; END IF;
  SELECT s.id INTO active_season
    FROM public.seasons AS s
   WHERE s.status = 'active'::public.cycle_status
   ORDER BY s.starts_at DESC NULLS LAST, s.created_at DESC, s.id
   LIMIT 1;

  FOR achievement_row IN
    SELECT id, code, xp_reward
      FROM public.achievements
  LOOP
    eligible := false;
    IF achievement_row.code = 'perfect_quiz' THEN
      SELECT EXISTS (
        SELECT 1 FROM public.quiz_attempts
         WHERE user_id = p_user
           AND total > 0
           AND score = total
      ) INTO eligible;
    ELSIF achievement_row.code IN ('first_book', 'five_books') THEN
      SELECT COUNT(*) >= CASE WHEN achievement_row.code = 'first_book' THEN 1 ELSE 5 END
        INTO eligible
        FROM public.xp_events
       WHERE user_id = p_user
         AND source = 'finish_book'::public.xp_source;
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
          VALUES (p_user, achievement_row.xp_reward, CASE WHEN active_season IS NULL THEN 0 ELSE achievement_row.xp_reward END, active_season, statement_timestamp())
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
REVOKE ALL ON FUNCTION public.evaluate_user_achievements(uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.award_xp(p_user uuid, p_source public.xp_source, p_amount integer, p_ref uuid DEFAULT NULL::uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_event_id uuid;
  v_active_season uuid;
BEGIN
  IF p_user IS NULL OR p_source IS NULL OR p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'invalid XP award' USING ERRCODE = '22023';
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

SELECT public.evaluate_user_achievements(id)
  FROM auth.users
 WHERE email = 'qa.diyspur.20261010@example.com'
 LIMIT 1;
