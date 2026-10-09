import { supabase } from "./client";

export type CommunityStats = {
  book_id: string;
  mood_percent: Record<string, number>;
  pace_percent: Record<"slow" | "medium" | "fast", number>;
  plot_vs_character_avg: number | null;
  sample_size: number | null;
  avg_rating: number;
  ratings_count: number;
  avg_spice_level: number;
};

export async function getBookCommunityStats(
  bookId: string,
): Promise<CommunityStats | null> {
  const { data, error } = await supabase
    .from("v_book_community_stats")
    .select(
      "book_id,mood_percent,pace_percent,plot_vs_character_avg,sample_size,avg_rating,ratings_count,avg_spice_level",
    )
    .eq("book_id", bookId)
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;
  return {
    book_id: data.book_id ?? bookId,
    mood_percent: (data.mood_percent ?? {}) as Record<string, number>,
    pace_percent: (data.pace_percent ?? {}) as Record<
      "slow" | "medium" | "fast",
      number
    >,
    plot_vs_character_avg: data.plot_vs_character_avg,
    sample_size: data.sample_size,
    avg_rating: data.avg_rating ?? 0,
    ratings_count: data.ratings_count ?? 0,
    avg_spice_level: data.avg_spice_level ?? 0,
  };
}
