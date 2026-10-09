-- Seguimento da auditoria anexada (2026-10-09).
-- Mudanças aditivas: nenhuma tabela/coluna/linha existente é removida.
-- O projeto remoto usa PostgreSQL 17 e o histórico legado deve permanecer intacto.
GRANT USAGE ON SCHEMA private TO service_role;

-- 1) XP: uma referência de atividade só pode creditar XP uma vez.
CREATE UNIQUE INDEX IF NOT EXISTS xp_events_user_source_ref_id_uidx
  ON public.xp_events (user_id, source, ref_id)
  WHERE ref_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.award_xp(
  p_user uuid,
  p_source public.xp_source,
  p_amount integer,
  p_ref uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_event_id uuid;
  v_active_season uuid;
BEGIN
  IF p_user IS NULL OR p_source IS NULL OR p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'invalid XP award' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.xp_events (user_id, source, amount, ref_id)
  VALUES (p_user, p_source, p_amount, p_ref)
  ON CONFLICT (user_id, source, ref_id) WHERE ref_id IS NOT NULL DO NOTHING
  RETURNING id INTO v_event_id;

  IF v_event_id IS NULL THEN
    RETURN;
  END IF;

  SELECT s.id INTO v_active_season
  FROM public.seasons AS s
  WHERE s.status = 'active'::public.cycle_status
  ORDER BY s.starts_at DESC NULLS LAST, s.created_at DESC, s.id
  LIMIT 1;

  INSERT INTO public.user_xp (user_id, total_xp, season_xp, season_id, updated_at)
  VALUES (
    p_user,
    p_amount,
    CASE WHEN v_active_season IS NULL THEN 0 ELSE p_amount END,
    v_active_season,
    statement_timestamp()
  )
  ON CONFLICT (user_id) DO UPDATE
  SET total_xp = public.user_xp.total_xp + EXCLUDED.total_xp,
      season_xp = CASE
        WHEN v_active_season IS NULL THEN public.user_xp.season_xp
        WHEN public.user_xp.season_id IS DISTINCT FROM v_active_season THEN EXCLUDED.season_xp
        ELSE public.user_xp.season_xp + EXCLUDED.season_xp
      END,
      season_id = COALESCE(v_active_season, public.user_xp.season_id),
      updated_at = statement_timestamp();
END;
$$;
REVOKE ALL ON FUNCTION public.award_xp(uuid, public.xp_source, integer, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.award_xp(uuid, public.xp_source, integer, uuid)
  TO service_role;

-- 2) Médias: recomputar após INSERT, UPDATE e DELETE, incluindo migração de owner/capítulo.
CREATE OR REPLACE FUNCTION private.refresh_user_quiz_average(p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF p_user IS NULL THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.quiz_attempts qa WHERE qa.user_id = p_user) THEN
    DELETE FROM public.user_quiz_averages WHERE user_id = p_user;
    RETURN;
  END IF;
  INSERT INTO public.user_quiz_averages (
    user_id, attempts_total, score_sum, total_sum, average_percent,
    best_percent, last_attempt_at, updated_at
  )
  SELECT p_user, count(*)::integer, coalesce(sum(qa.score), 0)::integer,
    coalesce(sum(qa.total), 0)::integer,
    CASE WHEN coalesce(sum(qa.total), 0) = 0 THEN 0
      ELSE round((sum(qa.score)::numeric / sum(qa.total)::numeric) * 100, 2) END,
    coalesce(max(CASE WHEN qa.total = 0 THEN 0
      ELSE round((qa.score::numeric / qa.total::numeric) * 100, 2) END), 0),
    max(qa.created_at), statement_timestamp()
  FROM public.quiz_attempts AS qa WHERE qa.user_id = p_user
  ON CONFLICT (user_id) DO UPDATE SET
    attempts_total = EXCLUDED.attempts_total, score_sum = EXCLUDED.score_sum,
    total_sum = EXCLUDED.total_sum, average_percent = EXCLUDED.average_percent,
    best_percent = EXCLUDED.best_percent, last_attempt_at = EXCLUDED.last_attempt_at,
    updated_at = statement_timestamp();
END;
$$;

CREATE OR REPLACE FUNCTION private.refresh_chapter_quiz_average(p_chapter uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF p_chapter IS NULL THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.quiz_attempts qa WHERE qa.chapter_id = p_chapter) THEN
    DELETE FROM public.chapter_quiz_averages WHERE chapter_id = p_chapter;
    RETURN;
  END IF;
  INSERT INTO public.chapter_quiz_averages (
    chapter_id, attempts_total, average_percent, perfect_count, updated_at
  )
  SELECT p_chapter, count(*)::integer,
    CASE WHEN coalesce(sum(qa.total), 0) = 0 THEN 0
      ELSE round((sum(qa.score)::numeric / sum(qa.total)::numeric) * 100, 2) END,
    count(*) FILTER (WHERE qa.score = qa.total)::integer, statement_timestamp()
  FROM public.quiz_attempts AS qa WHERE qa.chapter_id = p_chapter
  ON CONFLICT (chapter_id) DO UPDATE SET
    attempts_total = EXCLUDED.attempts_total, average_percent = EXCLUDED.average_percent,
    perfect_count = EXCLUDED.perfect_count, updated_at = statement_timestamp();
END;
$$;

CREATE OR REPLACE FUNCTION private.refresh_user_quiz_averages()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF TG_OP <> 'INSERT' THEN PERFORM private.refresh_user_quiz_average(OLD.user_id); END IF;
  IF TG_OP <> 'DELETE' AND (TG_OP = 'INSERT' OR OLD.user_id IS DISTINCT FROM NEW.user_id) THEN
    PERFORM private.refresh_user_quiz_average(NEW.user_id);
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION private.refresh_chapter_quiz_averages()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF TG_OP <> 'INSERT' THEN PERFORM private.refresh_chapter_quiz_average(OLD.chapter_id); END IF;
  IF TG_OP <> 'DELETE' AND (TG_OP = 'INSERT' OR OLD.chapter_id IS DISTINCT FROM NEW.chapter_id) THEN
    PERFORM private.refresh_chapter_quiz_average(NEW.chapter_id);
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION private.refresh_user_quiz_average(uuid),
  private.refresh_chapter_quiz_average(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.refresh_user_quiz_averages(),
  private.refresh_chapter_quiz_averages() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.refresh_user_quiz_averages(),
  public.refresh_chapter_quiz_averages() FROM PUBLIC, anon, authenticated, service_role;
DROP TRIGGER IF EXISTS trg_refresh_user_quiz_averages ON public.quiz_attempts;
CREATE TRIGGER trg_refresh_user_quiz_averages AFTER INSERT OR UPDATE OR DELETE
  ON public.quiz_attempts FOR EACH ROW EXECUTE FUNCTION private.refresh_user_quiz_averages();
DROP TRIGGER IF EXISTS trg_refresh_chapter_quiz_averages ON public.quiz_attempts;
CREATE TRIGGER trg_refresh_chapter_quiz_averages AFTER INSERT OR UPDATE OR DELETE
  ON public.quiz_attempts FOR EACH ROW EXECUTE FUNCTION private.refresh_chapter_quiz_averages();

-- 3) Metas anuais: capítulo concluído não equivale a livro concluído.
-- Livro concluído = todos os capítulos catalogados, em todas as temporadas,
-- marcados read; o ano de conclusão é o do último capítulo.
CREATE OR REPLACE FUNCTION private.refresh_reading_goal_progress()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_user uuid;
  v_goal record;
BEGIN
  FOR v_user IN
    SELECT DISTINCT affected.user_id
    FROM unnest(ARRAY[
      CASE WHEN TG_OP <> 'INSERT' THEN OLD.user_id END,
      CASE WHEN TG_OP <> 'DELETE' THEN NEW.user_id END
    ]) AS affected(user_id)
    WHERE affected.user_id IS NOT NULL
  LOOP
    FOR v_goal IN
      SELECT rg.id, rg.year FROM public.reading_goals AS rg WHERE rg.user_id = v_user
    LOOP
      INSERT INTO public.reading_goal_progress (
        goal_id, books_done, pages_done, minutes_done, updated_at
      )
      SELECT v_goal.id,
        (SELECT count(*)::integer FROM (
          SELECT s.book_id
          FROM public.chapters AS c
          JOIN public.seasons AS s ON s.id = c.season_id
          LEFT JOIN public.user_progress AS up ON up.chapter_id = c.id AND up.user_id = v_user
          GROUP BY s.book_id
          HAVING count(DISTINCT c.id) > 0
            AND count(DISTINCT c.id) = count(DISTINCT c.id) FILTER (
              WHERE up.status = 'read'::public.shelf_status
            )
            AND max(coalesce(up.finished_at, up.updated_at)) FILTER (WHERE up.status = 'read'::public.shelf_status)
              >= make_date(v_goal.year, 1, 1)
            AND max(coalesce(up.finished_at, up.updated_at)) FILTER (WHERE up.status = 'read'::public.shelf_status)
              < make_date(v_goal.year + 1, 1, 1)
        ) AS completed_books),
        (SELECT coalesce(sum(rje.page_to - rje.page_from), 0)::integer
          FROM public.reading_journal_entries AS rje
          WHERE rje.user_id = v_user
            AND rje.entry_date >= make_date(v_goal.year, 1, 1)
            AND rje.entry_date < make_date(v_goal.year + 1, 1, 1)),
        (SELECT coalesce(sum(rje.minutes_read), 0)::integer
          FROM public.reading_journal_entries AS rje
          WHERE rje.user_id = v_user
            AND rje.entry_date >= make_date(v_goal.year, 1, 1)
            AND rje.entry_date < make_date(v_goal.year + 1, 1, 1)),
        statement_timestamp()
      ON CONFLICT (goal_id) DO UPDATE SET
        books_done = EXCLUDED.books_done, pages_done = EXCLUDED.pages_done,
        minutes_done = EXCLUDED.minutes_done, updated_at = statement_timestamp();
    END LOOP;
  END LOOP;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION private.refresh_reading_goal_progress()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.refresh_reading_goal_progress()
  FROM PUBLIC, anon, authenticated, service_role;
CREATE OR REPLACE FUNCTION private.stamp_user_progress_finished_at()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF NEW.status = 'read'::public.shelf_status
      AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status)
      AND NEW.finished_at IS NULL THEN
    NEW.finished_at := statement_timestamp();
  ELSIF TG_OP = 'UPDATE' AND NEW.status <> 'read'::public.shelf_status
      AND OLD.status = 'read'::public.shelf_status THEN
    NEW.finished_at := NULL;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.stamp_user_progress_finished_at()
  FROM PUBLIC, anon, authenticated, service_role;
