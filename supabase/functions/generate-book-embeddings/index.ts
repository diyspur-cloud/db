import { isAdmin, json, requestUser, serviceClient } from "../_shared/auth.ts";
import OpenAI from "openai";

const PAGE_SIZE = 20;
Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const user = await requestUser(req);
    if (!user) return json({ error: "unauthorized" }, 401);
    const service = serviceClient();
    if (!await isAdmin(user.id, service)) {
      return json({ error: "forbidden" }, 403);
    }
    const apiKey = Deno.env.get("OPENAI_API_KEY");
    if (!apiKey) return json({ error: "embedding_provider_unavailable" }, 503);
    let body: unknown = {};
    try {
      body = await req.json();
    } catch {
      return json({ error: "invalid_json" }, 400);
    }
    const requested = body && typeof body === "object"
      ? (body as Record<string, unknown>).limit
      : undefined;
    const limit = typeof requested === "number"
      ? Math.floor(requested)
      : PAGE_SIZE;
    if (limit < 1 || limit > PAGE_SIZE) {
      return json({ error: "limit_must_be_1_to_20" }, 400);
    }

    const { data: books, error: booksError } = await service.from("books")
      .select("id,title,synopsis,tags,language").is("embedding", null)
      .order("created_at", { ascending: true }).limit(limit);
    if (booksError) {
      console.error(
        "generate-book-embeddings: catalog read failed",
        booksError.message,
      );
      return json({ error: "temporarily_unavailable" }, 503);
    }
    if (!books?.length) {
      return json({ ok: true, processed: 0, remaining: false });
    }
    const input = books.map((book) =>
      [
        `Título: ${book.title}`,
        `Sinopse: ${book.synopsis ?? ""}`,
        `Tags: ${(book.tags ?? []).join(", ")}`,
        `Idioma: ${book.language ?? "pt-BR"}`,
      ].join("\n").slice(0, 8_000)
    );
    const openai = new OpenAI({ apiKey });
    const result = await openai.embeddings.create({
      model: "text-embedding-3-small",
      input,
    });
    let processed = 0;
    for (const item of result.data) {
      const book = books[item.index];
      if (!book || item.embedding.length !== 1536) continue;
      const { error } = await service.from("books").update({
        embedding: item.embedding as unknown as string,
        updated_at: new Date().toISOString(),
      }).eq("id", book.id).is("embedding", null);
      if (error) {
        console.error("generate-book-embeddings: write failed", error.message);
      } else processed++;
    }
    return json({ ok: true, processed, remaining: books.length === limit });
  } catch (error) {
    console.error(
      "generate-book-embeddings: request failed",
      error instanceof Error ? error.message : "unknown",
    );
    return json({ error: "temporarily_unavailable" }, 503);
  }
});
