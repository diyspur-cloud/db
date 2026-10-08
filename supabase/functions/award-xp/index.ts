import { serve } from "https://deno.land/std@0.200.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { cors } from "../_shared/cors.ts";

const XP: Record<string, number> = {
  join_meeting: 10,
  finish_chapter: 20,
  comment: 30,
  quiz_answer: 50,
  finish_book: 100,
  streak_bonus: 25,
};

serve(async (req) => {
  if (req.method === "OPTIONS") return cors();
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { source, ref_id } = await req.json();
  const { data: { user } } = await supabase.auth.getUser(
    req.headers.get("Authorization")?.replace("Bearer ", "") ?? "",
  );
  if (!user) return cors(new Response("unauth", { status: 401 }));

  const amount = XP[source] ?? 0;
  await supabase.rpc("award_xp", {
    p_user: user.id, p_source: source, p_amount: amount, p_ref: ref_id,
  });
  return cors(Response.json({ ok: true, amount }));
});
