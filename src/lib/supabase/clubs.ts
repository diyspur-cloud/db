import { supabase } from "./client";

export type ClubProgressPanel = {
  club_id: string;
  club_name: string;
  current_book_id: string | null;
  current_book_title: string | null;
  current_season_id: string | null;
  current_season_title: string | null;
  current_started_at: string | null;
  current_ends_at: string | null;
  distinct_readers: number;
  chapters_read: number;
  chapters_in_progress: number;
  avg_percent: number;
  finished_count: number;
  reading_count: number;
  not_started_count: number;
};

export async function getClubProgressPanel(
  clubId: string,
): Promise<ClubProgressPanel | null> {
  const { data, error } = await supabase
    .from("v_club_progress_panel")
    .select(
      "club_id,club_name,current_book_id,current_book_title,current_season_id,current_season_title,current_started_at,current_ends_at,distinct_readers,chapters_read,chapters_in_progress,avg_percent,finished_count,reading_count,not_started_count",
    )
    .eq("club_id", clubId)
    .maybeSingle();
  if (error) throw error;
  return data as ClubProgressPanel | null;
}

export async function setClubReadingContext(
  clubId: string,
  context: {
    current_book_id?: string | null;
    current_season_id?: string | null;
    current_started_at?: string | null;
    current_ends_at?: string | null;
  },
) {
  const { data, error } = await supabase
    .from("user_clubs")
    .update(context)
    .eq("id", clubId)
    .select(
      "id,name,current_book_id,current_season_id,current_started_at,current_ends_at",
    )
    .maybeSingle();
  if (error) throw error;
  return data;
}
