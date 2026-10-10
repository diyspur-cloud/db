import { json, requestUser, serviceClient, UUID_RE } from "../_shared/auth.ts";
import { cors } from "../_shared/cors.ts";

const XP = {
  join_meeting: 10,
  finish_chapter: 20,
  comment: 30,
  quiz_answer: 50,
  finish_book: 100,
  streak_bonus: 25,
} as const;
type Source = keyof typeof XP;

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
    const { source, ref_id } = body as Record<string, unknown>;
    if (typeof source !== "string" || !(source in XP)) {
      return json({ error: "unsupported_or_invalid_activity" }, 400);
    }

    if (source === "streak_bonus") {
      // A RPC deriva a referência UUID de current_date no servidor, exige
      // atividade de hoje e aplica a chave user/source/ref em modo atômico.
      // O calendário é UTC/current_date, igual ao trigger de streak existente;
      // qualquer ref_id enviado pelo cliente é deliberadamente ignorado.
      const service = serviceClient();
      const { data, error } = await service.rpc(
        "award_daily_streak_bonus",
        { p_user: user.id },
      );
      if (error) {
        console.error("award-xp: daily streak RPC failed", error.message);
        return json({ error: "could_not_award_xp" }, 503);
      }
      const result = Array.isArray(data) ? data[0] : data;
      const resultObject = result && typeof result === "object"
        ? result as Record<string, unknown>
        : null;
      const awarded = result === true ||
        (typeof result === "string" && UUID_RE.test(result)) ||
        resultObject?.awarded === true || resultObject?.ok === true;
      const duplicate = resultObject?.duplicate === true;
      if (!awarded && !duplicate) {
        return json({ error: "streak_bonus_not_eligible" }, 403);
      }
      return json({ ok: true, amount: XP.streak_bonus, duplicate });
    }

    if (typeof ref_id !== "string" || !UUID_RE.test(ref_id)) {
      // As demais fontes continuam exigindo a referência UUID da atividade
      // que o servidor verifica antes de chamar award_xp.
      return json({ error: "unsupported_or_invalid_activity" }, 400);
    }

    const service = serviceClient();
    let verified = false;
    if (source === "finish_chapter") {
      const { data, error } = await service.from("user_progress").select("id")
        .eq("user_id", user.id).eq("chapter_id", ref_id).eq("status", "read")
        .limit(1);
      verified = !error && !!data?.length;
    } else if (source === "quiz_answer") {
      const { data, error } = await service.from("quiz_attempts").select("id")
        .eq("id", ref_id).eq("user_id", user.id).maybeSingle();
      verified = !error && !!data;
    } else if (source === "comment") {
      const { data, error } = await service.from("comments").select("id")
        .eq("id", ref_id).eq("user_id", user.id).is("deleted_at", null)
        .maybeSingle();
      verified = !error && !!data;
    } else if (source === "join_meeting") {
      const { data, error } = await service.from("meeting_rsvps").select(
        "meeting_id",
      )
        .eq("meeting_id", ref_id).eq("user_id", user.id).eq("attending", true)
        .maybeSingle();
      verified = !error && !!data;
    } else if (source === "finish_book") {
      const { data: book, error: bookError } = await service.from("books")
        .select("id,total_chapters").eq("id", ref_id).maybeSingle();
      const { data: chapters, error: chapterError } = await service.from(
        "chapters",
      )
        .select("id, seasons!inner(book_id)").eq("seasons.book_id", ref_id);
      const requiredChapters = book?.total_chapters && book.total_chapters > 0
        ? book.total_chapters
        : chapters?.length ?? 0;
      if (!bookError && !chapterError && chapters?.length && chapters.length >= requiredChapters) {
        const ids = chapters.map((row) => row.id);
        const { data: progress, error: progressError } = await service.from(
          "user_progress",
        )
          .select("chapter_id").eq("user_id", user.id).eq("status", "read").in(
            "chapter_id",
            ids,
          );
        verified = !progressError &&
          new Set((progress ?? []).map((row) => row.chapter_id)).size >=
            requiredChapters;
      }
    }
    if (!verified) return json({ error: "activity_not_verified" }, 403);

    const amount = XP[source as Source];
    const { error } = await service.rpc("award_xp", {
      p_user: user.id,
      p_source: source,
      p_amount: amount,
      p_ref: ref_id,
    });
    if (error) {
      console.error("award-xp: RPC failed", error.message);
      return json({ error: "could_not_award_xp" }, 503);
    }
    return json({ ok: true, amount });
  } catch (error) {
    console.error(
      "award-xp: request failed",
      error instanceof Error ? error.message : "unknown",
    );
    return json({ error: "server_misconfigured_or_unavailable" }, 503);
  }
});
