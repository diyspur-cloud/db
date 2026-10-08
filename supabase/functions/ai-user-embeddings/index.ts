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

  const { data: snapshot } = await supabase
    .rpc("build_user_reading_snapshot", { p_user: user_id });

  const openai = new OpenAI({ apiKey: Deno.env.get("OPENAI_API_KEY")! });
  const embed = await openai.embeddings.create({
    model: "text-embedding-3-small",
    input: snapshot ?? "[]",
  });
  const vector = embed.data[0].embedding;

  await supabase.from("user_reading_embeddings").upsert(
    {
      user_id,
      embedding: vector as unknown as string,
      source_hash: String(snapshot).length.toString(36),
      updated_at: new Date().toISOString(),
    },
    { onConflict: "user_id" },
  );

  return cors(Response.json({ ok: true, dims: vector.length }));
});
