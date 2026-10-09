import { supabase } from "./client";

export type RealtimeStatus =
  | "SUBSCRIBED"
  | "TIMED_OUT"
  | "CHANNEL_ERROR"
  | "CLOSED"
  | string;

export type ChangeTable =
  | "comments"
  | "reactions"
  | "video_timed_comments"
  | "notifications"
  | "book_poll_votes"
  | "feed_posts"
  | "reading_journal_entries"
  | "user_match_cache"
  | "book_mood_votes"
  | "newsletter_issues"
  | "host_prompt_votes";

export function watchChanges(
  channelName: string,
  table: ChangeTable,
  filter: string | undefined,
  reload: () => void | Promise<void>,
  onStatus: (status: RealtimeStatus) => void = () => {},
): () => void {
  const channel = supabase
    .channel(channelName)
    .on(
      "postgres_changes",
      {
        event: "*",
        schema: "public",
        table,
        ...(filter ? { filter } : {}),
      },
      () => {
        void reload();
      },
    )
    .subscribe((status) => onStatus(status));

  return () => {
    void supabase.removeChannel(channel);
  };
}

export const watchChapterComments = (
  chapterId: string,
  reload: () => void | Promise<void>,
  onStatus?: (status: RealtimeStatus) => void,
) =>
  watchChanges(
    `comments:chapter:${chapterId}`,
    "comments",
    `chapter_id=eq.${chapterId}`,
    reload,
    onStatus,
  );

export const watchUserNotifications = (
  userId: string,
  reload: () => void | Promise<void>,
  onStatus?: (status: RealtimeStatus) => void,
) =>
  watchChanges(
    `notifications:${userId}`,
    "notifications",
    `user_id=eq.${userId}`,
    reload,
    onStatus,
  );
