import { serve } from "https://deno.land/std@0.200.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Resend } from "https://esm.sh/resend@3";
import { cors } from "../_shared/cors.ts";

const resend = new Resend(Deno.env.get("RESEND_API_KEY")!);

serve(async (req) => {
  if (req.method === "OPTIONS") return cors();
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { issue_id } = await req.json();

  const { data: issue } = await supabase
    .from("newsletter_issues").select("*").eq("id", issue_id).single();
  if (!issue) return cors(new Response("not found", { status: 404 }));

  const { data: subs } = await supabase
    .from("newsletter_subscribers")
    .select("id, email, name")
    .eq("status", "confirmed");

  for (const s of subs ?? []) {
    const { data: sendRes, error } = await resend.emails.send({
      from: "Clube de Leitura <news@clubeleitura.app>",
      to: s.email,
      subject: issue.subject,
      html: issue.body_html ?? `<pre>${issue.body_markdown}</pre>`,
    });
    await supabase.from("newsletter_deliveries").upsert(
      {
        issue_id,
        subscriber_id: s.id,
        status: error ? "bounced" : "sent",
        provider_message_id: sendRes?.id,
        sent_at: new Date().toISOString(),
      },
      { onConflict: "issue_id,subscriber_id" },
    );
  }

  await supabase.from("newsletter_issues")
    .update({ sent_at: new Date().toISOString() })
    .eq("id", issue_id);

  return cors(Response.json({ ok: true, sent: (subs ?? []).length }));
});
