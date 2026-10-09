import type { MoodKind, ReaderMatch } from "../../types/domain.complement";
import { supabase } from "./client";

export type EndpointReaderMatch = {
  user_id: string;
  username: string;
  display_name: string | null;
  avatar_url: string | null;
  similarity: number;
  shared_books: number;
  shared_moods: MoodKind[];
};

export function toReaderMatch(row: EndpointReaderMatch): ReaderMatch {
  return {
    matched_id: row.user_id,
    username: row.username,
    display_name: row.display_name ?? row.username,
    avatar_url: row.avatar_url,
    similarity: row.similarity,
    shared_books: row.shared_books,
    shared_moods: row.shared_moods,
  };
}

export async function matchReaders(options: {
  threshold?: number;
  limit?: number;
} = {}): Promise<ReaderMatch[] | { reason: "no_embedding" }> {
  const { data, error } = await supabase.functions.invoke("match-readers", {
    body: options,
  });
  if (error) throw error;
  if (data?.ok === false && data.reason === "no_embedding") {
    return { reason: "no_embedding" };
  }
  return ((data?.matches ?? []) as EndpointReaderMatch[]).map(toReaderMatch);
}

export async function getReaderMatches(limit = 20): Promise<ReaderMatch[]> {
  const { data: auth, error: authError } = await supabase.auth.getUser();
  if (authError || !auth.user) throw authError ?? new Error("unauthenticated");
  const { data, error } = await supabase.rpc("get_reader_matches", {
    p_user: auth.user.id,
    p_limit: limit,
  });
  if (error) throw error;
  return (data ?? []) as ReaderMatch[];
}
