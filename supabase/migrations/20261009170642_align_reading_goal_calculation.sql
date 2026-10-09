-- O trigger continua privado e protegido; somente o corpo do cálculo é
-- alinhado ao contrato do anexo. A unidade books_done segue sendo a contagem
-- de linhas user_progress com status read, conforme o contrato literal.

CREATE OR REPLACE FUNCTION private.refresh_reading_goal_progress()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user uuid := COALESCE(NEW.user_id, OLD.user_id);
  v_year integer := EXTRACT(YEAR FROM CURRENT_DATE)::integer;
  v_goal uuid;
BEGIN
  SELECT rg.id
    INTO v_goal
    FROM public.reading_goals AS rg
   WHERE rg.user_id = v_user
     AND rg.year = v_year;

  IF v_goal IS NULL THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.reading_goal_progress (
    goal_id,
    books_done,
    pages_done,
    minutes_done,
    updated_at
  )
  SELECT
    v_goal,
    (
      SELECT COUNT(*)
        FROM public.user_progress AS up
       WHERE up.user_id = v_user
         AND up.status = 'read'::public.shelf_status
         AND up.finished_at >= make_date(v_year, 1, 1)
    ),
    (
      SELECT COALESCE(SUM(rje.page_to - rje.page_from), 0)
        FROM public.reading_journal_entries AS rje
       WHERE rje.user_id = v_user
         AND rje.entry_date >= make_date(v_year, 1, 1)
    ),
    (
      SELECT COALESCE(SUM(rje.minutes_read), 0)
        FROM public.reading_journal_entries AS rje
       WHERE rje.user_id = v_user
         AND rje.entry_date >= make_date(v_year, 1, 1)
    ),
    statement_timestamp()
  ON CONFLICT (goal_id) DO UPDATE
    SET books_done = EXCLUDED.books_done,
        pages_done = EXCLUDED.pages_done,
        minutes_done = EXCLUDED.minutes_done,
        updated_at = statement_timestamp();

  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION private.refresh_reading_goal_progress()
  FROM PUBLIC, anon, authenticated, service_role;
