import { serve } from "https://deno.land/std@0.200.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { cors } from "../_shared/cors.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return cors();

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(
    supabaseUrl,
    serviceRoleKey,
    { global: { headers: { Authorization: req.headers.get("Authorization")! } } },
  );
  // A request-scoped client respeita o JWT do leitor. XP é a única operação
  // nesta função que exige o cliente privilegiado sem substituir seu JWT.
  const privileged = createClient(supabaseUrl, serviceRoleKey);

  const { chapter_id, answers } = await req.json(); // answers: [{question_id, chosen_idx}]
  const { data: user } = await supabase.auth.getUser();
  if (!user?.user) return cors(new Response("unauth", { status: 401 }));

  const { data: questions } = await supabase
    .from("quiz_questions").select("id, correct_idx").eq("chapter_id", chapter_id);

  let score = 0;
  const detail = (questions ?? []).map((q) => {
    const a = answers.find((x: any) => x.question_id === q.id);
    const is_correct = a && a.chosen_idx === q.correct_idx;
    if (is_correct) score++;
    return { question_id: q.id, chosen_idx: a?.chosen_idx ?? -1, is_correct };
  });

  const { data: attempt } = await supabase
    .from("quiz_attempts")
    .insert({ user_id: user.user.id, chapter_id, score, total: questions!.length })
    .select().single();

  if (attempt) {
    await supabase.from("quiz_answers").insert(
      detail.map((d) => ({ ...d, attempt_id: attempt.id })),
    );
    // XP proporcional
    await privileged.rpc("award_xp", {
      p_user: user.user.id, p_source: "quiz_answer",
      p_amount: 50, p_ref: attempt.id,
    });
  }

  return cors(Response.json({ score, total: questions!.length, detail }));
});