DROP TRIGGER IF EXISTS trg_stamp_user_progress_finished_at ON public.user_progress;
CREATE TRIGGER trg_stamp_user_progress_finished_at
  BEFORE INSERT OR UPDATE OF status, finished_at ON public.user_progress
  FOR EACH ROW EXECUTE FUNCTION private.stamp_user_progress_finished_at();
DROP TRIGGER IF EXISTS trg_goal_progress_refresh ON public.user_progress;
CREATE TRIGGER trg_goal_progress_refresh AFTER INSERT OR UPDATE OR DELETE
  ON public.user_progress FOR EACH ROW EXECUTE FUNCTION private.refresh_reading_goal_progress();
DROP TRIGGER IF EXISTS trg_goal_progress_refresh_journal ON public.reading_journal_entries;
CREATE TRIGGER trg_goal_progress_refresh_journal AFTER INSERT OR UPDATE OR DELETE
  ON public.reading_journal_entries FOR EACH ROW EXECUTE FUNCTION private.refresh_reading_goal_progress();
DROP TRIGGER IF EXISTS trg_goal_progress_refresh_goal ON public.reading_goals;
CREATE TRIGGER trg_goal_progress_refresh_goal AFTER INSERT OR UPDATE
  ON public.reading_goals FOR EACH ROW EXECUTE FUNCTION private.refresh_reading_goal_progress();

