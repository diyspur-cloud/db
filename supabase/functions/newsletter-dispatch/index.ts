import { cors } from "../_shared/cors.ts";
import {
  isAdmin,
  json,
  requestUser,
  serviceClient,
  UUID_RE,
} from "../_shared/auth.ts";
import { Resend } from "resend";

function htmlEscape(value: string): string {
  return value.replace(
    /[&<>"']/g,
    (character) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        character
      ]!,
  );
}
async function audienceKey(value: unknown): Promise<string> {
  const canonical = JSON.stringify(value ?? {});
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonical),
  );
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return cors();
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const user = await requestUser(req);
    if (!user) return json({ error: "unauthorized" }, 401);
    const service = serviceClient();
    if (!await isAdmin(user.id, service)) {
      return json({ error: "forbidden" }, 403);
    }
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return json({ error: "invalid_json" }, 400);
    }
    const issueId = body && typeof body === "object"
      ? (body as Record<string, unknown>).issue_id
      : null;
    if (typeof issueId !== "string" || !UUID_RE.test(issueId)) {
      return json({ error: "invalid_payload" }, 400);
    }
    const { data: issue, error: issueError } = await service.from(
      "newsletter_issues",
    )
      .select("id,subject,body_html,body_markdown,audience_filter,sent_at")
      .eq("id", issueId).maybeSingle();
    if (issueError) return json({ error: "temporarily_unavailable" }, 503);
    if (!issue) return json({ error: "issue_not_found" }, 404);
    if (issue.sent_at) return json({ error: "already_dispatched" }, 409);

    const filter = issue.audience_filter ?? {};
    if (!filter || typeof filter !== "object" || Array.isArray(filter)) {
      return json({ error: "invalid_audience_filter" }, 422);
    }
    const filterObject = filter as Record<string, unknown>;
    const allowedKeys = new Set(["frequency", "tags_any", "tags_all"]);
    if (Object.keys(filterObject).some((key) => !allowedKeys.has(key))) {
      return json({ error: "unsupported_audience_filter" }, 422);
    }
    if (
      filterObject.frequency !== undefined &&
      !["daily", "weekly", "monthly", "special_only"].includes(
        String(filterObject.frequency),
      )
    ) {
      return json({ error: "invalid_audience_filter" }, 422);
    }
    for (const key of ["tags_any", "tags_all"] as const) {
      if (
        filterObject[key] !== undefined && (!Array.isArray(filterObject[key]) ||
          (filterObject[key] as unknown[]).length > 50 ||
          !(filterObject[key] as unknown[]).every((tag) =>
            typeof tag === "string" && tag.length <= 80
          ))
      ) {
        return json({ error: "invalid_audience_filter" }, 422);
      }
    }
    const resendKey = Deno.env.get("RESEND_API_KEY");
    const from = Deno.env.get("RESEND_FROM_EMAIL");
    if (!resendKey || !from) {
      return json({ error: "newsletter_provider_unavailable" }, 503);
    }
    const resend = new Resend(resendKey);
    const key = await audienceKey(filter);
    const { data: claimed, error: claimError } = await service.rpc(
      "claim_newsletter_dispatch",
      {
        p_issue: issueId,
        p_audience_key: key,
      },
    );
    if (claimError || claimed !== true) {
      return json({ error: "dispatch_already_claimed" }, 409);
    }
    const { data: priorDeliveries, error: deliveryReadError } = await service
      .from("newsletter_deliveries")
      .select("subscriber_id").eq("issue_id", issueId).eq("status", "sent")
      .limit(10_000);
    if (deliveryReadError) throw deliveryReadError;
    const alreadySent = new Set(
      (priorDeliveries ?? []).map((row) => row.subscriber_id),
    );
    const recipients: Array<
      {
        id: string;
        email: string;
        name: string | null;
        tags: string[] | null;
        frequency: string;
      }
    > = [];
    for (let offset = 0;; offset += 500) {
      const { data, error } = await service.from("newsletter_subscribers")
        .select("id,email,name,tags,frequency").eq("status", "confirmed").is(
          "unsubscribed_at",
          null,
        )
        .range(offset, offset + 499);
      if (error) throw error;
      recipients.push(...(data ?? []).filter((subscriber) => {
        if (alreadySent.has(subscriber.id)) return false;
        if (
          filterObject.frequency &&
          subscriber.frequency !== filterObject.frequency
        ) return false;
        const tags = new Set(subscriber.tags ?? []);
        const any = (filterObject.tags_any as string[] | undefined) ?? [];
        const all = (filterObject.tags_all as string[] | undefined) ?? [];
        return (!any.length || any.some((tag) => tags.has(tag))) &&
          all.every((tag) => tags.has(tag));
      }));
      if (!data || data.length < 500) break;
    }

    let sent = 0;
    let failed = 0;
    const html = issue.body_html ??
      `<pre>${htmlEscape(issue.body_markdown ?? "")}</pre>`;
    for (const recipient of recipients) {
      let messageId: string | undefined;
      let failure: string | null = null;
      try {
        const { data, error } = await resend.emails.send({
          from,
          to: recipient.email,
          subject: issue.subject,
          html,
          headers: { "X-Entity-Ref-ID": `${issueId}:${recipient.id}` },
        });
        if (error) failure = error.message.slice(0, 500);
        else messageId = data?.id;
      } catch (error) {
        failure = error instanceof Error
          ? error.message.slice(0, 500)
          : "provider_error";
      }
      const { error: logError } = await service.from("newsletter_deliveries")
        .upsert({
          issue_id: issueId,
          subscriber_id: recipient.id,
          status: failure ? "bounced" : "sent",
          provider_message_id: messageId ?? null,
          sent_at: failure ? null : new Date().toISOString(),
        }, { onConflict: "issue_id,subscriber_id" });
      if (logError) {
        console.error(
          "newsletter-dispatch: delivery log failed",
          logError.message,
        );
        failed++;
      } else if (failure) {
        failed++;
      } else {
        sent++;
      }
    }
    const { error: finishError } = await service.rpc(
      "finish_newsletter_dispatch",
      {
        p_issue: issueId,
        p_audience_key: key,
        p_success: failed === 0,
      },
    );
    if (finishError) {
      console.error(
        "newsletter-dispatch: finalize failed",
        finishError.message,
      );
    }
    return json({ ok: failed === 0, sent, failed, total: recipients.length });
  } catch (error) {
    console.error(
      "newsletter-dispatch: request failed",
      error instanceof Error ? error.message : "unknown",
    );
    return json({ error: "temporarily_unavailable" }, 503);
  }
});
