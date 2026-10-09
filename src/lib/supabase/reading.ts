import { supabase } from "./client";

export async function getVisibleChapterComments(chapterId: string) {
  const { data, error } = await supabase
    .from("v_comments_visible")
    .select(
      "id,chapter_id,user_id,parent_id,content,is_spoiler,is_locked,likes_count,replies_count,created_at",
    )
    .eq("chapter_id", chapterId)
    .order("created_at", { ascending: true });
  if (error) throw error;
  return data ?? [];
}

export async function getMyReadingOverview() {
  const { data: auth, error: authError } = await supabase.auth.getUser();
  if (authError || !auth.user) throw authError ?? new Error("unauthenticated");
  const { data, error } = await supabase
    .from("v_user_reading_overview")
    .select(
      "user_id,books_read,books_reading,books_want,books_dnf,total_minutes,reading_days,read_today",
    )
    .eq("user_id", auth.user.id)
    .maybeSingle();
  if (error) throw error;
  return data;
}
