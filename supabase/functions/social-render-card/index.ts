import { cors } from "../_shared/cors.ts";
import { json, requestUser, serviceClient } from "../_shared/auth.ts";

const kinds = new Set([
  "quote_card",
  "progress_card",
  "milestone_card",
  "review_card",
  "list_card",
  "aura_card",
  "streak_card",
]);
function xmlEscape(value: string): string {
  return value.replace(
    /[&<>"']/g,
    (character) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&apos;",
      })[character]!,
  );
}
function wrap(text: string, max = 36): string[] {
  const words = text.split(/\s+/).filter(Boolean);
  const lines: string[] = [];
  let current = "";
  for (const word of words) {
    if ((current + " " + word).trim().length > max && current) {
      lines.push(current);
      current = word;
    } else current = (current + " " + word).trim();
    if (lines.length === 4) break;
  }
  if (current && lines.length < 5) lines.push(current);
  return lines;
}
function renderSvg(title: string, body: string): string {
  const lines = wrap(body, 40).map((line, index) =>
    `<tspan x="90" dy="${index ? 62 : 0}">${xmlEscape(line)}</tspan>`
  ).join("");
  return `<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630"><defs><linearGradient id="bg"><stop stop-color="#1f2937"/><stop offset="1" stop-color="#7c3aed"/></linearGradient></defs><rect width="1200" height="630" fill="url(#bg)"/><text x="90" y="135" fill="#ddd6fe" font-family="sans-serif" font-size="28">CLUBE DE LEITURA</text><text x="90" y="230" fill="white" font-family="serif" font-size="48" font-weight="700">${
    xmlEscape(title)
  }</text><text x="90" y="330" fill="white" font-family="sans-serif" font-size="38">${lines}</text><text x="90" y="570" fill="#ede9fe" font-family="sans-serif" font-size="22">Compartilhe sua leitura</text></svg>`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return cors();
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const user = await requestUser(req);
    if (!user) return json({ error: "unauthorized" }, 401);
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return json({ error: "invalid_json" }, 400);
    }
    if (!body || typeof body !== "object") {
      return json({ error: "invalid_payload" }, 400);
    }
    const input = body as Record<string, unknown>;
    if (input.user_id !== undefined && input.user_id !== user.id) {
      return json({ error: "forbidden" }, 403);
    }
    if (
      typeof input.kind !== "string" || !kinds.has(input.kind) ||
      !input.payload || typeof input.payload !== "object" ||
      Array.isArray(input.payload)
    ) {
      return json({ error: "invalid_payload" }, 400);
    }
    const payload = input.payload as Record<string, unknown>;
    const title = typeof payload.title === "string"
      ? payload.title.slice(0, 100)
      : "Minha leitura";
    const quote = typeof payload.quote === "string"
      ? payload.quote.slice(0, 500)
      : typeof payload.text === "string"
      ? payload.text.slice(0, 500)
      : "Uma boa história merece ser compartilhada.";
    const service = serviceClient();
    const since = new Date(Date.now() - 24 * 60 * 60_000).toISOString();
    const { count, error: countError } = await service.from(
      "social_render_jobs",
    )
      .select("id", { count: "exact", head: true }).eq("user_id", user.id).gte(
        "created_at",
        since,
      );
    if (countError) return json({ error: "temporarily_unavailable" }, 503);
    if ((count ?? 0) >= 10) return json({ error: "daily_limit_reached" }, 429);

    const { data: job, error: jobError } = await service.from(
      "social_render_jobs",
    )
      .insert({
        user_id: user.id,
        kind: input.kind,
        payload: { title, quote },
        status: "queued",
      })
      .select("id").single();
    if (jobError || !job) return json({ error: "could_not_create_job" }, 503);
    const path = `${user.id}/${job.id}.svg`;
    const svg = renderSvg(title, quote);
    const { error: uploadError } = await service.storage.from("social-cards")
      .upload(
        path,
        new Blob([svg], { type: "image/svg+xml; charset=utf-8" }),
        { contentType: "image/svg+xml; charset=utf-8", upsert: false },
      );
    if (uploadError) {
      await service.from("social_render_jobs").update({
        status: "failed",
        error: "render_or_upload_failed",
      }).eq("id", job.id).eq("user_id", user.id);
      console.error("social-render-card: upload failed", uploadError.message);
      return json({ error: "render_failed" }, 503);
    }
    const { data: publicUrl } = service.storage.from("social-cards")
      .getPublicUrl(path);
    const { error: updateError } = await service.from("social_render_jobs")
      .update({
        status: "rendered",
        image_url: publicUrl.publicUrl,
        rendered_at: new Date().toISOString(),
      }).eq("id", job.id).eq("user_id", user.id);
    if (updateError) return json({ error: "render_state_update_failed" }, 503);
    return json({ ok: true, job_id: job.id, image_url: publicUrl.publicUrl });
  } catch (error) {
    console.error(
      "social-render-card: request failed",
      error instanceof Error ? error.message : "unknown",
    );
    return json({ error: "temporarily_unavailable" }, 503);
  }
});