-- 4) Visão de leitura: agregar progresso por livro e diário antes de juntá-los,
-- evitando contar capítulos como livros e multiplicar minutos pelos joins.
CREATE OR REPLACE VIEW public.v_user_reading_overview WITH (security_invoker = true) AS
WITH book_progress AS (
  SELECT up.user_id, s.book_id,
    (SELECT count(*)::bigint FROM public.chapters all_chapters
      JOIN public.seasons all_seasons ON all_seasons.id = all_chapters.season_id
      WHERE all_seasons.book_id = s.book_id) AS total_chapters,
    count(DISTINCT c.id) FILTER (
      WHERE up.status = 'read'::public.shelf_status
    )::bigint AS completed_chapters,
    bool_or(up.status = 'reading'::public.shelf_status) AS has_reading,
    bool_or(up.status = 'want_to_read'::public.shelf_status) AS has_want,
    bool_or(up.status = 'dnf'::public.shelf_status) AS has_dnf
  FROM public.user_progress AS up
  JOIN public.chapters AS c ON c.id = up.chapter_id
  JOIN public.seasons AS s ON s.id = c.season_id
  GROUP BY up.user_id, s.book_id
), progress_summary AS (
  SELECT bp.user_id,
    count(*) FILTER (WHERE bp.total_chapters > 0 AND bp.completed_chapters = bp.total_chapters)::bigint AS books_read,
    count(*) FILTER (WHERE NOT (bp.total_chapters > 0 AND bp.completed_chapters = bp.total_chapters)
      AND (bp.has_reading OR bp.completed_chapters > 0))::bigint AS books_reading,
    count(*) FILTER (WHERE bp.has_want AND NOT bp.has_reading
      AND bp.completed_chapters = 0 AND NOT bp.has_dnf)::bigint AS books_want,
    count(*) FILTER (WHERE bp.has_dnf)::bigint AS books_dnf
  FROM book_progress AS bp GROUP BY bp.user_id
), journal_summary AS (
  SELECT rje.user_id, coalesce(sum(rje.minutes_read), 0)::bigint AS total_minutes,
    count(DISTINCT rje.entry_date)::bigint AS reading_days,
    count(*) FILTER (WHERE rje.entry_date = CURRENT_DATE)::bigint AS read_today
  FROM public.reading_journal_entries AS rje GROUP BY rje.user_id
)
SELECT p.id AS user_id,
  coalesce(ps.books_read, 0)::bigint AS books_read,
  coalesce(ps.books_reading, 0)::bigint AS books_reading,
  coalesce(ps.books_want, 0)::bigint AS books_want,
  coalesce(ps.books_dnf, 0)::bigint AS books_dnf,
  coalesce(js.total_minutes, 0)::bigint AS total_minutes,
  coalesce(js.reading_days, 0)::bigint AS reading_days,
  coalesce(js.read_today, 0)::bigint AS read_today
