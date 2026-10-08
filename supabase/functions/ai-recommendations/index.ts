import { serve } from "https://deno.land/std@0.200.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import OpenAI from "https://esm.sh/openai@4";
import { cors } from "../_shared/cors.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return cors();
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { user_id } = await req.json();

  const { data: history } = await supabase
    .from("user_progress").select("chapters(season_id, seasons(title))")
    .eq("user_id", user_id).eq("status", "read");

  const openai = new OpenAI({ apiKey: Deno.env.get("OPENAI_API_KEY")! });
  const embed = await openai.embeddings.create({
    model: "text-embedding-3-small",
    input: JSON.stringify(history),
  });
  const vector = embed.data[0].embedding;

  const { data: books } = await supabase.rpc("match_books", {
    query_embedding: vector, match_threshold: 0.72, match_count: 5,
  });

  return cors(Response.json({ books }));
});
