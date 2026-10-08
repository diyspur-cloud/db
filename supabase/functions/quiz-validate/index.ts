import { serve } from "https://deno.land/std@0.200.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { cors } from "../_shared/cors.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MAX_QUESTIONS = 50;
const RATE_WINDOW_MS = 60_000;
const MAX_ATTEMPTS_PER_WINDOW = 10;

const json = (body: unknown, status = 200) =>
  cors(Response.json(body, { status }));

serve(async (req) => {
  if (req.method === "OPTIONS") return cors();
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.match(/^Bearer\s+(\S+)$/i)?.[1];
  if (!token) return json({ error: "unauthorized" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY")
    ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY")
    ?? Deno.env.get("SB_PUBLISHABLE_KEY");
  if (!supabaseUrl || !serviceRoleKey || !publicKey) {
    console.error("quiz-validate: required environment variables are missing");
    return json({ error: "server_misconfigured" }, 500);
  }

  // Validate the caller with a publishable key; never let a caller-supplied JWT
  // override the service-role client's authorization header.
  const authClient = createClient(supabaseUrl, publicKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await authClient.auth.getUser(token);
  if (authError || !authData.user) return json({ error: "unauthorized" }, 401);

  let payload: unknown;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  if (!payload || typeof payload !== "object") return json({ error: "invalid_payload" }, 400);
  const body = payload as { chapter_id?: unknown; answers?: unknown };
  if (typeof body.chapter_id !== "string" || !UUID_RE.test(body.chapter_id)
      || !Array.isArray(body.answers) || body.answers.length < 1
      || body.answers.length > MAX_QUESTIONS) {
    return json({ error: "invalid_payload" }, 400);
  }

  const service = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const userId = authData.user.id;
  const since = new Date(Date.now() - RATE_WINDOW_MS).toISOString();
  const { count, error: rateError } = await service
    .from("quiz_attempts")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("created_at", since);
  if (rateError) {
    console.error("quiz-validate: rate-limit query failed", rateError.message);
    return json({ error: "temporarily_unavailable" }, 503);
  }
  if ((count ?? 0) >= MAX_ATTEMPTS_PER_WINDOW) {
    return json({ error: "rate_limited", retry_after_seconds: 60 }, 429);
  }

  const { data: questions, error: questionsError } = await service
    .from("quiz_questions")
    .select("id, correct_idx, options")
    .eq("chapter_id", body.chapter_id)
    .order("position", { ascending: true })
    .limit(MAX_QUESTIONS);
  if (questionsError) {
    console.error("quiz-validate: question lookup failed", questionsError.message);
    return json({ error: "temporarily_unavailable" }, 503);
  }
  if (!questions?.length) return json({ error: "quiz_not_found" }, 404);
  if (questions.length > MAX_QUESTIONS) return json({ error: "quiz_too_large" }, 422);

  const answers = body.answers as Array<{ question_id?: unknown; chosen_idx?: unknown }>;
  const answersByQuestion = new Map<string, number>();
  for (const answer of answers) {
    if (!answer || typeof answer.question_id !== "string"
        || !UUID_RE.test(answer.question_id)
        || !Number.isInteger(answer.chosen_idx)
        || answersByQuestion.has(answer.question_id)) {
      return json({ error: "invalid_answers" }, 400);
    }
    answersByQuestion.set(answer.question_id, answer.chosen_idx as number);
  }
  if (answersByQuestion.size !== questions.length
      || questions.some((question) => !answersByQuestion.has(question.id))) {
    return json({ error: "incomplete_or_unexpected_answers" }, 400);
  }

  let score = 0;
  const detail = [] as Array<{ question_id: string; chosen_idx: number; is_correct: boolean }>;
  for (const question of questions) {
    const chosenIdx = answersByQuestion.get(question.id)!;
    const optionCount = Array.isArray(question.options) ? question.options.length : 0;
    if (optionCount < 1 || !Number.isInteger(question.correct_idx)
        || question.correct_idx < 0 || question.correct_idx >= optionCount
        || chosenIdx < 0 || chosenIdx >= optionCount) {
      return json({ error: "invalid_quiz_configuration_or_answer" }, 422);
    }
    const isCorrect = chosenIdx === question.correct_idx;
    if (isCorrect) score++;
    detail.push({ question_id: question.id, chosen_idx: chosenIdx, is_correct: isCorrect });
  }

  const { data: attempt, error: attemptError } = await service
    .from("quiz_attempts")
    .insert({ user_id: userId, chapter_id: body.chapter_id, score, total: questions.length })
    .select("id")
    .single();
  if (attemptError || !attempt) {
    console.error("quiz-validate: attempt insert failed", attemptError?.message);
    return json({ error: "could_not_record_attempt" }, 500);
  }

  const { error: answersError } = await service.from("quiz_answers").insert(
    detail.map((answer) => ({ ...answer, attempt_id: attempt.id })),
  );
  if (answersError) {
    console.error("quiz-validate: answers insert failed", answersError.message);
    const { error: cleanupError } = await service.from("quiz_attempts")
      .delete().eq("id", attempt.id).eq("user_id", userId);
    if (cleanupError) console.error("quiz-validate: orphan attempt cleanup failed", cleanupError.message);
    return json({ error: "could_not_record_attempt" }, 500);
  }

  const { error: xpError } = await service.rpc("award_xp", {
    p_user: userId,
    p_source: "quiz_answer",
    p_amount: 50,
    p_ref: attempt.id,
  });
  if (xpError) console.error("quiz-validate: XP award failed", xpError.message);

  return json({ score, total: questions.length, detail });
});
