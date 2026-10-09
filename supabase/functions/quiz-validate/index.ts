import { cors } from "../_shared/cors.ts";
import { json, requestUser, serviceClient, UUID_RE } from "../_shared/auth.ts";

const MAX_QUESTIONS = 50;

type AnswerInput = { question_id: string; chosen_idx: number };
function parseAnswers(value: unknown): AnswerInput[] | null {
  if (
    !Array.isArray(value) || value.length < 1 || value.length > MAX_QUESTIONS
  ) return null;
  const seen = new Set<string>();
  const result: AnswerInput[] = [];
  for (const item of value) {
    if (!item || typeof item !== "object") return null;
    const answer = item as Record<string, unknown>;
    if (
      typeof answer.question_id !== "string" ||
      !UUID_RE.test(answer.question_id) ||
      !Number.isInteger(answer.chosen_idx) || seen.has(answer.question_id)
    ) return null;
    seen.add(answer.question_id);
    result.push({
      question_id: answer.question_id,
      chosen_idx: answer.chosen_idx as number,
    });
  }
  return result;
}

async function finishExisting(
  service: ReturnType<typeof serviceClient>,
  userId: string,
  requestId: string,
) {
  const { data: attempt, error } = await service.from("quiz_attempts")
    .select("id,score,total").eq("user_id", userId).eq(
      "client_request_id",
      requestId,
    ).maybeSingle();
  if (error || !attempt) return null;
  const { data: answers } = await service.from("quiz_answers")
    .select("question_id,chosen_idx,is_correct").eq("attempt_id", attempt.id);
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
    const requestId = req.headers.get("Idempotency-Key") ?? payload.request_id;
    const answers = parseAnswers(payload.answers);
    if (
      typeof chapterId !== "string" || !UUID_RE.test(chapterId) ||
      typeof requestId !== "string" || !UUID_RE.test(requestId) || !answers
    ) {
      return json({ error: "invalid_payload_or_missing_idempotency_key" }, 400);
    }
    const service = serviceClient();
    const existing = await finishExisting(service, user.id, requestId);
    if (existing) return existing.response;

    // Publicly available chapter access is defined by an active/finished season;
    // future-scheduled chapters remain inaccessible until their publish timestamp.
    const { data: chapter, error: chapterError } = await service.from(
      "chapters",
    )
      .select("id,season_id,published_at").eq("id", chapterId).maybeSingle();
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
      const racedDuplicate = await finishExisting(service, user.id, requestId);
      if (racedDuplicate) return racedDuplicate.response;
      return json({ error: "rate_limited", retry_after_seconds: 60 }, 429);
    }

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
    const answerMap = new Map(
      answers.map((answer) => [answer.question_id, answer.chosen_idx]),
    );
    if (
      answers.length !== questions.length ||
      questions.some((question) => !answerMap.has(question.id))
    ) {
      return json({ error: "incomplete_or_unexpected_answers" }, 400);
    }
    let score = 0;
    const details: Array<
      { question_id: string; chosen_idx: number; is_correct: boolean }
    > = [];
    for (const question of questions) {
      const chosen = answerMap.get(question.id)!;
      const options = Array.isArray(question.options)
        ? question.options.length
        : 0;
      if (
        options < 1 || !Number.isInteger(question.correct_idx) ||
        question.correct_idx < 0 ||
        question.correct_idx >= options || chosen < 0 || chosen >= options
      ) {
        return json({ error: "invalid_quiz_configuration_or_answer" }, 422);
      }
      const isCorrect = chosen === question.correct_idx;
      if (isCorrect) score++;
      details.push({
        question_id: question.id,
        chosen_idx: chosen,
        is_correct: isCorrect,
      });
    }
    const { data: recorded, error: recordError } = await service.rpc(
      "record_quiz_attempt",
      {
        p_user: user.id,
        p_chapter: chapterId,
        p_request_id: requestId,
        p_score: score,
        p_total: questions.length,
        p_answers: details,
      },
    );
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
      detail: details,
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
