-- O contrato do anexo chama de books_* as linhas de progresso por capítulo.
-- A view permanece security_invoker; o significado por livro do baseline fica
-- substituído explicitamente nesta migration, sem criar book_progress persistido.

CREATE OR REPLACE VIEW public.v_user_reading_overview
WITH (security_invoker = true)
AS
SELECT
  p.id AS user_id,
  COUNT(DISTINCT up.id) FILTER (WHERE up.status = 'read'::public.shelf_status)
    AS books_read,
  COUNT(DISTINCT up.id) FILTER (WHERE up.status = 'reading'::public.shelf_status)
    AS books_reading,
  COUNT(DISTINCT up.id) FILTER (WHERE up.status = 'want_to_read'::public.shelf_status)
    AS books_want,
  COUNT(DISTINCT up.id) FILTER (WHERE up.status = 'dnf'::public.shelf_status)
    AS books_dnf,
  COALESCE(SUM(rje.minutes_read), 0) AS total_minutes,
  COALESCE(COUNT(DISTINCT rje.entry_date), 0) AS reading_days,
  COALESCE(
    SUM(CASE WHEN rje.entry_date = CURRENT_DATE THEN 1 ELSE 0 END),
    0
  ) AS read_today
FROM public.profiles AS p
LEFT JOIN public.user_progress AS up
  ON up.user_id = p.id
LEFT JOIN public.reading_journal_entries AS rje
  ON rje.user_id = p.id
GROUP BY p.id;

GRANT SELECT ON public.v_user_reading_overview
  TO anon, authenticated, service_role;