FROM public.profiles AS p
LEFT JOIN progress_summary AS ps ON ps.user_id = p.id
LEFT JOIN journal_summary AS js ON js.user_id = p.id;

-- 5) Likes do diário: a tabela não existia; criar registro por usuário e
-- manter likes_count sem permitir que o cliente altere o contador diretamente.
CREATE TABLE IF NOT EXISTS public.reading_journal_likes (
  entry_id uuid NOT NULL REFERENCES public.reading_journal_entries(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  PRIMARY KEY (entry_id, user_id)
);
CREATE INDEX IF NOT EXISTS reading_journal_likes_user_id_idx ON public.reading_journal_likes (user_id);
ALTER TABLE public.reading_journal_likes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.reading_journal_likes FROM PUBLIC, anon;
GRANT SELECT, INSERT, DELETE ON TABLE public.reading_journal_likes TO authenticated;
GRANT ALL ON TABLE public.reading_journal_likes TO service_role;
DROP POLICY IF EXISTS reading_journal_likes_select_own ON public.reading_journal_likes;
CREATE POLICY reading_journal_likes_select_own ON public.reading_journal_likes FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);
DROP POLICY IF EXISTS reading_journal_likes_insert_own_visible ON public.reading_journal_likes;
CREATE POLICY reading_journal_likes_insert_own_visible ON public.reading_journal_likes FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.uid()) = user_id AND EXISTS (
    SELECT 1 FROM public.reading_journal_entries AS e WHERE e.id = entry_id
  ));
DROP POLICY IF EXISTS reading_journal_likes_delete_own ON public.reading_journal_likes;
CREATE POLICY reading_journal_likes_delete_own ON public.reading_journal_likes FOR DELETE TO authenticated
  USING ((SELECT auth.uid()) = user_id);
CREATE OR REPLACE FUNCTION private.bump_journal_likes()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.reading_journal_entries SET likes_count = likes_count + 1 WHERE id = NEW.entry_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.reading_journal_entries SET likes_count = greatest(likes_count - 1, 0) WHERE id = OLD.entry_id;
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION private.bump_journal_likes() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.bump_journal_likes() FROM PUBLIC, anon, authenticated, service_role;
DROP TRIGGER IF EXISTS trg_reading_journal_likes_count ON public.reading_journal_likes;
CREATE TRIGGER trg_reading_journal_likes_count AFTER INSERT OR DELETE
  ON public.reading_journal_likes FOR EACH ROW EXECUTE FUNCTION private.bump_journal_likes();

-- 6) Enquetes: validar período/opção e atualizar contadores de forma atômica.
CREATE OR REPLACE FUNCTION private.bump_book_poll_option_votes()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.book_poll_options SET votes_count = votes_count + 1 WHERE id = NEW.option_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.book_poll_options SET votes_count = greatest(votes_count - 1, 0) WHERE id = OLD.option_id;
  ELSIF OLD.option_id IS DISTINCT FROM NEW.option_id THEN
    UPDATE public.book_poll_options SET votes_count = greatest(votes_count - 1, 0) WHERE id = OLD.option_id;
    UPDATE public.book_poll_options SET votes_count = votes_count + 1 WHERE id = NEW.option_id;
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION private.bump_book_poll_option_votes() FROM PUBLIC, anon, authenticated, service_role;
DROP TRIGGER IF EXISTS trg_book_poll_option_votes_count ON public.book_poll_votes;
CREATE TRIGGER trg_book_poll_option_votes_count AFTER INSERT OR UPDATE OF option_id OR DELETE
  ON public.book_poll_votes FOR EACH ROW EXECUTE FUNCTION private.bump_book_poll_option_votes();
