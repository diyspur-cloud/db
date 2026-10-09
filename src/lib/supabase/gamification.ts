import { supabase } from "./client";

export async function voteNextBook(pollId: string, optionId: string) {
  const { data, error } = await supabase.functions.invoke("vote-next-book", {
    body: { poll_id: pollId, option_id: optionId },
  });
  if (error) throw error;
  return data as { ok: true; votes: unknown };
}

export async function awardVerifiedXp(
  source:
    | "join_meeting"
    | "finish_chapter"
    | "comment"
    | "quiz_answer"
    | "finish_book",
  refId: string,
) {
  const { data, error } = await supabase.functions.invoke("award-xp", {
    body: { source, ref_id: refId },
  });
  if (error) throw error;
  return data as { ok: true; amount: number; duplicate?: boolean };
}

export async function awardDailyStreakBonus() {
  const { data, error } = await supabase.functions.invoke("award-xp", {
    body: { source: "streak_bonus" },
  });
  if (error) throw error;
  return data as { ok: true; amount: 25; duplicate?: boolean };
}
