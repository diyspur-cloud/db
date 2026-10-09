import { cors } from "../_shared/cors.ts";
import { json, requestUser, serviceClient } from "../_shared/auth.ts";
import OpenAI from "openai";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return cors();
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const user = await requestUser(req);
    if (!user) return json({ error: "unauthorized" }, 401);
    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiKey) return json({ error: "recommendations_unavailable" }, 503);
    const service = serviceClient();
    const { data: snapshot, error: snapshotError } = await service.rpc(
      "build_user_reading_snapshot",
      { p_user: user.id },
    );
    if (snapshotError) {
      console.error(
        "ai-recommendations: snapshot failed",
        snapshotError.message,
      );
      return json({ error: "temporarily_unavailable" }, 503);
    }
    const input = typeof snapshot === "string"
      ? snapshot
      : JSON.stringify(snapshot ?? []);
    if (input.length < 3) return json({ books: [] });
    const openai = new OpenAI({ apiKey: openaiKey });
    const embedding = await openai.embeddings.create({
      model: "text-embedding-3-small",
      input: input.slice(0, 20_000),
    });
    const vector = embedding.data[0]?.embedding;
    if (!vector?.length) return json({ error: "embedding_unavailable" }, 503);
    const { data: books, error } = await service.rpc("match_books", {
      query_embedding: vector,
      match_threshold: 0.72,
      match_count: 5,
    });
    if (error) {
      console.error("ai-recommendations: match failed", error.message);
      return json({ error: "temporarily_unavailable" }, 503);
    }
    return json({ books: books ?? [] });
  } catch (error) {
    console.error(
      "ai-recommendations: request failed",
      error instanceof Error ? error.message : "unknown",
    );
    return json({ error: "temporarily_unavailable" }, 503);
  }
});