REVOKE INSERT, UPDATE, DELETE ON TABLE public.book_poll_votes FROM anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON TABLE public.book_poll_votes TO service_role;
UPDATE public.book_poll_options AS opt
SET votes_count = (SELECT count(*)::integer FROM public.book_poll_votes AS vote WHERE vote.option_id = opt.id)
WHERE opt.votes_count IS DISTINCT FROM (
  SELECT count(*)::integer FROM public.book_poll_votes AS vote WHERE vote.option_id = opt.id
);

CREATE OR REPLACE FUNCTION public.cast_book_poll_vote(p_user uuid, p_poll uuid, p_option uuid)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE
  v_poll public.book_polls%ROWTYPE;
  v_count integer;
BEGIN
  IF p_user IS NULL OR p_poll IS NULL OR p_option IS NULL THEN
    RAISE EXCEPTION 'poll vote payload is invalid' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_poll FROM public.book_polls WHERE id = p_poll FOR UPDATE;
  IF NOT FOUND OR v_poll.status <> 'open'::public.poll_status
      OR v_poll.opens_at > statement_timestamp() OR v_poll.closes_at <= statement_timestamp() THEN
    RAISE EXCEPTION 'poll is not open' USING ERRCODE = 'P0001';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.book_poll_options opt WHERE opt.id = p_option AND opt.poll_id = p_poll) THEN
    RAISE EXCEPTION 'option does not belong to poll' USING ERRCODE = '23503';
  END IF;
  INSERT INTO public.book_poll_votes (poll_id, option_id, user_id)
  VALUES (p_poll, p_option, p_user)
  ON CONFLICT (poll_id, user_id) DO UPDATE
    SET option_id = EXCLUDED.option_id, created_at = statement_timestamp()
    WHERE public.book_poll_votes.option_id IS DISTINCT FROM EXCLUDED.option_id;
  SELECT votes_count INTO v_count FROM public.book_poll_options WHERE id = p_option;
  RETURN coalesce(v_count, 0);
END;
$$;
REVOKE ALL ON FUNCTION public.cast_book_poll_vote(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cast_book_poll_vote(uuid, uuid, uuid) TO service_role;

-- 7) Limite atômico e idempotência de quizzes; somente o backend usa estas RPCs.
ALTER TABLE public.quiz_attempts ADD COLUMN IF NOT EXISTS client_request_id uuid;
CREATE UNIQUE INDEX IF NOT EXISTS quiz_attempts_user_request_id_uidx
  ON public.quiz_attempts (user_id, client_request_id) WHERE client_request_id IS NOT NULL;
