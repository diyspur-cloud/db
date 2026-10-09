-- O contrato original persiste -1 para uma pergunta sem resposta.
-- A função continua service-role-only e valida a resposta completa no banco.

ALTER TABLE public.quiz_answers
  DROP CONSTRAINT IF EXISTS quiz_answers_chosen_idx_nonnegative_check;

ALTER TABLE public.quiz_answers
  ADD CONSTRAINT quiz_answers_chosen_idx_original_check
  CHECK (chosen_idx >= -1);

CREATE OR REPLACE FUNCTION public.record_quiz_attempt(
  p_user uuid,
  p_chapter uuid,
  p_request_id uuid,
  p_score integer,
  p_total integer,
  p_answers jsonb
)
RETURNS TABLE (
  attempt_id uuid,
  score integer,
  total integer,
  duplicate boolean
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_attempt_id uuid;
  v_attempt_chapter uuid;
  v_score integer;
  v_total integer;
  v_expected_answers jsonb;
  v_stored_answers jsonb;
BEGIN
  IF p_user IS NULL
     OR p_chapter IS NULL
     OR p_request_id IS NULL
     OR p_total IS NULL
     OR p_total < 1
     OR p_score IS NULL
     OR p_score < 0
     OR p_score > p_total
     OR p_answers IS NULL
     OR jsonb_typeof(p_answers) <> 'array'
     OR jsonb_array_length(p_answers) <> p_total THEN
    RAISE EXCEPTION 'invalid quiz attempt payload' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM jsonb_array_elements(p_answers) AS answer(value)
     WHERE (answer.value->>'question_id') IS NULL
        OR (answer.value->>'chosen_idx') IS NULL
        OR (answer.value->>'is_correct') IS NULL
        OR NOT EXISTS (
          SELECT 1
            FROM public.quiz_questions AS q
           WHERE q.id = (answer.value->>'question_id')::uuid
             AND q.chapter_id = p_chapter
        )
  ) THEN
    RAISE EXCEPTION 'quiz answer does not belong to chapter' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM jsonb_array_elements(p_answers) AS answer(value)
      JOIN public.quiz_questions AS q
        ON q.id = (answer.value->>'question_id')::uuid
     WHERE q.chapter_id = p_chapter
       AND (
         (answer.value->>'chosen_idx')::integer < -1
         OR (answer.value->>'chosen_idx')::integer >= jsonb_array_length(q.options)
         OR (answer.value->>'is_correct')::boolean IS DISTINCT FROM (
           (answer.value->>'chosen_idx')::integer >= 0
           AND (answer.value->>'chosen_idx')::integer = q.correct_idx
         )
       )
  ) THEN
    RAISE EXCEPTION 'quiz answer is outside the configured options' USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'question_id', answer.question_id,
        'chosen_idx', answer.chosen_idx
      )
      ORDER BY answer.question_id, answer.chosen_idx
    ),
    '[]'::jsonb
  )
    INTO v_expected_answers
    FROM (
      SELECT
        (answer.value->>'question_id')::uuid AS question_id,
        (answer.value->>'chosen_idx')::integer AS chosen_idx
        FROM jsonb_array_elements(p_answers) AS answer(value)
    ) AS answer;

  SELECT qa.id, qa.chapter_id, qa.score, qa.total
    INTO v_attempt_id, v_attempt_chapter, v_score, v_total
    FROM public.quiz_attempts AS qa
   WHERE qa.user_id = p_user
     AND qa.client_request_id = p_request_id
   FOR UPDATE;

  IF FOUND THEN
    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'question_id', answer.question_id,
          'chosen_idx', answer.chosen_idx
        )
        ORDER BY answer.question_id, answer.chosen_idx
      ),
      '[]'::jsonb
    )
      INTO v_stored_answers
      FROM public.quiz_answers AS answer
     WHERE answer.attempt_id = v_attempt_id;

    IF v_attempt_chapter IS DISTINCT FROM p_chapter
       OR v_stored_answers IS DISTINCT FROM v_expected_answers THEN
      RAISE EXCEPTION 'idempotency key conflicts with existing quiz attempt'
        USING ERRCODE = '22023';
    END IF;

    RETURN QUERY SELECT v_attempt_id, v_score, v_total, true;
    RETURN;
  END IF;

  INSERT INTO public.quiz_attempts (
    user_id,
    chapter_id,
    score,
    total,
    client_request_id
  )
  VALUES (p_user, p_chapter, p_score, p_total, p_request_id)
  ON CONFLICT (user_id, client_request_id)
    WHERE client_request_id IS NOT NULL
  DO NOTHING
  RETURNING id INTO v_attempt_id;

  IF v_attempt_id IS NULL THEN
    SELECT qa.id, qa.chapter_id, qa.score, qa.total
      INTO v_attempt_id, v_attempt_chapter, v_score, v_total
      FROM public.quiz_attempts AS qa
     WHERE qa.user_id = p_user
       AND qa.client_request_id = p_request_id
     FOR UPDATE;

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'question_id', answer.question_id,
          'chosen_idx', answer.chosen_idx
        )
        ORDER BY answer.question_id, answer.chosen_idx
      ),
      '[]'::jsonb
    )
      INTO v_stored_answers
      FROM public.quiz_answers AS answer
     WHERE answer.attempt_id = v_attempt_id;

    IF v_attempt_chapter IS DISTINCT FROM p_chapter
       OR v_stored_answers IS DISTINCT FROM v_expected_answers THEN
      RAISE EXCEPTION 'idempotency key conflicts with existing quiz attempt'
        USING ERRCODE = '22023';
    END IF;

    RETURN QUERY SELECT v_attempt_id, v_score, v_total, true;
    RETURN;
  END IF;

  INSERT INTO public.quiz_answers (attempt_id, question_id, chosen_idx, is_correct)
  SELECT
    v_attempt_id,
    (answer.value->>'question_id')::uuid,
    (answer.value->>'chosen_idx')::integer,
    (answer.value->>'is_correct')::boolean
    FROM jsonb_array_elements(p_answers) AS answer(value);

  RETURN QUERY SELECT v_attempt_id, p_score, p_total, false;
END;
$$;

REVOKE ALL ON FUNCTION public.record_quiz_attempt(uuid, uuid, uuid, integer, integer, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_quiz_attempt(uuid, uuid, uuid, integer, integer, jsonb)
  TO service_role;
