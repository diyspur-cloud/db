BEGIN;

DO $$
DECLARE
  v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM public.authors
   WHERE id = '11111111-1111-1111-1111-111111111111';
  IF v_count <> 1 THEN RAISE EXCEPTION 'seed author count is %, expected 1', v_count; END IF;

  SELECT count(*) INTO v_count FROM public.books
   WHERE id = '22222222-2222-2222-2222-222222222222';
  IF v_count <> 1 THEN RAISE EXCEPTION 'seed book count is %, expected 1', v_count; END IF;

  SELECT count(*) INTO v_count FROM public.seasons
   WHERE id = '33333333-3333-3333-3333-333333333333';
  IF v_count <> 1 THEN RAISE EXCEPTION 'seed season count is %, expected 1', v_count; END IF;

  SELECT count(*) INTO v_count FROM public.chapters
   WHERE season_id = '33333333-3333-3333-3333-333333333333';
  IF v_count <> 5 THEN RAISE EXCEPTION 'seed chapter count is %, expected 5', v_count; END IF;

  SELECT count(*) INTO v_count FROM public.quiz_questions q
   JOIN public.chapters c ON c.id = q.chapter_id
   WHERE c.season_id = '33333333-3333-3333-3333-333333333333';
  IF v_count <> 1 THEN RAISE EXCEPTION 'seed quiz count is %, expected 1', v_count; END IF;

  SELECT count(*) INTO v_count FROM public.host_prompts hp
   JOIN public.chapters c ON c.id = hp.chapter_id
   WHERE c.season_id = '33333333-3333-3333-3333-333333333333';
  IF v_count <> 1 THEN RAISE EXCEPTION 'seed host prompt count is %, expected 1', v_count; END IF;

  SELECT count(*) INTO v_count FROM public.content_warnings;
  IF v_count < 10 THEN RAISE EXCEPTION 'content warning count is %, expected at least 10', v_count; END IF;

  SELECT count(*) INTO v_count FROM public.chapter_extra_content x
   JOIN public.chapters c ON c.id = x.chapter_id
   WHERE c.season_id = '33333333-3333-3333-3333-333333333333';
  IF v_count <> 2 THEN RAISE EXCEPTION 'extra content count is %, expected 2', v_count; END IF;

  SELECT count(*) INTO v_count FROM public.chapter_activities a
   JOIN public.chapters c ON c.id = a.chapter_id
   WHERE c.season_id = '33333333-3333-3333-3333-333333333333';
  IF v_count <> 1 THEN RAISE EXCEPTION 'chapter activity count is %, expected 1', v_count; END IF;

  SELECT count(*) INTO v_count FROM public.chapter_prompts p
   JOIN public.chapters c ON c.id = p.chapter_id
   WHERE c.season_id = '33333333-3333-3333-3333-333333333333';
  IF v_count <> 1 THEN RAISE EXCEPTION 'chapter prompt count is %, expected 1', v_count; END IF;

  SELECT count(*) INTO v_count FROM public.membership_plans;
  IF v_count <> 4 THEN RAISE EXCEPTION 'membership plan count is %, expected 4', v_count; END IF;

  SELECT count(*) INTO v_count FROM public.newsletter_issues
   WHERE slug = 'boas-vindas-t1';
  IF v_count <> 1 THEN RAISE EXCEPTION 'newsletter issue count is %, expected 1', v_count; END IF;
END;
$$;

COMMIT;
SELECT 'PASS: explicit double seed validation' AS result;
