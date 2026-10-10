import { cors } from "../_shared/cors.ts";
import { json, requestUser, serviceClient, UUID_RE } from "../_shared/auth.ts";

const MAX_QUESTIONS = 50;

type AnswerInput = { question_id: string; chosen_idx: number };
type QuizQuestion = {
  id: string;
  correct_idx: number;
  options: unknown;
};
type QuizDetail = AnswerInput & { is_correct: boolean };

function parseAnswers(value: unknown): AnswerInput[] | null {
  // Array vazio significa que nenhuma pergunta foi respondida.
  if (!Array.isArray(value) || value.length > MAX_QUESTIONS) return null;
  const seen = new Set<string>();
  const result: AnswerInput[] = [];
  for (const item of value) {
    if (!item || typeof item !== "object") return null;
    const answer = item as Record<string, unknown>;
    if (
      typeof answer.question_id !== "string" ||
      !UUID_RE.test(answer.question_id) ||
      !Number.isInteger(answer.chosen_idx) ||
      seen.has(answer.question_id)
    ) return null;
    seen.add(answer.question_id);
    result.push({
      question_id: answer.question_id,
      chosen_idx: answer.chosen_idx as number,
    });
  }
  return result;
}

function canonicalAnswers(
  answers: ReadonlyArray<{ question_id: string; chosen_idx: number }>,
): string {
  return JSON.stringify(
    [...answers]
      .sort((left, right) => {
        if (left.question_id < right.question_id) return -1;
        if (left.question_id > right.question_id) return 1;
        return left.chosen_idx - right.chosen_idx;
      })
      .map(({ question_id, chosen_idx }) => ({ question_id, chosen_idx })),
  );
}

function buildDetails(
  questions: QuizQuestion[],
  answers: AnswerInput[],
): { normalized: AnswerInput[]; details: QuizDetail[] } | {
  error: "unexpected_answers" | "incomplete_answers" | "invalid_quiz_configuration_or_answer";
} {
  const questionIds = new Set(questions.map((question) => question.id));
  if (answers.length !== questions.length) {
    return { error: "incomplete_answers" };
  }
  if (answers.some((answer) => !questionIds.has(answer.question_id))) {
    return { error: "unexpected_answers" };
  }
  const answerMap = new Map(
    answers.map((answer) => [answer.question_id, answer.chosen_idx]),
  );
  const normalized: AnswerInput[] = [];
  const details: QuizDetail[] = [];
  for (const question of questions) {
    const chosen = answerMap.get(question.id) ?? -1;
    const options = Array.isArray(question.options)
      ? question.options.length
      : 0;
    if (
      options < 1 || !Number.isInteger(question.correct_idx) ||
      question.correct_idx < 0 || question.correct_idx >= options ||
      chosen < -1 || chosen >= options
    ) {
      return { error: "invalid_quiz_configuration_or_answer" };
    }
    const isCorrect = chosen >= 0 && chosen === question.correct_idx;
    const normalizedAnswer = { question_id: question.id, chosen_idx: chosen };
    normalized.push(normalizedAnswer);
    details.push({ ...normalizedAnswer, is_correct: isCorrect });
  }
  return { normalized, details };
}

