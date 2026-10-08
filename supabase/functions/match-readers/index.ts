import { serve } from "https://deno.land/std@0.200.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { cors } from "../_shared/cors.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return cors();
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { user_id, threshold = 0.75, limit = 20 } = await req.json();

  const { data: me } = await supabase
    .from("user_reading_embeddings")
    .select("embedding")
    .eq("user_id", user_id)
    .single();

  if (!me) return cors(Response.json({ ok: false, reason: "no_embedding" }));

  const { data: matches } = await supabase.rpc("match_readers", {
    query_embedding: me.embedding,
    match_threshold: threshold,
    match_count: limit,
    p_user: user_id,
  });

  for (const m of matches ?? []) {
    await supabase.from("user_match_cache").upsert(
      {
        user_id,
        matched_id: m.user_id,
        similarity: m.similarity,
        shared_books: 0,
        shared_moods: [],
        computed_at: new Date().toISOString(),
      },
      { onConflict: "user_id,matched_id" },
    );
  }

  return cors(Response.json({ matches }));
});
