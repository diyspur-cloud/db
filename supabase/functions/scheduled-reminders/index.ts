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
    const { data: meetings, error: meetingsError } = await service
      .from("meetings").select("id,title,scheduled_at")
      .eq("status", "scheduled")
      .gte("scheduled_at", now.toISOString())
      .lte("scheduled_at", until.toISOString())
      .order("scheduled_at", { ascending: true }).limit(500);
    if (meetingsError) throw meetingsError;

    let created = 0;
    let skipped = 0;
    for (const meeting of meetings ?? []) {
      const { data: rsvps, error: rsvpError } = await service.from(
        "meeting_rsvps",
      )
        .select("user_id").eq("meeting_id", meeting.id).eq("attending", true)
        .limit(2000);
      if (rsvpError) throw rsvpError;
      for (const rsvp of rsvps ?? []) {
        const { data, error } = await service.rpc("deliver_meeting_reminder", {
          p_user: rsvp.user_id,
          p_meeting: meeting.id,
          p_window: "48h",
        });
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
    }
    return json({
      ok: true,
      created,
      skipped,
      meetings: meetings?.length ?? 0,
    });
  } catch (error) {
    console.error(
      "scheduled-reminders: request failed",
      error instanceof Error ? error.message : "unknown",
    );
    return json({ error: "temporarily_unavailable" }, 503);
  }
});
