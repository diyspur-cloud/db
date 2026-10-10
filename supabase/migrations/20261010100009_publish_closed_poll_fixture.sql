DO $$
DECLARE
  v_poll uuid;
  v_book uuid;
  v_option uuid;
  v_user uuid;
BEGIN
  SELECT id INTO v_book FROM public.books WHERE slug = 'verity' LIMIT 1;
  IF v_book IS NULL THEN RETURN; END IF;

  SELECT id INTO v_poll
    FROM public.book_polls
   WHERE title = 'Qual leitura vem depois de Verity?'
   LIMIT 1;

  IF v_poll IS NULL THEN
    INSERT INTO public.book_polls (season_id, title, opens_at, closes_at, status)
    SELECT s.id,
           'Qual leitura vem depois de Verity?',
           '2026-10-01T00:00:00Z'::timestamptz,
           '2026-10-07T00:00:00Z'::timestamptz,
           'closed'
      FROM public.seasons AS s
     WHERE s.slug = 't1-verity'
    RETURNING id INTO v_poll;
  END IF;

  IF v_poll IS NULL THEN RETURN; END IF;

  INSERT INTO public.book_poll_options (poll_id, book_id, proposal)
  VALUES (v_poll, v_book, 'Continuar com suspense')
  ON CONFLICT (poll_id, book_id) DO NOTHING;

  SELECT id INTO v_option
    FROM public.book_poll_options
   WHERE poll_id = v_poll
   ORDER BY id
   LIMIT 1;
  SELECT id INTO v_user FROM auth.users WHERE email = 'qa.diyspur.20261010@example.com' LIMIT 1;

  IF v_user IS NOT NULL AND v_option IS NOT NULL THEN
    INSERT INTO public.book_poll_votes (poll_id, option_id, user_id)
    VALUES (v_poll, v_option, v_user)
    ON CONFLICT DO NOTHING;
  END IF;
END $$;