async function finishExisting(
  service: ReturnType<typeof serviceClient>,
  userId: string,
  requestId: string,
  chapterId: string,
  expectedAnswers: AnswerInput[],
) {
  const { data: attempt, error } = await service.from("quiz_attempts")
    .select("id,chapter_id,score,total").eq("user_id", userId).eq(
      "client_request_id",
      requestId,
    ).maybeSingle();
  if (error) {
    return { response: json({ error: "temporarily_unavailable" }, 503) };
  }
  if (!attempt) return null;
  const { data: answers, error: answersError } = await service.from(
    "quiz_answers",
  )
    .select("question_id,chosen_idx,is_correct").eq("attempt_id", attempt.id);
  if (answersError) {
    return { response: json({ error: "temporarily_unavailable" }, 503) };
  }
  const actualAnswers = (answers ?? []).map((answer) => ({
    question_id: answer.question_id,
    chosen_idx: answer.chosen_idx,
  }));
  if (
    attempt.chapter_id !== chapterId ||
    canonicalAnswers(actualAnswers) !== canonicalAnswers(expectedAnswers)
  ) {
    return {
      response: json({ error: "idempotency_key_conflict" }, 409),
    };
  }
  const { error: xpError } = await service.rpc("award_xp", {
    p_user: userId,
    p_source: "quiz_answer",
    p_amount: 50,
    p_ref: attempt.id,
  });
  if (xpError) {
    return {
      response: json(
        { error: "xp_award_pending", attempt_id: attempt.id },
        503,
      ),
    };
  }
  return {
    response: json({
      attempt_id: attempt.id,
      score: attempt.score,
      total: attempt.total,
      detail: answers ?? [],
      duplicate: true,
    }),
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return cors();
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const user = await requestUser(req);
    if (!user) return json({ error: "unauthorized" }, 401);
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return json({ error: "invalid_json" }, 400);
    }
    if (!body || typeof body !== "object") {
      return json({ error: "invalid_payload" }, 400);
    }
    const payload = body as Record<string, unknown>;
    if (payload.user_id !== undefined && payload.user_id !== user.id) {
      return json({ error: "forbidden" }, 403);
    }
    const chapterId = payload.chapter_id;
    const suppliedRequestId = req.headers.has("Idempotency-Key")
      ? req.headers.get("Idempotency-Key")
      : payload.request_id;
    // Sem chave explícita, a chamada continua compatível, mas não há
    // identidade persistida para retries posteriores.
    const requestId = suppliedRequestId === undefined
      ? crypto.randomUUID()
      : suppliedRequestId;
    const answers = parseAnswers(payload.answers);
    if (
      typeof chapterId !== "string" || !UUID_RE.test(chapterId) ||
      typeof requestId !== "string" || !UUID_RE.test(requestId) || !answers
    ) {
      return json({ error: "invalid_payload" }, 400);
    }

    const service = serviceClient();
    const { data: questions, error: questionsError } = await service.from(
      "quiz_questions",
    )
      .select("id,correct_idx,options").eq("chapter_id", chapterId).order(
        "position",
      ).limit(MAX_QUESTIONS + 1);
    if (questionsError) return json({ error: "temporarily_unavailable" }, 503);
    if (!questions?.length) return json({ error: "quiz_not_found" }, 404);
    if (questions.length > MAX_QUESTIONS) {
      return json({ error: "quiz_too_large" }, 422);
    }
    const built = buildDetails(questions as QuizQuestion[], answers);
    if ("error" in built) {
      return json(
        {
          error: built.error === "unexpected_answers"
            ? "unexpected_answers"
            : built.error === "incomplete_answers"
            ? "incomplete_answers"
            : built.error,
        },
        built.error === "unexpected_answers" ? 400 : 422,
      );
    }

    const existing = await finishExisting(
      service,
      user.id,
      requestId,
      chapterId,
      built.normalized,
    );
    if (existing) return existing.response;

    // Capítulo futuro e temporadas não publicadas não aceitam novas tentativas.
    const { data: chapter, error: chapterError } = await service.from(
      "chapters",
    )
      .select("id,season_id,number,published_at").eq("id", chapterId).maybeSingle();
    if (chapterError) return json({ error: "temporarily_unavailable" }, 503);
    if (!chapter) return json({ error: "chapter_not_found" }, 404);
    if (chapter.published_at && Date.parse(chapter.published_at) > Date.now()) {
      return json({ error: "chapter_not_available" }, 403);
    }
    const { data: season, error: seasonError } = await service.from("seasons")
      .select("status").eq("id", chapter.season_id).maybeSingle();
    if (seasonError) return json({ error: "temporarily_unavailable" }, 503);
    if (!season || !["active", "finished"].includes(season.status)) {
      return json({ error: "chapter_not_available" }, 403);
    }

    // The service client bypasses RLS, so the Edge Function repeats the
    // previous-quiz gate using the identity verified from the bearer token.
    if (chapter.number > 1) {
      const { data: previous, error: previousError } = await service
        .from("chapters")
        .select("id")
        .eq("season_id", chapter.season_id)
        .eq("number", chapter.number - 1)
        .maybeSingle();
      if (previousError) return json({ error: "temporarily_unavailable" }, 503);
      if (!previous) return json({ error: "chapter_not_available" }, 403);
      const { data: previousAttempt, error: previousAttemptError } = await service
        .from("quiz_attempts")
        .select("id")
        .eq("user_id", user.id)
        .eq("chapter_id", previous.id)
        .limit(1)
        .maybeSingle();
      if (previousAttemptError) return json({ error: "temporarily_unavailable" }, 503);
      if (!previousAttempt) return json({ error: "previous_quiz_required" }, 403);
    }

    const { data: allowed, error: rateError } = await service.rpc(
      "consume_quiz_rate_limit",
      {
        p_user: user.id,
        p_chapter: chapterId,
      },
    );
    if (rateError) {
      console.error(
        "quiz-validate: atomic rate limit failed",
        rateError.message,
      );
      return json({ error: "temporarily_unavailable" }, 503);
    }
    if (allowed !== true) {
      const racedDuplicate = await finishExisting(
        service,
        user.id,
        requestId,
        chapterId,
        built.normalized,
      );
      if (racedDuplicate) return racedDuplicate.response;
      return json({ error: "rate_limited", retry_after_seconds: 60 }, 429);
    }

    const { data: recorded, error: recordError } = await service.rpc(
      "record_quiz_attempt",
      {
        p_user: user.id,
        p_chapter: chapterId,
        p_request_id: requestId,
        p_score: built.details.filter((detail) => detail.is_correct).length,
        p_total: questions.length,
        p_answers: built.details,
      },
    );
    if (recordError?.code === "22023") {
      return json({ error: "idempotency_key_conflict" }, 409);
    }
    if (recordError || !recorded?.length) {
      console.error(
        "quiz-validate: atomic record failed",
        recordError?.message,
      );
      return json({ error: "could_not_record_attempt" }, 503);
    }
    const attempt = recorded[0];
    const { error: xpError } = await service.rpc("award_xp", {
      p_user: user.id,
      p_source: "quiz_answer",
      p_amount: 50,
      p_ref: attempt.attempt_id,
    });
    if (xpError) {
      console.error(
        "quiz-validate: idempotent XP award failed",
        xpError.message,
      );
      return json(
        { error: "xp_award_pending", attempt_id: attempt.attempt_id },
        503,
      );
    }
    return json({
      attempt_id: attempt.attempt_id,
      score: attempt.score,
      total: attempt.total,
      detail: built.details,
      duplicate: attempt.duplicate,
    });
  } catch (error) {
    console.error(
      "quiz-validate: request failed",
      error instanceof Error ? error.message : "unknown",
    );
    return json({ error: "server_misconfigured_or_unavailable" }, 503);
  }
});
