import type { Database } from "./database.types";
import { supabase } from "./client";

export type PublicQuizQuestion =
  Database["public"]["Views"]["v_quiz_questions_public"]["Row"];
export type QuizAnswerInput = {
  question_id: string;
  chosen_idx: number;
};
export type QuizAttemptResult = {
  attempt_id: string;
  score: number;
  total: number;
  detail: Array<QuizAnswerInput & { is_correct: boolean }>;
  duplicate: boolean;
};

export async function getPublicQuiz(chapterId: string) {
  const { data, error } = await supabase
    .from("v_quiz_questions_public")
    .select("id,chapter_id,position,question,options")
    .eq("chapter_id", chapterId)
    .order("position", { ascending: true });
  if (error) throw error;
  return (data ?? []) as PublicQuizQuestion[];
}

export async function validateQuiz(
  chapterId: string,
  answers: QuizAnswerInput[],
  requestId = crypto.randomUUID(),
): Promise<QuizAttemptResult> {
  const { data, error } = await supabase.functions.invoke("quiz-validate", {
    body: { chapter_id: chapterId, answers, request_id: requestId },
    headers: { "Idempotency-Key": requestId },
  });
  if (error) throw error;
  return data as QuizAttemptResult;
}
