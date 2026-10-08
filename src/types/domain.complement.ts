export type MoodKind =
  | 'adventurous' | 'emotional' | 'dark' | 'funny' | 'hopeful'
  | 'informative' | 'inspiring' | 'lighthearted' | 'mysterious'
  | 'reflective' | 'sad' | 'tense' | 'challenging';

export type PaceKind = 'slow' | 'medium' | 'fast';
export type ContentWarningSeverity = 'minor' | 'moderate' | 'graphic';
export type EditorialPickKind =
  | 'book_of_the_month' | 'editorial_pick' | 'community_pick' | 'staff_pick';
export type ReadingListVisibility = 'private' | 'unlisted' | 'public';
export type ReadingListItemKind = 'book' | 'chapter' | 'quote' | 'external';
export type JournalVisibility = 'private' | 'friends' | 'club' | 'public';
export type FeedPostKind =
  | 'quote' | 'review' | 'shelf_update' | 'progress' | 'list'
  | 'club_invite' | 'link' | 'photo' | 'poll';
export type FeedVisibility = 'public' | 'followers' | 'club' | 'private';
export type FollowStatus = 'pending' | 'accepted' | 'blocked';
export type MemberTier = 'free' | 'plus' | 'pro' | 'patron' | 'corporate';
export type SubscriptionStatus =
  | 'trialing' | 'active' | 'past_due' | 'canceled' | 'paused' | 'incomplete';
export type PaymentProvider = 'stripe' | 'mercado_pago' | 'pagseguro' | 'manual';
export type NewsletterStatus =
  | 'pending' | 'confirmed' | 'unsubscribed' | 'bounced' | 'complained';
export type NewsletterFrequency = 'daily' | 'weekly' | 'monthly' | 'special_only';
export type ExtraContentKind =
  | 'pdf' | 'slides' | 'audio' | 'video' | 'link' | 'spreadsheet'
  | 'deck' | 'notebook' | 'dataset' | 'template';
export type ActivityKind =
  | 'quiz' | 'crossword' | 'word_search' | 'poll' | 'trivia'
  | 'flashcards' | 'debate_prompt' | 'drawing_prompt' | 'roleplay'
  | 'essay_prompt' | 'timed_challenge';
export type ActivityStatus = 'draft' | 'published' | 'archived';
export type SocialTemplateKind =
  | 'quote_card' | 'progress_card' | 'milestone_card'
  | 'review_card' | 'list_card' | 'aura_card' | 'streak_card';
export type SocialRenderStatus = 'queued' | 'rendered' | 'failed' | 'expired';

export interface ContentWarning {
  id: string;
  code: string;
  label: string;
  description?: string | null;
  category?: string | null;
}

export interface BookContentWarning {
  id: string;
  book_id: string;
  warning_id: string;
  severity: ContentWarningSeverity;
  is_community: boolean;
  community_votes: number;
  notes?: string | null;
}

export interface BookMoodStats {
  book_id: string;
  mood_counts: Record<MoodKind, number>;
  mood_percent: Partial<Record<MoodKind, number>>;
  pace_percent: Record<PaceKind, number>;
  plot_vs_character_avg: number;
  sample_size: number;
}

export interface EditorialPick {
  id: string;
  book_id: string;
  season_id?: string | null;
  kind: EditorialPickKind;
  reference_month: string; // YYYY-MM-DD
  title?: string | null;
  rationale?: string | null;
  media_url?: string | null;
  is_active: boolean;
}

export interface ReadingJournalEntry {
  id: string;
  user_id: string;
  book_id: string;
  chapter_id?: string | null;
  season_id?: string | null;
  entry_date: string;
  page_from?: number | null;
  page_to?: number | null;
  percent_at?: number | null;
  minutes_read?: number | null;
  mood_at_time?: MoodKind | null;
  title?: string | null;
  body: string;
  visibility: JournalVisibility;
  is_spoiler: boolean;
  min_percent: number;
  likes_count: number;
  created_at: string;
  updated_at: string;
}

export interface ReadingList {
  id: string;
  owner_id: string;
  slug: string;
  title: string;
  description?: string | null;
  cover_url?: string | null;
  visibility: ReadingListVisibility;
  is_collaborative: boolean;
  theme?: string | null;
  tags: string[];
  items_count: number;
}

