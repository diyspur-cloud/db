CREATE OR REPLACE VIEW public.v_user_reading_overview
WITH (security_invoker = true)
AS
WITH book_progress AS (
  SELECT up.user_id,
         b.id AS book_id,
         COALESCE(NULLIF(b.total_chapters, 0), COUNT(DISTINCT c.id)) AS required_chapters,
         COUNT(DISTINCT c.id) FILTER (WHERE up.status = 'read') AS completed_chapters,
         BOOL_OR(up.status = 'reading') AS has_reading,
         BOOL_OR(up.status = 'want_to_read') AS has_want,
         BOOL_OR(up.status = 'dnf') AS has_dnf
    FROM public.user_progress AS up
    JOIN public.chapters AS c ON c.id = up.chapter_id
    JOIN public.seasons AS s ON s.id = c.season_id
    JOIN public.books AS b ON b.id = s.book_id
   GROUP BY up.user_id, b.id, b.total_chapters
), progress_summary AS (
  SELECT user_id,
         COUNT(*) FILTER (WHERE completed_chapters >= required_chapters AND required_chapters > 0) AS books_read,
         COUNT(*) FILTER (WHERE NOT (completed_chapters >= required_chapters AND required_chapters > 0) AND (has_reading OR completed_chapters > 0)) AS books_reading,
         COUNT(*) FILTER (WHERE has_want AND NOT has_reading AND completed_chapters = 0 AND NOT has_dnf) AS books_want,
         COUNT(*) FILTER (WHERE has_dnf) AS books_dnf
    FROM book_progress
   GROUP BY user_id
), journal_summary AS (
  SELECT user_id,
         COALESCE(SUM(minutes_read), 0) AS total_minutes,
         COUNT(DISTINCT entry_date) AS reading_days,
         COUNT(*) FILTER (WHERE entry_date = CURRENT_DATE) AS read_today
    FROM public.reading_journal_entries
   GROUP BY user_id
)
SELECT p.id AS user_id,
       COALESCE(ps.books_read, 0) AS books_read,
       COALESCE(ps.books_reading, 0) AS books_reading,
       COALESCE(ps.books_want, 0) AS books_want,
       COALESCE(ps.books_dnf, 0) AS books_dnf,
       COALESCE(js.total_minutes, 0) AS total_minutes,
       COALESCE(js.reading_days, 0) AS reading_days,
       COALESCE(js.read_today, 0) AS read_today
  FROM public.profiles AS p
  LEFT JOIN progress_summary AS ps ON ps.user_id = p.id
  LEFT JOIN journal_summary AS js ON js.user_id = p.id;
