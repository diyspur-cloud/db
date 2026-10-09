import { constantTimeEqual, json, serviceClient } from "../_shared/auth.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const expected = Deno.env.get("SCHEDULED_REMINDERS_SECRET");
  const actual = req.headers.get("x-scheduled-reminders-secret") ?? "";
  if (!expected || !constantTimeEqual(actual, expected)) {
    return json({ error: "unauthorized" }, 401);
  }

  try {
    const service = serviceClient();
    const now = new Date();
    const until = new Date(now.getTime() + 48 * 60 * 60_000);
    const meetingPageSize = 500;
    const rsvpPageSize = 2_000;
    const meetings: Array<{
      id: string;
      title: string;
      scheduled_at: string;
    }> = [];
    for (let offset = 0;; offset += meetingPageSize) {
      // Decisão preservada do handler existente: somente reuniões scheduled
      // dentro da janela e RSVP attending=true recebem lembrete. O SDD não
      // define regra para cancelled/live ou RSVP negativo, então não os
      // promovemos silenciosamente a destinatários.
      const { data, error } = await service.from("meetings")
        .select("id,title,scheduled_at")
        .eq("status", "scheduled")
        .gte("scheduled_at", now.toISOString())
        .lte("scheduled_at", until.toISOString())
        .order("scheduled_at", { ascending: true })
        .order("id", { ascending: true })
        .range(offset, offset + meetingPageSize - 1);
      if (error) throw error;
      const page = data ?? [];
      meetings.push(...page);
      if (page.length < meetingPageSize) break;
    }

    let created = 0;
    let skipped = 0;
    for (const meeting of meetings) {
      for (let offset = 0;; offset += rsvpPageSize) {
        const { data: rsvps, error: rsvpError } = await service.from(
          "meeting_rsvps",
        )
          .select("user_id").eq("meeting_id", meeting.id).eq("attending", true)
          .order("user_id", { ascending: true })
          .range(offset, offset + rsvpPageSize - 1);
        if (rsvpError) throw rsvpError;
        const page = rsvps ?? [];
        for (const rsvp of page) {
          const { data, error } = await service.rpc(
            "deliver_meeting_reminder",
            {
              p_user: rsvp.user_id,
              p_meeting: meeting.id,
              p_window: "48h",
            },
          );
          if (error) {
            console.error(
              "scheduled-reminders: delivery RPC failed",
              error.message,
            );
            skipped++;
            continue;
          }
          if (data === true) created++;
          else skipped++;
        }
        if (page.length < rsvpPageSize) break;
      }
    }
    return json({
      ok: true,
      created,
      skipped,
      meetings: meetings.length,
    });
  } catch (error) {
    console.error(
      "scheduled-reminders: request failed",
      error instanceof Error ? error.message : "unknown",
    );
    return json({ error: "temporarily_unavailable" }, 503);
  }
});