CREATE TABLE IF NOT EXISTS private.quiz_rate_limits (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  chapter_id uuid NOT NULL,
  window_started_at timestamptz NOT NULL,
  attempts integer NOT NULL CHECK (attempts > 0),
  PRIMARY KEY (user_id, chapter_id)
);
REVOKE ALL ON TABLE private.quiz_rate_limits FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE private.quiz_rate_limits TO service_role;
CREATE OR REPLACE FUNCTION public.consume_quiz_rate_limit(p_user uuid, p_chapter uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE v_attempts integer;
BEGIN
  IF p_user IS NULL OR p_chapter IS NULL THEN
    RAISE EXCEPTION 'rate limit identity is required' USING ERRCODE = '22023';
  END IF;
  INSERT INTO private.quiz_rate_limits (user_id, chapter_id, window_started_at, attempts)
  VALUES (p_user, p_chapter, clock_timestamp(), 1)
  ON CONFLICT (user_id, chapter_id) DO UPDATE SET
    window_started_at = CASE
      WHEN private.quiz_rate_limits.window_started_at + interval '60 seconds' <= clock_timestamp()
        THEN clock_timestamp() ELSE private.quiz_rate_limits.window_started_at END,
    attempts = CASE
      WHEN private.quiz_rate_limits.window_started_at + interval '60 seconds' <= clock_timestamp()
        THEN 1 ELSE private.quiz_rate_limits.attempts + 1 END
  RETURNING attempts INTO v_attempts;
  RETURN v_attempts <= 10;
END;
$$;
REVOKE ALL ON FUNCTION public.consume_quiz_rate_limit(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_quiz_rate_limit(uuid, uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.record_quiz_attempt(
  p_user uuid, p_chapter uuid, p_request_id uuid, p_score integer, p_total integer, p_answers jsonb
) RETURNS TABLE (attempt_id uuid, score integer, total integer, duplicate boolean)
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE v_attempt_id uuid; v_score integer; v_total integer;
BEGIN
  IF p_user IS NULL OR p_chapter IS NULL OR p_request_id IS NULL OR p_total IS NULL OR p_total < 1
      OR p_score IS NULL OR p_score < 0 OR p_score > p_total
      OR jsonb_typeof(p_answers) <> 'array' OR jsonb_array_length(p_answers) <> p_total THEN
    RAISE EXCEPTION 'invalid quiz attempt payload' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_answers) AS answer(value)
    WHERE (answer.value->>'question_id') IS NULL OR (answer.value->>'chosen_idx') IS NULL
      OR (answer.value->>'is_correct') IS NULL
      OR NOT EXISTS (SELECT 1 FROM public.quiz_questions q
        WHERE q.id = (answer.value->>'question_id')::uuid AND q.chapter_id = p_chapter)
  ) THEN
    RAISE EXCEPTION 'quiz answer does not belong to chapter' USING ERRCODE = '22023';
  END IF;
  SELECT qa.id, qa.score, qa.total INTO v_attempt_id, v_score, v_total
  FROM public.quiz_attempts qa WHERE qa.user_id = p_user AND qa.client_request_id = p_request_id;
  IF FOUND THEN RETURN QUERY SELECT v_attempt_id, v_score, v_total, true; RETURN; END IF;

  INSERT INTO public.quiz_attempts (user_id, chapter_id, score, total, client_request_id)
  VALUES (p_user, p_chapter, p_score, p_total, p_request_id)
  ON CONFLICT (user_id, client_request_id) WHERE client_request_id IS NOT NULL DO NOTHING
  RETURNING id INTO v_attempt_id;
  IF v_attempt_id IS NULL THEN
    SELECT qa.id, qa.score, qa.total INTO v_attempt_id, v_score, v_total
    FROM public.quiz_attempts qa WHERE qa.user_id = p_user AND qa.client_request_id = p_request_id;
    RETURN QUERY SELECT v_attempt_id, v_score, v_total, true; RETURN;
  END IF;
  INSERT INTO public.quiz_answers (attempt_id, question_id, chosen_idx, is_correct)
  SELECT v_attempt_id, (answer.value->>'question_id')::uuid,
    (answer.value->>'chosen_idx')::integer, (answer.value->>'is_correct')::boolean
  FROM jsonb_array_elements(p_answers) AS answer(value);
  RETURN QUERY SELECT v_attempt_id, p_score, p_total, false;
END;
$$;
REVOKE ALL ON FUNCTION public.record_quiz_attempt(uuid, uuid, uuid, integer, integer, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_quiz_attempt(uuid, uuid, uuid, integer, integer, jsonb) TO service_role;

-- 8) Lembretes: deduplicar por usuário/evento/janela, e gravar notificação + claim
-- na mesma transação. Janela atualmente definida como 48 horas.
CREATE TABLE IF NOT EXISTS private.sent_reminders (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  meeting_id uuid NOT NULL REFERENCES public.meetings(id) ON DELETE CASCADE,
  reminder_window text NOT NULL CHECK (reminder_window IN ('48h')),
  sent_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  PRIMARY KEY (user_id, meeting_id, reminder_window)
);
REVOKE ALL ON TABLE private.sent_reminders FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE private.sent_reminders TO service_role;
CREATE INDEX IF NOT EXISTS sent_reminders_meeting_id_idx ON private.sent_reminders (meeting_id);
CREATE OR REPLACE FUNCTION public.deliver_meeting_reminder(p_user uuid, p_meeting uuid, p_window text DEFAULT '48h')
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE v_meeting public.meetings%ROWTYPE; v_claimed integer;
BEGIN
  IF p_window <> '48h' THEN RAISE EXCEPTION 'unsupported reminder window' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_meeting FROM public.meetings m WHERE m.id = p_meeting;
  IF NOT FOUND OR v_meeting.status <> 'scheduled'::public.meeting_status
      OR v_meeting.scheduled_at < statement_timestamp()
      OR v_meeting.scheduled_at > statement_timestamp() + interval '48 hours'
      OR NOT EXISTS (SELECT 1 FROM public.meeting_rsvps r
        WHERE r.meeting_id = p_meeting AND r.user_id = p_user AND r.attending) THEN
    RETURN false;
  END IF;
  INSERT INTO private.sent_reminders (user_id, meeting_id, reminder_window)
  VALUES (p_user, p_meeting, p_window) ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_claimed = ROW_COUNT;
  IF v_claimed = 0 THEN RETURN false; END IF;
  INSERT INTO public.notifications (user_id, kind, payload)
  VALUES (p_user, 'meeting_reminder'::public.notification_kind,
    jsonb_build_object('meeting_id', v_meeting.id, 'title', v_meeting.title, 'at', v_meeting.scheduled_at));
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.deliver_meeting_reminder(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.deliver_meeting_reminder(uuid, uuid, text) TO service_role;

-- 9) Newsletter: chave única por issue/audience, com lease recuperável após 24h.
CREATE TABLE IF NOT EXISTS private.newsletter_dispatch_runs (
  issue_id uuid NOT NULL REFERENCES public.newsletter_issues(id) ON DELETE CASCADE,
  audience_key text NOT NULL,
  started_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  completed_at timestamptz,
  PRIMARY KEY (issue_id, audience_key)
);
REVOKE ALL ON TABLE private.newsletter_dispatch_runs FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE private.newsletter_dispatch_runs TO service_role;
CREATE INDEX IF NOT EXISTS newsletter_dispatch_runs_issue_id_idx ON private.newsletter_dispatch_runs (issue_id);
CREATE OR REPLACE FUNCTION public.claim_newsletter_dispatch(p_issue uuid, p_audience_key text)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE v_rows integer;
BEGIN
  IF p_issue IS NULL OR p_audience_key IS NULL OR length(p_audience_key) NOT BETWEEN 1 AND 128 THEN
    RAISE EXCEPTION 'invalid newsletter dispatch key' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM public.newsletter_issues i WHERE i.id = p_issue AND i.sent_at IS NOT NULL) THEN
    RETURN false;
  END IF;
  INSERT INTO private.newsletter_dispatch_runs (issue_id, audience_key, started_at)
  VALUES (p_issue, p_audience_key, statement_timestamp())
  ON CONFLICT (issue_id, audience_key) DO UPDATE SET started_at = statement_timestamp()
    WHERE private.newsletter_dispatch_runs.completed_at IS NULL
      AND private.newsletter_dispatch_runs.started_at < statement_timestamp() - interval '24 hours';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows > 0;
