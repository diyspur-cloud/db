import { cors } from "../_shared/cors.ts";
import { json, requestUser, serviceClient, UUID_RE } from "../_shared/auth.ts";

type ReaderMatch = {
  user_id: string;
  username: string;
  display_name: string | null;
  avatar_url: string | null;
  similarity: number;
};
type ReaderOverlap = {
  matched_id: string;
  shared_books: number;
  shared_moods: string[];
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return cors();
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const user = await requestUser(req);
    if (!user) return json({ error: "unauthorized" }, 401);
    let body: unknown = {};
    try {
      body = await req.json();
    } catch {
      return json({ error: "invalid_json" }, 400);
    }
    const options = body && typeof body === "object"
      ? body as Record<string, unknown>
      : {};
    if (
      options.user_id !== undefined && (typeof options.user_id !== "string" ||
        !UUID_RE.test(options.user_id) || options.user_id !== user.id)
    ) return json({ error: "forbidden" }, 403);
    const threshold = typeof options.threshold === "number"
      ? options.threshold
      : 0.75;
    const limit = typeof options.limit === "number"
      ? Math.floor(options.limit)
      : 20;
    if (
      !Number.isFinite(threshold) || threshold < 0.55 || threshold > 0.95 ||
      limit < 1 || limit > 20
    ) {
      return json({ error: "invalid_parameters" }, 400);
    }
    const service = serviceClient();
    const { data: mine, error: mineError } = await service.from(
      "user_reading_embeddings",
    )
      .select("embedding").eq("user_id", user.id).maybeSingle();
    if (mineError) return json({ error: "temporarily_unavailable" }, 503);
    if (!mine?.embedding) return json({ ok: false, reason: "no_embedding" });
    const { data: rawMatches, error: matchError } = await service.rpc(
      "match_readers",
      {
        query_embedding: mine.embedding,
        match_threshold: threshold,
        match_count: limit,
        p_user: user.id,
      },
    );
    if (matchError) {
      console.error(
        "match-readers: similarity query failed",
        matchError.message,
      );
      return json({ error: "temporarily_unavailable" }, 503);
    }
    const matchesFromRpc = (rawMatches ?? []) as ReaderMatch[];
    const candidates = matchesFromRpc.filter((row) =>
      typeof row.user_id === "string"
    ).map((row) => row.user_id);
    if (!candidates.length) return json({ ok: true, matches: [] });
    const { data: overlaps, error: overlapError } = await service.rpc(
      "get_reader_overlaps",
      {
        p_user: user.id,
        p_candidates: candidates,
      },
    );
    if (overlapError) {
      console.error(
        "match-readers: overlap query failed",
        overlapError.message,
      );
      return json({ error: "temporarily_unavailable" }, 503);
    }
    const overlapRows = (overlaps ?? []) as ReaderOverlap[];
    const byId = new Map<string, ReaderOverlap>(
      overlapRows.map((row) => [row.matched_id, row]),
    );
    const matches = matchesFromRpc.map((match) => {
      const overlap = byId.get(match.user_id);
      return {
        ...match,
        shared_books: overlap?.shared_books ?? 0,
        shared_moods: overlap?.shared_moods ?? [],
      };
    });
    const cacheRows = matches.map((match) => ({
      user_id: user.id,
      matched_id: match.user_id,
      similarity: match.similarity,
      shared_books: match.shared_books,
      shared_moods: match.shared_moods,
      computed_at: new Date().toISOString(),
    }));
    const { error: cacheError } = await service.from("user_match_cache")
      .upsert(cacheRows, { onConflict: "user_id,matched_id" });
    if (cacheError) {
      console.error("match-readers: cache update failed", cacheError.message);
    }
    return json({ ok: true, matches });
  } catch (error) {
    console.error(
      "match-readers: request failed",
      error instanceof Error ? error.message : "unknown",
    );
    return json({ error: "temporarily_unavailable" }, 503);
  }
});
