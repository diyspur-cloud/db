import { serve } from "https://deno.land/std@0.200.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { cors } from "../_shared/cors.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return cors();
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { poll_id, option_id } = await req.json();
  const auth = req.headers.get("Authorization")?.replace("Bearer ", "") ?? "";
  const { data: { user } } = await supabase.auth.getUser(auth);
  if (!user) return cors(new Response("unauth", { status: 401 }));

  await supabase.from("book_poll_votes").upsert(
    { poll_id, option_id, user_id: user.id },
    { onConflict: "poll_id,user_id" },
  );

  // Recontagem
  const { count } = await supabase
    .from("book_poll_votes")
    .select("*", { count: "exact", head: true })
    .eq("option_id", option_id);
  await supabase.from("book_poll_options")
    .update({ votes_count: count ?? 0 }).eq("id", option_id);

  return cors(Response.json({ ok: true, votes: count }));
});