END;
$$;
CREATE OR REPLACE FUNCTION public.finish_newsletter_dispatch(p_issue uuid, p_audience_key text, p_success boolean)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  UPDATE private.newsletter_dispatch_runs
     SET completed_at = CASE WHEN p_success THEN statement_timestamp() ELSE NULL END
   WHERE issue_id = p_issue AND audience_key = p_audience_key;
  IF p_success THEN
    UPDATE public.newsletter_issues SET sent_at = coalesce(sent_at, statement_timestamp()) WHERE id = p_issue;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.claim_newsletter_dispatch(uuid, text),
  public.finish_newsletter_dispatch(uuid, text, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_newsletter_dispatch(uuid, text),
  public.finish_newsletter_dispatch(uuid, text, boolean) TO service_role;

-- 10) Stripe: guardar relação de customer em schema privado e aplicar assinatura
-- antes de marcar evento; ambas as operações compartilham a transação do RPC.
CREATE TABLE IF NOT EXISTS private.stripe_customers (
  customer_id text PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp()
);
CREATE INDEX IF NOT EXISTS stripe_customers_user_id_idx ON private.stripe_customers (user_id);
REVOKE ALL ON TABLE private.stripe_customers FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE private.stripe_customers TO service_role;
CREATE OR REPLACE FUNCTION public.link_stripe_customer(p_customer_id text, p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE v_rows integer;
BEGIN
  IF p_customer_id IS NULL OR p_customer_id !~ '^cus_[A-Za-z0-9]+$' OR p_user IS NULL THEN
    RAISE EXCEPTION 'invalid Stripe customer mapping' USING ERRCODE = '22023';
  END IF;
  INSERT INTO private.stripe_customers (customer_id, user_id) VALUES (p_customer_id, p_user)
  ON CONFLICT (customer_id) DO UPDATE SET user_id = EXCLUDED.user_id
    WHERE private.stripe_customers.user_id = EXCLUDED.user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN RAISE EXCEPTION 'Stripe customer is already linked to another profile' USING ERRCODE = '23505'; END IF;
END;
$$;
CREATE OR REPLACE FUNCTION public.apply_stripe_subscription_event(
  p_event_id text, p_event_type text, p_customer_id text, p_metadata_user uuid,
  p_subscription_id text, p_plan_id uuid, p_status text,
  p_period_start timestamptz, p_period_end timestamptz,
  p_cancel_at_period_end boolean, p_payload jsonb
) RETURNS text LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE v_user uuid; v_rows integer;
BEGIN
  IF p_event_id IS NULL OR p_event_type IS NULL OR p_payload IS NULL THEN
    RAISE EXCEPTION 'invalid Stripe event payload' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('stripe:' || p_event_id, 0));
  IF EXISTS (SELECT 1 FROM public.payment_events pe
    WHERE pe.provider = 'stripe'::public.payment_provider AND pe.event_id = p_event_id) THEN
    RETURN 'duplicate';
  END IF;
  SELECT sc.user_id INTO v_user FROM private.stripe_customers sc WHERE sc.customer_id = p_customer_id;
  IF p_metadata_user IS NOT NULL THEN
    IF v_user IS NOT NULL AND v_user <> p_metadata_user THEN
      RAISE EXCEPTION 'Stripe customer metadata does not match stored mapping' USING ERRCODE = '23505';
    END IF;
    PERFORM public.link_stripe_customer(p_customer_id, p_metadata_user);
    v_user := p_metadata_user;
  END IF;
  IF p_event_type LIKE 'customer.subscription.%' THEN
    IF p_customer_id IS NULL OR v_user IS NULL OR p_subscription_id IS NULL
      OR p_plan_id IS NULL OR p_status IS NULL THEN
      RAISE EXCEPTION 'subscription event has no verified customer/profile/plan mapping' USING ERRCODE = '23502';
    END IF;
    INSERT INTO public.user_subscriptions (
      user_id, plan_id, status, provider, provider_customer_id, provider_subscription_id,
      current_period_start, current_period_end, cancel_at_period_end, updated_at
    ) VALUES (
      v_user, p_plan_id, p_status::public.subscription_status, 'stripe'::public.payment_provider,
      p_customer_id, p_subscription_id, p_period_start, p_period_end,
      coalesce(p_cancel_at_period_end, false), statement_timestamp()
    )
    ON CONFLICT (provider_subscription_id) DO UPDATE SET
      plan_id = EXCLUDED.plan_id, status = EXCLUDED.status,
      provider_customer_id = EXCLUDED.provider_customer_id,
      current_period_start = EXCLUDED.current_period_start,
      current_period_end = EXCLUDED.current_period_end,
      cancel_at_period_end = EXCLUDED.cancel_at_period_end,
      updated_at = statement_timestamp()
    WHERE public.user_subscriptions.user_id = EXCLUDED.user_id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows = 0 THEN RAISE EXCEPTION 'subscription is already associated with another profile' USING ERRCODE = '23505'; END IF;
  END IF;
  INSERT INTO public.payment_events (provider, event_id, event_type, user_id, payload, processed_at)
  VALUES ('stripe'::public.payment_provider, p_event_id, p_event_type, v_user, p_payload, statement_timestamp());
  RETURN 'processed';
