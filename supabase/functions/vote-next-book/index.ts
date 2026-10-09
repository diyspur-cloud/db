import { cors } from "../_shared/cors.ts";
import { json, requestUser, serviceClient, UUID_RE } from "../_shared/auth.ts";

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
    const { poll_id, option_id } = body as Record<string, unknown>;
    if (
      typeof poll_id !== "string" || !UUID_RE.test(poll_id) ||
      typeof option_id !== "string" || !UUID_RE.test(option_id)
    ) {
      return json({ error: "invalid_payload" }, 400);
    }
    const { data, error } = await serviceClient().rpc("cast_book_poll_vote", {
      p_user: user.id,
      p_poll: poll_id,
      p_option: option_id,
    });
    if (error) {
      if (error.code === "P0001") return json({ error: "poll_closed" }, 409);
      if (error.code === "23503") {
        return json({ error: "option_not_in_poll" }, 400);
      }
      console.error("vote-next-book: RPC failed", error.message);
      return json({ error: "temporarily_unavailable" }, 503);
    }
    return json({ ok: true, votes: data });
  } catch (error) {
    console.error(
      "vote-next-book: request failed",
      error instanceof Error ? error.message : "unknown",
    );
    return json({ error: "server_misconfigured_or_unavailable" }, 503);
  }
});
