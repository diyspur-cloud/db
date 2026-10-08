import { serve } from "https://deno.land/std@0.200.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async () => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const now = new Date();
  const in48h = new Date(now.getTime() + 48 * 3600_000).toISOString();

  const { data: meetings } = await supabase
    .from("meetings").select("*")
    .gte("scheduled_at", now.toISOString())
    .lte("scheduled_at", in48h);

  for (const m of meetings ?? []) {
    const { data: rsvps } = await supabase
      .from("meeting_rsvps").select("user_id").eq("meeting_id", m.id);
    for (const r of rsvps ?? []) {
      await supabase.from("notifications").insert({
        user_id: r.user_id, kind: "meeting_reminder",
        payload: { meeting_id: m.id, title: m.title, at: m.scheduled_at },
      });
    }
  }
  return Response.json({ ok: true });
});