END;
$$;
REVOKE ALL ON FUNCTION public.link_stripe_customer(text, uuid),
  public.apply_stripe_subscription_event(text, text, text, uuid, text, uuid, text, timestamptz, timestamptz, boolean, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.link_stripe_customer(text, uuid),
  public.apply_stripe_subscription_event(text, text, text, uuid, text, uuid, text, timestamptz, timestamptz, boolean, jsonb)
  TO service_role;

-- 11) Interseções de leitores reais sem expor IDs individuais de livros.
CREATE OR REPLACE FUNCTION public.get_reader_overlaps(p_user uuid, p_candidates uuid[])
RETURNS TABLE (matched_id uuid, shared_books integer, shared_moods public.mood_kind[])
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
  WITH candidates AS (
    SELECT DISTINCT candidate_id AS id FROM unnest(coalesce(p_candidates, ARRAY[]::uuid[])) AS candidate(candidate_id)
    WHERE candidate_id IS NOT NULL AND candidate_id <> p_user
  ), book_overlaps AS (
    SELECT other.user_id AS matched_id, count(DISTINCT season_a.book_id)::integer AS shared_books
    FROM candidates candidate
    JOIN public.user_progress mine ON mine.user_id = p_user AND mine.status = 'read'::public.shelf_status
    JOIN public.chapters chapter_a ON chapter_a.id = mine.chapter_id
    JOIN public.seasons season_a ON season_a.id = chapter_a.season_id
    JOIN public.user_progress other ON other.user_id = candidate.id AND other.status = 'read'::public.shelf_status
    JOIN public.chapters chapter_b ON chapter_b.id = other.chapter_id
    JOIN public.seasons season_b ON season_b.id = chapter_b.season_id AND season_b.book_id = season_a.book_id
    GROUP BY other.user_id
  ), mood_overlaps AS (
    SELECT candidate.id AS matched_id,
      coalesce(array_agg(DISTINCT mood.value ORDER BY mood.value), ARRAY[]::public.mood_kind[]) AS shared_moods
    FROM candidates candidate
    JOIN public.book_mood_votes mine ON mine.user_id = p_user
    JOIN public.book_mood_votes other ON other.user_id = candidate.id AND other.book_id = mine.book_id
    CROSS JOIN LATERAL unnest(mine.moods) AS mood(value)
    WHERE mood.value = ANY(other.moods)
    GROUP BY candidate.id
  )
  SELECT candidate.id, coalesce(books.shared_books, 0),
    coalesce(moods.shared_moods, ARRAY[]::public.mood_kind[])
  FROM candidates candidate
  LEFT JOIN book_overlaps books ON books.matched_id = candidate.id
  LEFT JOIN mood_overlaps moods ON moods.matched_id = candidate.id;
$$;
REVOKE ALL ON FUNCTION public.get_reader_overlaps(uuid, uuid[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_reader_overlaps(uuid, uuid[]) TO service_role;
