import { cors } from "../_shared/cors.ts";
import { json, requestUser, serviceClient, UUID_RE } from "../_shared/auth.ts";
import OpenAI from "openai";

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
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
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return json({ error: "invalid_json" }, 400);
    }
    if (body && typeof body === "object" && "user_id" in body) {
      const requested = (body as { user_id?: unknown }).user_id;
      if (
        typeof requested !== "string" || !UUID_RE.test(requested) ||
        requested !== user.id
      ) {
        return json({ error: "forbidden" }, 403);
      }
    }
    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiKey) return json({ error: "embeddings_unavailable" }, 503);
    const service = serviceClient();
    const { data: previous, error: previousError } = await service.from(
      "user_reading_embeddings",
    )
      .select("updated_at").eq("user_id", user.id).maybeSingle();
    if (previousError) return json({ error: "temporarily_unavailable" }, 503);
    if (
      previous?.updated_at &&
      Date.now() - Date.parse(previous.updated_at) < 60 * 60_000
    ) {
      return json({ error: "rate_limited", retry_after_seconds: 3600 }, 429);
    }
    const { data: snapshot, error: snapshotError } = await service.rpc(
      "build_user_reading_snapshot",
      { p_user: user.id },
    );
    if (snapshotError) {
      console.error(
        "ai-user-embeddings: snapshot failed",
        snapshotError.message,
      );
      return json({ error: "temporarily_unavailable" }, 503);
    }
    const snapshotText = typeof snapshot === "string"
      ? snapshot
      : JSON.stringify(snapshot ?? []);
    const openai = new OpenAI({ apiKey: openaiKey });
    const response = await openai.embeddings.create({
      model: "text-embedding-3-small",
      input: snapshotText.slice(0, 20_000),
    });
    const vector = response.data[0]?.embedding;
    if (!vector?.length) return json({ error: "embedding_unavailable" }, 503);
    const { error } = await service.from("user_reading_embeddings").upsert({
      user_id: user.id,
      embedding: vector as unknown as string,
      source_hash: await sha256(snapshotText),
      updated_at: new Date().toISOString(),
    }, { onConflict: "user_id" });
    if (error) {
      console.error("ai-user-embeddings: upsert failed", error.message);
      return json({ error: "temporarily_unavailable" }, 503);
    }
    return json({ ok: true, dims: vector.length });
  } catch (error) {
    console.error(
      "ai-user-embeddings: request failed",
      error instanceof Error ? error.message : "unknown",
    );
    return json({ error: "temporarily_unavailable" }, 503);
  }
});
