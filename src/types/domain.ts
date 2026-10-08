export type ShelfStatus = 'want_to_read' | 'reading' | 'read' | 'dnf';
export type CycleStatus = 'planned' | 'enrolling' | 'active' | 'finished';
export type MeetingKind = 'online' | 'in_person' | 'hybrid';
export type MeetingStatus = 'scheduled' | 'live' | 'done' | 'cancelled';
export type ReactionKind = 'like' | 'love' | 'fire' | 'clap' | 'thinking';
export type XpSource =
  | 'join_meeting' | 'finish_chapter' | 'comment'
  | 'quiz_answer' | 'finish_book' | 'streak_bonus';

export interface Profile {
  id: string;
  username: string;
  display_name: string;
  avatar_url?: string | null;
  bio?: string | null;
  role: 'reader' | 'ambassador' | 'editor' | 'admin';
  level?: 'estudante' | 'junior' | 'pleno' | 'senior' | 'lideranca' | null;
  onboarding_done: boolean;
}

export interface Chapter {
  id: string;
  season_id: string;
  number: number;
  title: string;
  reading_range?: string | null;
  youtube_url?: string | null;
  summary?: string | null;
}

export interface CommentVisible {
  id: string;
  chapter_id: string;
  user_id: string;
  parent_id: string | null;
  created_at: string;
  likes_count: number;
  replies_count: number;
  is_spoiler: boolean;
  is_locked: boolean;
  content: string | null;
}

export interface QuizQuestion { id: string; chapter_id: string; question: string; options: string[]; }
export interface QuizAnswerIn { question_id: string; chosen_idx: number; }
export interface QuizAttemptResult { score: number; total: number; detail: { question_id: string; is_correct: boolean }[]; }