export interface ReadingListItem {
  id: string;
  list_id: string;
  kind: ReadingListItemKind;
  book_id?: string | null;
  chapter_id?: string | null;
  external_url?: string | null;
  quote_text?: string | null;
  note?: string | null;
  position: number;
}

export interface Milestone {
  id: string;
  chapter_id?: string | null;
  season_id: string;
  book_id: string;
  position: number;
  title: string;
  description?: string | null;
  kind: 'auto' | 'custom';
  page_from?: number | null;
  page_to?: number | null;
  chapter_from?: number | null;
  chapter_to?: number | null;
  percent_from?: number | null;
  percent_to?: number | null;
  target_date?: string | null;
  xp_reward: number;
}

export interface UserQuizAverage {
  user_id: string;
  attempts_total: number;
  score_sum: number;
  total_sum: number;
  average_percent: number;
  best_percent: number;
  last_attempt_at?: string | null;
}

export interface FeedPost {
  id: string;
  author_id: string;
  kind: FeedPostKind;
  visibility: FeedVisibility;
  club_id?: string | null;
  book_id?: string | null;
  chapter_id?: string | null;
  season_id?: string | null;
  body?: string | null;
  quote_text?: string | null;
  link_url?: string | null;
  cover_url?: string | null;
  metadata: Record<string, unknown>;
  is_spoiler: boolean;
  min_percent: number;
  likes_count: number;
  comments_count: number;
  shares_count: number;
  created_at: string;
  updated_at: string;
}

export interface ReaderMatch {
  matched_id: string;
  username: string;
  display_name: string;
  avatar_url?: string | null;
  similarity: number;
  shared_books: number;
  shared_moods: MoodKind[];
}

export interface MembershipPlan {
  id: string;
  code: string;
  tier: MemberTier;
  name: string;
  description?: string | null;
  price_cents: number;
  currency: string;
  interval: 'month' | 'year' | 'lifetime';
  stripe_price_id?: string | null;
  perks: Array<{ code: string; label: string; description?: string }>;
  is_active: boolean;
}

export interface UserSubscription {
  id: string;
  user_id: string;
  plan_id: string;
  status: SubscriptionStatus;
  provider: PaymentProvider;
  current_period_start?: string | null;
  current_period_end?: string | null;
  cancel_at_period_end: boolean;
}

export interface NewsletterSubscriber {
  id: string;
  user_id?: string | null;
  email: string;
  name?: string | null;
  status: NewsletterStatus;
  frequency: NewsletterFrequency;
  source?: string | null;
  tags: string[];
  confirmed_at?: string | null;
  unsubscribed_at?: string | null;
}

export interface ChapterExtraContent {
  id: string;
  chapter_id?: string | null;
  season_id?: string | null;
  book_id?: string | null;
  kind: ExtraContentKind;
  title: string;
  description?: string | null;
  storage_path?: string | null;
  external_url?: string | null;
  preview_url?: string | null;
  size_bytes?: number | null;
  mime_type?: string | null;
  position: number;
  is_public: boolean;
}

export interface ChapterActivity {
  id: string;
  chapter_id: string;
  kind: ActivityKind;
  status: ActivityStatus;
  title: string;
  instructions?: string | null;
  config: Record<string, unknown>;
  xp_reward: number;
  time_limit_sec?: number | null;
  position: number;
  available_from?: string | null;
  available_until?: string | null;
}

export interface ChapterPrompt {
  id: string;
  chapter_id: string;
  position: number;
  prompt: string;
  hint?: string | null;
  min_chars: number;
  max_chars: number;
}

export interface ChapterPromptResponse {
  prompt_id: string;
  user_id: string;
  response: string;
  visibility: JournalVisibility;
  created_at: string;
  updated_at: string;
}

export interface SocialRenderJob {
  id: string;
  user_id: string;
  kind: SocialTemplateKind;
  payload: Record<string, unknown>;
  status: SocialRenderStatus;
  image_url?: string | null;
  error?: string | null;
  created_at: string;
  rendered_at?: string | null;
}
