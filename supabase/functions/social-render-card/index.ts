import { serve } from "https://deno.land/std@0.200.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { cors } from "../_shared/cors.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return cors();
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { user_id, kind, payload } = await req.json();

  // Enfileira uma renderização para consumo de worker/next-gen render
  const { data, error } = await supabase
    .from("social_render_jobs")
    .insert({
      user_id,
      kind,
      payload,
      status: "queued",
    })
    .select()
    .single();

  if (error) return cors(new Response(error.message, { status: 400 }));

  // Placeholder: a renderização real pode ser feita por worker externo
  // (ex.: Chromium headless via Browserless, Cloudflare Images, ou Vercel OG).
  return cors(Response.json({ ok: true, job: data }));
});
