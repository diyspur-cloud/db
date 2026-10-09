export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      achievements: {
        Row: {
          code: string
          description: string
          icon_url: string | null
          id: string
          rule: Json
          title: string
          xp_reward: number | null
        }
        Insert: {
          code: string
          description: string
          icon_url?: string | null
          id?: string
          rule: Json
          title: string
          xp_reward?: number | null
        }
        Update: {
          code?: string
          description?: string
          icon_url?: string | null
          id?: string
          rule?: Json
          title?: string
          xp_reward?: number | null
        }
        Relationships: []
      }
      affiliate_clicks: {
        Row: {
          book_id: string | null
          created_at: string
          id: string
          ip_hash: string | null
          referrer: string | null
          tag: string | null
          target_url: string
          user_agent: string | null
          user_id: string | null
        }
        Insert: {
          book_id?: string | null
          created_at?: string
          id?: string
          ip_hash?: string | null
          referrer?: string | null
          tag?: string | null
          target_url: string
          user_agent?: string | null
          user_id?: string | null
        }
        Update: {
          book_id?: string | null
          created_at?: string
          id?: string
          ip_hash?: string | null
          referrer?: string | null
          tag?: string | null
          target_url?: string
          user_agent?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "affiliate_clicks_book_id_fkey"
            columns: ["book_id"]
            isOneToOne: false
            referencedRelation: "books"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "affiliate_clicks_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "affiliate_clicks_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "affiliate_clicks_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      authors: {
        Row: {
          bio: string | null
          created_at: string
          id: string
          instagram: string | null
          name: string
          photo_url: string | null
          slug: string
          website_url: string | null
        }
        Insert: {
          bio?: string | null
          created_at?: string
          id?: string
          instagram?: string | null
          name: string
          photo_url?: string | null
          slug: string
          website_url?: string | null
        }
        Update: {
          bio?: string | null
          created_at?: string
          id?: string
          instagram?: string | null
          name?: string
          photo_url?: string | null
          slug?: string
          website_url?: string | null
        }
        Relationships: []
      }
      book_content_warning_votes: {
        Row: {
          agrees: boolean
          created_at: string
          user_id: string
          warning_row_id: string
        }
        Insert: {
          agrees?: boolean
          created_at?: string
          user_id: string
          warning_row_id: string
        }
        Update: {
          agrees?: boolean
          created_at?: string
          user_id?: string
          warning_row_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "book_content_warning_votes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "book_content_warning_votes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "book_content_warning_votes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "book_content_warning_votes_warning_row_id_fkey"
            columns: ["warning_row_id"]
            isOneToOne: false
            referencedRelation: "book_content_warnings"
            referencedColumns: ["id"]
          },
        ]
      }
      book_content_warnings: {
        Row: {
          book_id: string
          community_votes: number
          created_at: string
          id: string
          is_community: boolean
          notes: string | null
          reported_by: string | null
          severity: Database["public"]["Enums"]["content_warning_severity"]
          warning_id: string
        }
        Insert: {
          book_id: string
          community_votes?: number
          created_at?: string
          id?: string
          is_community?: boolean
          notes?: string | null
          reported_by?: string | null
          severity?: Database["public"]["Enums"]["content_warning_severity"]
          warning_id: string
        }
        Update: {
          book_id?: string
          community_votes?: number
          created_at?: string
          id?: string
          is_community?: boolean
          notes?: string | null
          reported_by?: string | null
          severity?: Database["public"]["Enums"]["content_warning_severity"]
          warning_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "book_content_warnings_book_id_fkey"
            columns: ["book_id"]
            isOneToOne: false
            referencedRelation: "books"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "book_content_warnings_reported_by_fkey"
            columns: ["reported_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "book_content_warnings_reported_by_fkey"
            columns: ["reported_by"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "book_content_warnings_reported_by_fkey"
            columns: ["reported_by"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "book_content_warnings_warning_id_fkey"
            columns: ["warning_id"]
            isOneToOne: false
            referencedRelation: "content_warnings"
            referencedColumns: ["id"]
          },
        ]
      }
      book_mood_stats: {
        Row: {
          book_id: string
          mood_counts: Json
          mood_percent: Json
          pace_percent: Json
          plot_vs_character_avg: number
          sample_size: number
          updated_at: string
        }
        Insert: {
          book_id: string
          mood_counts?: Json
          mood_percent?: Json
          pace_percent?: Json
          plot_vs_character_avg?: number
          sample_size?: number
          updated_at?: string
        }
        Update: {
          book_id?: string
          mood_counts?: Json
          mood_percent?: Json
          pace_percent?: Json
          plot_vs_character_avg?: number
          sample_size?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "book_mood_stats_book_id_fkey"
            columns: ["book_id"]
            isOneToOne: true
            referencedRelation: "books"
            referencedColumns: ["id"]
          },
        ]
      }
      book_mood_votes: {
        Row: {
          book_id: string
          created_at: string
          moods: Database["public"]["Enums"]["mood_kind"][]
          pace: Database["public"]["Enums"]["pace_kind"] | null
          plot_vs_character: number | null
          updated_at: string
          user_id: string
        }
        Insert: {
          book_id: string
          created_at?: string
          moods?: Database["public"]["Enums"]["mood_kind"][]
          pace?: Database["public"]["Enums"]["pace_kind"] | null
          plot_vs_character?: number | null
          updated_at?: string
          user_id: string
        }
        Update: {
          book_id?: string
          created_at?: string
          moods?: Database["public"]["Enums"]["mood_kind"][]
          pace?: Database["public"]["Enums"]["pace_kind"] | null
          plot_vs_character?: number | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "book_mood_votes_book_id_fkey"
            columns: ["book_id"]
            isOneToOne: false
            referencedRelation: "books"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "book_mood_votes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "book_mood_votes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "book_mood_votes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      book_poll_options: {
        Row: {
          book_id: string
          id: string
          poll_id: string
          proposal: string | null
          votes_count: number
        }
        Insert: {
          book_id: string
          id?: string
          poll_id: string
          proposal?: string | null
          votes_count?: number
        }
        Update: {
          book_id?: string
          id?: string
          poll_id?: string
          proposal?: string | null
          votes_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "book_poll_options_book_id_fkey"
            columns: ["book_id"]
            isOneToOne: false
            referencedRelation: "books"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "book_poll_options_poll_id_fkey"
            columns: ["poll_id"]
            isOneToOne: false
            referencedRelation: "book_polls"
            referencedColumns: ["id"]
          },
        ]
      }
      book_poll_votes: {
        Row: {
          created_at: string
          option_id: string
          poll_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          option_id: string
          poll_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          option_id?: string
          poll_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "book_poll_votes_option_id_fkey"
            columns: ["option_id"]
            isOneToOne: false
            referencedRelation: "book_poll_options"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "book_poll_votes_poll_id_fkey"
            columns: ["poll_id"]
            isOneToOne: false
            referencedRelation: "book_polls"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "book_poll_votes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "book_poll_votes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "book_poll_votes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      book_polls: {
        Row: {
          closes_at: string
          created_at: string
          id: string
          opens_at: string
          season_id: string | null
          status: Database["public"]["Enums"]["poll_status"]
          title: string
        }
        Insert: {
          closes_at: string
          created_at?: string
          id?: string
          opens_at?: string
          season_id?: string | null
          status?: Database["public"]["Enums"]["poll_status"]
          title: string
        }
        Update: {
          closes_at?: string
          created_at?: string
          id?: string
          opens_at?: string
          season_id?: string | null
          status?: Database["public"]["Enums"]["poll_status"]
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "book_polls_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
        ]
      }
      book_reviews: {
        Row: {
          book_id: string
          contains_spoilers: boolean
          created_at: string
          deleted_at: string | null
          id: string
          rating: number | null
          review_text: string | null
          spice_level: number | null
          updated_at: string
          user_id: string
        }
        Insert: {
          book_id: string
          contains_spoilers?: boolean
          created_at?: string
          deleted_at?: string | null
          id?: string
          rating?: number | null
          review_text?: string | null
          spice_level?: number | null
          updated_at?: string
          user_id: string
        }
        Update: {
          book_id?: string
          contains_spoilers?: boolean
          created_at?: string
          deleted_at?: string | null
          id?: string
          rating?: number | null
          review_text?: string | null
          spice_level?: number | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "book_reviews_book_id_fkey"
            columns: ["book_id"]
            isOneToOne: false
            referencedRelation: "books"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "book_reviews_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "book_reviews_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "book_reviews_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      books: {
        Row: {
          amazon_affiliate: string | null
          amazon_url: string | null
          audiobook_url: string | null
          author_id: string
          cover_url: string | null
          created_at: string
          ebook_url: string | null
          embedding: string | null
          id: string
          isbn13: string | null
          language: string | null
          publication_year: number | null
          slug: string
          synopsis: string | null
          tags: string[] | null
          title: string
          total_chapters: number | null
          total_pages: number | null
          updated_at: string
        }
        Insert: {
          amazon_affiliate?: string | null
          amazon_url?: string | null
          audiobook_url?: string | null
          author_id: string
          cover_url?: string | null
          created_at?: string
          ebook_url?: string | null
          embedding?: string | null
          id?: string
          isbn13?: string | null
          language?: string | null
          publication_year?: number | null
          slug: string
          synopsis?: string | null
          tags?: string[] | null
          title: string
          total_chapters?: number | null
          total_pages?: number | null
          updated_at?: string
        }
        Update: {
          amazon_affiliate?: string | null
          amazon_url?: string | null
          audiobook_url?: string | null
          author_id?: string
          cover_url?: string | null
          created_at?: string
          ebook_url?: string | null
          embedding?: string | null
          id?: string
          isbn13?: string | null
          language?: string | null
          publication_year?: number | null
          slug?: string
          synopsis?: string | null
          tags?: string[] | null
          title?: string
          total_chapters?: number | null
          total_pages?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "books_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "authors"
            referencedColumns: ["id"]
          },
        ]
      }
      buddy_read_checkpoints: {
        Row: {
          buddy_read_id: string
          id: string
          page_from: number | null
          page_to: number | null
          percent_from: number | null
          percent_to: number | null
          position: number
          target_date: string | null
          title: string
        }
        Insert: {
          buddy_read_id: string
          id?: string
          page_from?: number | null
          page_to?: number | null
          percent_from?: number | null
          percent_to?: number | null
          position: number
          target_date?: string | null
          title: string
        }
        Update: {
          buddy_read_id?: string
          id?: string
          page_from?: number | null
          page_to?: number | null
          percent_from?: number | null
          percent_to?: number | null
          position?: number
          target_date?: string | null
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "buddy_read_checkpoints_buddy_read_id_fkey"
            columns: ["buddy_read_id"]
            isOneToOne: false
            referencedRelation: "buddy_reads"
            referencedColumns: ["id"]
          },
        ]
      }
      buddy_read_members: {
        Row: {
          buddy_read_id: string
          joined_at: string
          user_id: string
        }
        Insert: {
          buddy_read_id: string
          joined_at?: string
          user_id: string
        }
        Update: {
          buddy_read_id?: string
          joined_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "buddy_read_members_buddy_read_id_fkey"
            columns: ["buddy_read_id"]
            isOneToOne: false
            referencedRelation: "buddy_reads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "buddy_read_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "buddy_read_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "buddy_read_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      buddy_reads: {
        Row: {
          book_id: string
          created_at: string
          end_date: string | null
          id: string
          is_private: boolean
          max_members: number
          owner_id: string
          season_id: string | null
          start_date: string | null
          title: string | null
        }
        Insert: {
          book_id: string
          created_at?: string
          end_date?: string | null
          id?: string
          is_private?: boolean
          max_members?: number
          owner_id: string
          season_id?: string | null
          start_date?: string | null
          title?: string | null
        }
        Update: {
          book_id?: string
          created_at?: string
          end_date?: string | null
          id?: string
          is_private?: boolean
          max_members?: number
          owner_id?: string
          season_id?: string | null
          start_date?: string | null
          title?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "buddy_reads_book_id_fkey"
            columns: ["book_id"]
            isOneToOne: false
            referencedRelation: "books"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "buddy_reads_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "buddy_reads_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "buddy_reads_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "buddy_reads_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
        ]
      }
      challenge_prompts: {
        Row: {
          book_id: string | null
          challenge_id: string
          completed_at: string | null
          completed_by: string | null
          id: string
          position: number
          prompt: string
        }
        Insert: {
          book_id?: string | null
          challenge_id: string
          completed_at?: string | null
          completed_by?: string | null
          id?: string
          position: number
          prompt: string
        }
        Update: {
          book_id?: string | null
          challenge_id?: string
          completed_at?: string | null
          completed_by?: string | null
          id?: string
          position?: number
          prompt?: string
        }
        Relationships: [
          {
            foreignKeyName: "challenge_prompts_book_id_fkey"
            columns: ["book_id"]
            isOneToOne: false
            referencedRelation: "books"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "challenge_prompts_challenge_id_fkey"
            columns: ["challenge_id"]
            isOneToOne: false
            referencedRelation: "challenges"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "challenge_prompts_completed_by_fkey"
            columns: ["completed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "challenge_prompts_completed_by_fkey"
            columns: ["completed_by"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "challenge_prompts_completed_by_fkey"
            columns: ["completed_by"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      challenges: {
        Row: {
          created_at: string
          description: string | null
          id: string
          prompt_rules: Json
          title: string
          year: number | null
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          prompt_rules: Json
          title: string
          year?: number | null
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          prompt_rules?: Json
          title?: string
          year?: number | null
        }
        Relationships: []
      }
      chapter_activities: {
        Row: {
          available_from: string | null
          available_until: string | null
          chapter_id: string
          config: Json
          created_at: string
          created_by: string | null
          id: string
          instructions: string | null
          kind: Database["public"]["Enums"]["activity_kind"]
          position: number
          status: Database["public"]["Enums"]["activity_status"]
          time_limit_sec: number | null
          title: string
          xp_reward: number
        }
        Insert: {
          available_from?: string | null
          available_until?: string | null
          chapter_id: string
          config?: Json
          created_at?: string
          created_by?: string | null
          id?: string
          instructions?: string | null
          kind: Database["public"]["Enums"]["activity_kind"]
          position?: number
          status?: Database["public"]["Enums"]["activity_status"]
          time_limit_sec?: number | null
          title: string
          xp_reward?: number
        }
        Update: {
          available_from?: string | null
          available_until?: string | null
          chapter_id?: string
          config?: Json
          created_at?: string
          created_by?: string | null
          id?: string
          instructions?: string | null
          kind?: Database["public"]["Enums"]["activity_kind"]
          position?: number
          status?: Database["public"]["Enums"]["activity_status"]
          time_limit_sec?: number | null
          title?: string
          xp_reward?: number
        }
        Relationships: [
          {
            foreignKeyName: "chapter_activities_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "chapters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chapter_activities_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "v_chapter_audience"
            referencedColumns: ["chapter_id"]
          },
          {
            foreignKeyName: "chapter_activities_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chapter_activities_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chapter_activities_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      chapter_activity_attempts: {
        Row: {
          activity_id: string
          duration_ms: number | null
          id: string
          max_score: number | null
          result: Json
          score: number | null
          submitted_at: string
          user_id: string
        }
        Insert: {
          activity_id: string
          duration_ms?: number | null
          id?: string
          max_score?: number | null
          result?: Json
          score?: number | null
          submitted_at?: string
          user_id: string
        }
        Update: {
          activity_id?: string
          duration_ms?: number | null
          id?: string
          max_score?: number | null
          result?: Json
          score?: number | null
          submitted_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "chapter_activity_attempts_activity_id_fkey"
            columns: ["activity_id"]
            isOneToOne: false
            referencedRelation: "chapter_activities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chapter_activity_attempts_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chapter_activity_attempts_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chapter_activity_attempts_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      chapter_extra_content: {
        Row: {
          book_id: string | null
          chapter_id: string | null
          created_at: string
          created_by: string | null
          description: string | null
          external_url: string | null
          id: string
          is_public: boolean
          kind: Database["public"]["Enums"]["extra_content_kind"]
          mime_type: string | null
          position: number
          preview_url: string | null
          season_id: string | null
          size_bytes: number | null
          storage_path: string | null
          title: string
        }
        Insert: {
          book_id?: string | null
          chapter_id?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          external_url?: string | null
          id?: string
          is_public?: boolean
          kind: Database["public"]["Enums"]["extra_content_kind"]
          mime_type?: string | null
          position?: number
          preview_url?: string | null
          season_id?: string | null
          size_bytes?: number | null
          storage_path?: string | null
          title: string
        }
        Update: {
          book_id?: string | null
          chapter_id?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          external_url?: string | null
          id?: string
          is_public?: boolean
          kind?: Database["public"]["Enums"]["extra_content_kind"]
          mime_type?: string | null
          position?: number
          preview_url?: string | null
          season_id?: string | null
          size_bytes?: number | null
          storage_path?: string | null
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "chapter_extra_content_book_id_fkey"
            columns: ["book_id"]
            isOneToOne: false
            referencedRelation: "books"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chapter_extra_content_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "chapters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chapter_extra_content_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "v_chapter_audience"
            referencedColumns: ["chapter_id"]
          },
          {
            foreignKeyName: "chapter_extra_content_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chapter_extra_content_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chapter_extra_content_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "chapter_extra_content_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
        ]
      }
      chapter_prompt_responses: {
        Row: {
          created_at: string
          prompt_id: string
          response: string
          updated_at: string
          user_id: string
          visibility: Database["public"]["Enums"]["journal_visibility"]
        }
        Insert: {
          created_at?: string
          prompt_id: string
          response: string
          updated_at?: string
          user_id: string
          visibility?: Database["public"]["Enums"]["journal_visibility"]
        }
        Update: {
          created_at?: string
          prompt_id?: string
          response?: string
          updated_at?: string
          user_id?: string
          visibility?: Database["public"]["Enums"]["journal_visibility"]
        }
        Relationships: [
          {
            foreignKeyName: "chapter_prompt_responses_prompt_id_fkey"
            columns: ["prompt_id"]
            isOneToOne: false
            referencedRelation: "chapter_prompts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chapter_prompt_responses_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chapter_prompt_responses_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chapter_prompt_responses_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      chapter_prompts: {
        Row: {
          chapter_id: string
          created_at: string
          hint: string | null
          id: string
          max_chars: number | null
          min_chars: number | null
          position: number
          prompt: string
        }
        Insert: {
          chapter_id: string
          created_at?: string
          hint?: string | null
          id?: string
          max_chars?: number | null
          min_chars?: number | null
          position: number
          prompt: string
        }
        Update: {
          chapter_id?: string
          created_at?: string
          hint?: string | null
          id?: string
          max_chars?: number | null
          min_chars?: number | null
          position?: number
          prompt?: string
        }
        Relationships: [
          {
            foreignKeyName: "chapter_prompts_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "chapters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chapter_prompts_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "v_chapter_audience"
            referencedColumns: ["chapter_id"]
          },
        ]
      }
      chapter_quiz_averages: {
        Row: {
          attempts_total: number
          average_percent: number
          chapter_id: string
          perfect_count: number
          updated_at: string
        }
        Insert: {
          attempts_total?: number
          average_percent?: number
          chapter_id: string
          perfect_count?: number
          updated_at?: string
        }
        Update: {
          attempts_total?: number
          average_percent?: number
          chapter_id?: string
          perfect_count?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "chapter_quiz_averages_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: true
            referencedRelation: "chapters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "chapter_quiz_averages_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: true
            referencedRelation: "v_chapter_audience"
            referencedColumns: ["chapter_id"]
          },
        ]
      }
      chapters: {
        Row: {
          created_at: string
          id: string
          number: number
          published_at: string | null
          reading_range: string | null
          season_id: string
          summary: string | null
          title: string
          youtube_live_url: string | null
          youtube_url: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          number: number
          published_at?: string | null
          reading_range?: string | null
          season_id: string
          summary?: string | null
          title: string
          youtube_live_url?: string | null
          youtube_url?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          number?: number
          published_at?: string | null
          reading_range?: string | null
          season_id?: string
          summary?: string | null
          title?: string
          youtube_live_url?: string | null
          youtube_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "chapters_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
        ]
      }
      comments: {
        Row: {
          chapter_id: string
          content: string
          created_at: string
          deleted_at: string | null
          edited_at: string | null
          id: string
          is_spoiler: boolean
          likes_count: number
          min_percent: number
          parent_id: string | null
          replies_count: number
          user_id: string
        }
        Insert: {
          chapter_id: string
          content: string
          created_at?: string
          deleted_at?: string | null
          edited_at?: string | null
          id?: string
          is_spoiler?: boolean
          likes_count?: number
          min_percent?: number
          parent_id?: string | null
          replies_count?: number
          user_id: string
        }
        Update: {
          chapter_id?: string
          content?: string
          created_at?: string
          deleted_at?: string | null
          edited_at?: string | null
          id?: string
          is_spoiler?: boolean
          likes_count?: number
          min_percent?: number
          parent_id?: string | null
          replies_count?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "comments_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "chapters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comments_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "v_chapter_audience"
            referencedColumns: ["chapter_id"]
          },
          {
            foreignKeyName: "comments_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      content_warnings: {
        Row: {
          category: string | null
          code: string
          created_at: string
          description: string | null
          id: string
          label: string
        }
        Insert: {
          category?: string | null
          code: string
          created_at?: string
          description?: string | null
          id?: string
          label: string
        }
        Update: {
          category?: string | null
          code?: string
          created_at?: string
          description?: string | null
          id?: string
          label?: string
        }
        Relationships: []
      }
      editorial_picks: {
        Row: {
          book_id: string
          created_at: string
          created_by: string | null
          id: string
          is_active: boolean
          kind: Database["public"]["Enums"]["editorial_pick_kind"]
          media_url: string | null
          rationale: string | null
          reference_month: string
          season_id: string | null
          title: string | null
        }
        Insert: {
          book_id: string
          created_at?: string
          created_by?: string | null
          id?: string
          is_active?: boolean
          kind?: Database["public"]["Enums"]["editorial_pick_kind"]
          media_url?: string | null
          rationale?: string | null
          reference_month: string
          season_id?: string | null
          title?: string | null
        }
        Update: {
          book_id?: string
          created_at?: string
          created_by?: string | null
          id?: string
          is_active?: boolean
          kind?: Database["public"]["Enums"]["editorial_pick_kind"]
          media_url?: string | null
          rationale?: string | null
          reference_month?: string
          season_id?: string | null
          title?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "editorial_picks_book_id_fkey"
            columns: ["book_id"]
            isOneToOne: false
            referencedRelation: "books"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "editorial_picks_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "editorial_picks_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "editorial_picks_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "editorial_picks_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
        ]
      }
      feed_post_comments: {
        Row: {
          content: string
          created_at: string
          deleted_at: string | null
          id: string
          is_spoiler: boolean
          likes_count: number
          parent_id: string | null
          post_id: string
          user_id: string
        }
        Insert: {
          content: string
          created_at?: string
          deleted_at?: string | null
          id?: string
          is_spoiler?: boolean
          likes_count?: number
          parent_id?: string | null
          post_id: string
          user_id: string
        }
        Update: {
          content?: string
          created_at?: string
          deleted_at?: string | null
          id?: string
          is_spoiler?: boolean
          likes_count?: number
          parent_id?: string | null
          post_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "feed_post_comments_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "feed_post_comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feed_post_comments_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "feed_posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feed_post_comments_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "v_feed_post_counters"
            referencedColumns: ["post_id"]
          },
          {
            foreignKeyName: "feed_post_comments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feed_post_comments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feed_post_comments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      feed_post_likes: {
        Row: {
          created_at: string
          post_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          post_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          post_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "feed_post_likes_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "feed_posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feed_post_likes_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "v_feed_post_counters"
            referencedColumns: ["post_id"]
          },
          {
            foreignKeyName: "feed_post_likes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feed_post_likes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feed_post_likes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      feed_post_media: {
        Row: {
          created_at: string
          id: string
          mime_type: string
          position: number
          post_id: string
          storage_path: string
        }
        Insert: {
          created_at?: string
          id?: string
          mime_type: string
          position?: number
          post_id: string
          storage_path: string
        }
        Update: {
          created_at?: string
          id?: string
          mime_type?: string
          position?: number
          post_id?: string
          storage_path?: string
        }
        Relationships: [
          {
            foreignKeyName: "feed_post_media_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "feed_posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feed_post_media_post_id_fkey"
            columns: ["post_id"]
            isOneToOne: false
            referencedRelation: "v_feed_post_counters"
            referencedColumns: ["post_id"]
          },
        ]
      }
      feed_posts: {
        Row: {
          author_id: string
          body: string | null
          book_id: string | null
          chapter_id: string | null
          club_id: string | null
          comments_count: number
          cover_url: string | null
          created_at: string
          deleted_at: string | null
          id: string
          is_spoiler: boolean
          kind: Database["public"]["Enums"]["feed_post_kind"]
          likes_count: number
          link_url: string | null
          metadata: Json
          min_percent: number
          quote_text: string | null
          season_id: string | null
          shares_count: number
          updated_at: string
          visibility: Database["public"]["Enums"]["feed_visibility"]
        }
        Insert: {
          author_id: string
          body?: string | null
          book_id?: string | null
          chapter_id?: string | null
          club_id?: string | null
          comments_count?: number
          cover_url?: string | null
          created_at?: string
          deleted_at?: string | null
          id?: string
          is_spoiler?: boolean
          kind?: Database["public"]["Enums"]["feed_post_kind"]
          likes_count?: number
          link_url?: string | null
          metadata?: Json
          min_percent?: number
          quote_text?: string | null
          season_id?: string | null
          shares_count?: number
          updated_at?: string
          visibility?: Database["public"]["Enums"]["feed_visibility"]
        }
        Update: {
          author_id?: string
          body?: string | null
          book_id?: string | null
          chapter_id?: string | null
          club_id?: string | null
          comments_count?: number
          cover_url?: string | null
          created_at?: string
          deleted_at?: string | null
          id?: string
          is_spoiler?: boolean
          kind?: Database["public"]["Enums"]["feed_post_kind"]
          likes_count?: number
          link_url?: string | null
          metadata?: Json
          min_percent?: number
          quote_text?: string | null
          season_id?: string | null
          shares_count?: number
          updated_at?: string
          visibility?: Database["public"]["Enums"]["feed_visibility"]
        }
        Relationships: [
          {
            foreignKeyName: "feed_posts_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feed_posts_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feed_posts_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "feed_posts_book_id_fkey"
            columns: ["book_id"]
            isOneToOne: false
            referencedRelation: "books"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feed_posts_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "chapters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feed_posts_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "v_chapter_audience"
            referencedColumns: ["chapter_id"]
          },
          {
            foreignKeyName: "feed_posts_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "user_clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "feed_posts_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "v_club_progress_panel"
            referencedColumns: ["club_id"]
          },
          {
            foreignKeyName: "feed_posts_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
        ]
      }
      follows: {
        Row: {
          created_at: string
          followed_id: string
          follower_id: string
          status: Database["public"]["Enums"]["follow_status"]
        }
        Insert: {
          created_at?: string
          followed_id: string
          follower_id: string
          status?: Database["public"]["Enums"]["follow_status"]
        }
        Update: {
          created_at?: string
          followed_id?: string
          follower_id?: string
          status?: Database["public"]["Enums"]["follow_status"]
        }
        Relationships: [
          {
            foreignKeyName: "follows_followed_id_fkey"
            columns: ["followed_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "follows_followed_id_fkey"
            columns: ["followed_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "follows_followed_id_fkey"
            columns: ["followed_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "follows_follower_id_fkey"
            columns: ["follower_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "follows_follower_id_fkey"
            columns: ["follower_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "follows_follower_id_fkey"
            columns: ["follower_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      host_prompt_votes: {
        Row: {
          created_at: string
          option_idx: number
          prompt_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          option_idx: number
          prompt_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          option_idx?: number
          prompt_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "host_prompt_votes_prompt_id_fkey"
            columns: ["prompt_id"]
            isOneToOne: false
            referencedRelation: "host_prompts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "host_prompt_votes_prompt_id_fkey"
            columns: ["prompt_id"]
            isOneToOne: false
            referencedRelation: "v_host_prompt_results"
            referencedColumns: ["prompt_id"]
          },
          {
            foreignKeyName: "host_prompt_votes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "host_prompt_votes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "host_prompt_votes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      host_prompts: {
        Row: {
          chapter_id: string
          created_at: string
          id: string
          options: Json
          question: string
        }
        Insert: {
          chapter_id: string
          created_at?: string
          id?: string
          options: Json
          question: string
        }
        Update: {
          chapter_id?: string
          created_at?: string
          id?: string
          options?: Json
          question?: string
        }
        Relationships: [
          {
            foreignKeyName: "host_prompts_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "chapters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "host_prompts_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "v_chapter_audience"
            referencedColumns: ["chapter_id"]
          },
        ]
      }
      meeting_rsvps: {
        Row: {
          attending: boolean
          created_at: string
          meeting_id: string
          user_id: string
        }
        Insert: {
          attending?: boolean
          created_at?: string
          meeting_id: string
          user_id: string
        }
        Update: {
          attending?: boolean
          created_at?: string
          meeting_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "meeting_rsvps_meeting_id_fkey"
            columns: ["meeting_id"]
            isOneToOne: false
            referencedRelation: "meetings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_rsvps_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_rsvps_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meeting_rsvps_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      meetings: {
        Row: {
          agenda: string | null
          chapter_id: string
          created_at: string
          duration_min: number | null
          id: string
          kind: Database["public"]["Enums"]["meeting_kind"]
          location: string | null
          meeting_url: string | null
          scheduled_at: string
          slides_url: string | null
          status: Database["public"]["Enums"]["meeting_status"]
          title: string
        }
        Insert: {
          agenda?: string | null
          chapter_id: string
          created_at?: string
          duration_min?: number | null
          id?: string
          kind?: Database["public"]["Enums"]["meeting_kind"]
          location?: string | null
          meeting_url?: string | null
          scheduled_at: string
          slides_url?: string | null
          status?: Database["public"]["Enums"]["meeting_status"]
          title: string
        }
        Update: {
          agenda?: string | null
          chapter_id?: string
          created_at?: string
          duration_min?: number | null
          id?: string
          kind?: Database["public"]["Enums"]["meeting_kind"]
          location?: string | null
          meeting_url?: string | null
          scheduled_at?: string
          slides_url?: string | null
          status?: Database["public"]["Enums"]["meeting_status"]
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "meetings_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "chapters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meetings_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "v_chapter_audience"
            referencedColumns: ["chapter_id"]
          },
        ]
      }
      membership_plans: {
        Row: {
          code: string
          created_at: string
          currency: string
          description: string | null
          id: string
          interval: string
          is_active: boolean
          name: string
          perks: Json
          price_cents: number
          stripe_price_id: string | null
          tier: Database["public"]["Enums"]["member_tier"]
        }
        Insert: {
          code: string
          created_at?: string
          currency?: string
          description?: string | null
          id?: string
          interval?: string
          is_active?: boolean
          name: string
          perks?: Json
          price_cents?: number
          stripe_price_id?: string | null
          tier: Database["public"]["Enums"]["member_tier"]
        }
        Update: {
          code?: string
          created_at?: string
          currency?: string
          description?: string | null
          id?: string
          interval?: string
          is_active?: boolean
          name?: string
          perks?: Json
          price_cents?: number
          stripe_price_id?: string | null
          tier?: Database["public"]["Enums"]["member_tier"]
        }
        Relationships: []
      }
      milestones: {
        Row: {
          book_id: string
          chapter_from: number | null
          chapter_id: string | null
          chapter_to: number | null
          created_at: string
          created_by: string | null
          description: string | null
          id: string
          kind: string
          page_from: number | null
          page_to: number | null
          percent_from: number | null
          percent_to: number | null
          position: number
          season_id: string
          target_date: string | null
          title: string
          xp_reward: number
        }
        Insert: {
          book_id: string
          chapter_from?: number | null
          chapter_id?: string | null
          chapter_to?: number | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          kind?: string
          page_from?: number | null
          page_to?: number | null
          percent_from?: number | null
          percent_to?: number | null
          position: number
          season_id: string
          target_date?: string | null
          title: string
          xp_reward?: number
        }
        Update: {
          book_id?: string
          chapter_from?: number | null
          chapter_id?: string | null
          chapter_to?: number | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          kind?: string
          page_from?: number | null
          page_to?: number | null
          percent_from?: number | null
          percent_to?: number | null
          position?: number
          season_id?: string
          target_date?: string | null
          title?: string
          xp_reward?: number
        }
        Relationships: [
          {
            foreignKeyName: "milestones_book_id_fkey"
            columns: ["book_id"]
            isOneToOne: false
            referencedRelation: "books"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "milestones_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "chapters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "milestones_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "v_chapter_audience"
            referencedColumns: ["chapter_id"]
          },
          {
            foreignKeyName: "milestones_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "milestones_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "milestones_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "milestones_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
        ]
      }
      mood_labels: {
        Row: {
          color_hex: string
          icon: string | null
          label_pt: string
          mood: Database["public"]["Enums"]["mood_kind"]
        }
        Insert: {
          color_hex: string
          icon?: string | null
          label_pt: string
          mood: Database["public"]["Enums"]["mood_kind"]
        }
        Update: {
          color_hex?: string
          icon?: string | null
          label_pt?: string
          mood?: Database["public"]["Enums"]["mood_kind"]
        }
        Relationships: []
      }
      newsletter_deliveries: {
        Row: {
          clicked_at: string | null
          issue_id: string
          opened_at: string | null
          provider_message_id: string | null
          sent_at: string | null
          status: string
          subscriber_id: string
        }
        Insert: {
          clicked_at?: string | null
          issue_id: string
          opened_at?: string | null
          provider_message_id?: string | null
          sent_at?: string | null
          status?: string
          subscriber_id: string
        }
        Update: {
          clicked_at?: string | null
          issue_id?: string
          opened_at?: string | null
          provider_message_id?: string | null
          sent_at?: string | null
          status?: string
          subscriber_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "newsletter_deliveries_issue_id_fkey"
            columns: ["issue_id"]
            isOneToOne: false
            referencedRelation: "newsletter_issues"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "newsletter_deliveries_subscriber_id_fkey"
            columns: ["subscriber_id"]
            isOneToOne: false
            referencedRelation: "newsletter_subscribers"
            referencedColumns: ["id"]
          },
        ]
      }
      newsletter_issues: {
        Row: {
          audience_filter: Json
          body_html: string | null
          body_markdown: string
          created_at: string
          created_by: string | null
          id: string
          preview_text: string | null
          provider_broadcast_id: string | null
          scheduled_at: string | null
          sent_at: string | null
          slug: string
          subject: string
        }
        Insert: {
          audience_filter?: Json
          body_html?: string | null
          body_markdown: string
          created_at?: string
          created_by?: string | null
          id?: string
          preview_text?: string | null
          provider_broadcast_id?: string | null
          scheduled_at?: string | null
          sent_at?: string | null
          slug: string
          subject: string
        }
        Update: {
          audience_filter?: Json
          body_html?: string | null
          body_markdown?: string
          created_at?: string
          created_by?: string | null
          id?: string
          preview_text?: string | null
          provider_broadcast_id?: string | null
          scheduled_at?: string | null
          sent_at?: string | null
          slug?: string
          subject?: string
        }
        Relationships: [
          {
            foreignKeyName: "newsletter_issues_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "newsletter_issues_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "newsletter_issues_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      newsletter_subscribers: {
        Row: {
          bounce_reason: string | null
          confirmed_at: string | null
          created_at: string
          email: string
          frequency: Database["public"]["Enums"]["newsletter_frequency"]
          id: string
          name: string | null
          provider: string | null
          provider_contact_id: string | null
          source: string | null
          status: Database["public"]["Enums"]["newsletter_status"]
          tags: string[] | null
          unsubscribed_at: string | null
          user_id: string | null
        }
        Insert: {
          bounce_reason?: string | null
          confirmed_at?: string | null
          created_at?: string
          email: string
          frequency?: Database["public"]["Enums"]["newsletter_frequency"]
          id?: string
          name?: string | null
          provider?: string | null
          provider_contact_id?: string | null
          source?: string | null
          status?: Database["public"]["Enums"]["newsletter_status"]
          tags?: string[] | null
          unsubscribed_at?: string | null
          user_id?: string | null
        }
        Update: {
          bounce_reason?: string | null
          confirmed_at?: string | null
          created_at?: string
          email?: string
          frequency?: Database["public"]["Enums"]["newsletter_frequency"]
          id?: string
          name?: string | null
          provider?: string | null
          provider_contact_id?: string | null
          source?: string | null
          status?: Database["public"]["Enums"]["newsletter_status"]
          tags?: string[] | null
          unsubscribed_at?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "newsletter_subscribers_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "newsletter_subscribers_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "newsletter_subscribers_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      notifications: {
        Row: {
          created_at: string
          id: string
          kind: Database["public"]["Enums"]["notification_kind"]
          payload: Json
          read_at: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          kind: Database["public"]["Enums"]["notification_kind"]
          payload?: Json
          read_at?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["notification_kind"]
          payload?: Json
          read_at?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      payment_events: {
        Row: {
          created_at: string
          event_id: string
          event_type: string
          id: string
          payload: Json
          processed_at: string | null
          provider: Database["public"]["Enums"]["payment_provider"]
          user_id: string | null
        }
        Insert: {
          created_at?: string
          event_id: string
          event_type: string
          id?: string
          payload: Json
          processed_at?: string | null
          provider: Database["public"]["Enums"]["payment_provider"]
          user_id?: string | null
        }
        Update: {
          created_at?: string
          event_id?: string
          event_type?: string
          id?: string
          payload?: Json
          processed_at?: string | null
          provider?: Database["public"]["Enums"]["payment_provider"]
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "payment_events_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_events_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_events_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      profiles: {
        Row: {
          avatar_url: string | null
          bio: string | null
          created_at: string
          display_name: string
          id: string
          level: string | null
          lgpd_consent: boolean
          lgpd_consent_at: string | null
          onboarding_done: boolean
          role: Database["public"]["Enums"]["user_role"]
          updated_at: string
          username: string
          whatsapp: string | null
        }
        Insert: {
          avatar_url?: string | null
          bio?: string | null
          created_at?: string
          display_name: string
          id: string
          level?: string | null
          lgpd_consent?: boolean
          lgpd_consent_at?: string | null
          onboarding_done?: boolean
          role?: Database["public"]["Enums"]["user_role"]
          updated_at?: string
          username: string
          whatsapp?: string | null
        }
        Update: {
          avatar_url?: string | null
          bio?: string | null
          created_at?: string
          display_name?: string
          id?: string
          level?: string | null
          lgpd_consent?: boolean
          lgpd_consent_at?: string | null
          onboarding_done?: boolean
          role?: Database["public"]["Enums"]["user_role"]
          updated_at?: string
          username?: string
          whatsapp?: string | null
        }
        Relationships: []
      }
      push_subscriptions: {
        Row: {
          auth: string
          created_at: string
          endpoint: string
          id: string
          p256dh: string
          user_id: string
        }
        Insert: {
          auth: string
          created_at?: string
          endpoint: string
          id?: string
          p256dh: string
          user_id: string
        }
        Update: {
          auth?: string
          created_at?: string
          endpoint?: string
          id?: string
          p256dh?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "push_subscriptions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "push_subscriptions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "push_subscriptions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      quiz_answers: {
        Row: {
          attempt_id: string
          chosen_idx: number
          is_correct: boolean
          question_id: string
        }
        Insert: {
          attempt_id: string
          chosen_idx: number
          is_correct: boolean
          question_id: string
        }
        Update: {
          attempt_id?: string
          chosen_idx?: number
          is_correct?: boolean
          question_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "quiz_answers_attempt_id_fkey"
            columns: ["attempt_id"]
            isOneToOne: false
            referencedRelation: "quiz_attempts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quiz_answers_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "quiz_questions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quiz_answers_question_id_fkey"
            columns: ["question_id"]
            isOneToOne: false
            referencedRelation: "v_quiz_questions_public"
            referencedColumns: ["id"]
          },
        ]
      }
      quiz_attempts: {
        Row: {
          chapter_id: string
          client_request_id: string | null
          created_at: string
          duration_ms: number | null
          id: string
          score: number
          total: number
          user_id: string
        }
        Insert: {
          chapter_id: string
          client_request_id?: string | null
          created_at?: string
          duration_ms?: number | null
          id?: string
          score: number
          total: number
          user_id: string
        }
        Update: {
          chapter_id?: string
          client_request_id?: string | null
          created_at?: string
          duration_ms?: number | null
          id?: string
          score?: number
          total?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "quiz_attempts_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "chapters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quiz_attempts_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "v_chapter_audience"
            referencedColumns: ["chapter_id"]
          },
          {
            foreignKeyName: "quiz_attempts_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quiz_attempts_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quiz_attempts_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      quiz_questions: {
        Row: {
          chapter_id: string
          correct_idx: number
          explanation: string | null
          id: string
          options: Json
          position: number
          question: string
        }
        Insert: {
          chapter_id: string
          correct_idx: number
          explanation?: string | null
          id?: string
          options: Json
          position: number
          question: string
        }
        Update: {
          chapter_id?: string
          correct_idx?: number
          explanation?: string | null
          id?: string
          options?: Json
          position?: number
          question?: string
        }
        Relationships: [
          {
            foreignKeyName: "quiz_questions_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "chapters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quiz_questions_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "v_chapter_audience"
            referencedColumns: ["chapter_id"]
          },
        ]
      }
      reactions: {
        Row: {
          comment_id: string
          created_at: string
          id: string
          kind: Database["public"]["Enums"]["reaction_kind"]
          user_id: string
        }
        Insert: {
          comment_id: string
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["reaction_kind"]
          user_id: string
        }
        Update: {
          comment_id?: string
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["reaction_kind"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "reactions_comment_id_fkey"
            columns: ["comment_id"]
            isOneToOne: false
            referencedRelation: "comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reactions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reactions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reactions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      reading_goal_progress: {
        Row: {
          books_done: number
          goal_id: string
          minutes_done: number
          pages_done: number
          updated_at: string
        }
        Insert: {
          books_done?: number
          goal_id: string
          minutes_done?: number
          pages_done?: number
          updated_at?: string
        }
        Update: {
          books_done?: number
          goal_id?: string
          minutes_done?: number
          pages_done?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "reading_goal_progress_goal_id_fkey"
            columns: ["goal_id"]
            isOneToOne: true
            referencedRelation: "reading_goals"
            referencedColumns: ["id"]
          },
        ]
      }
      reading_goals: {
        Row: {
          created_at: string
          id: string
          target_books: number | null
          target_minutes: number | null
          target_pages: number | null
          user_id: string
          year: number
        }
        Insert: {
          created_at?: string
          id?: string
          target_books?: number | null
          target_minutes?: number | null
          target_pages?: number | null
          user_id: string
          year: number
        }
        Update: {
          created_at?: string
          id?: string
          target_books?: number | null
          target_minutes?: number | null
          target_pages?: number | null
          user_id?: string
          year?: number
        }
        Relationships: [
          {
            foreignKeyName: "reading_goals_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_goals_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_goals_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      reading_journal_attachments: {
        Row: {
          created_at: string
          entry_id: string
          id: string
          mime_type: string
          size_bytes: number
          storage_path: string
        }
        Insert: {
          created_at?: string
          entry_id: string
          id?: string
          mime_type: string
          size_bytes: number
          storage_path: string
        }
        Update: {
          created_at?: string
          entry_id?: string
          id?: string
          mime_type?: string
          size_bytes?: number
          storage_path?: string
        }
        Relationships: [
          {
            foreignKeyName: "reading_journal_attachments_entry_id_fkey"
            columns: ["entry_id"]
            isOneToOne: false
            referencedRelation: "reading_journal_entries"
            referencedColumns: ["id"]
          },
        ]
      }
      reading_journal_entries: {
        Row: {
          body: string
          book_id: string
          chapter_id: string | null
          created_at: string
          entry_date: string
          id: string
          is_spoiler: boolean
          likes_count: number
          min_percent: number
          minutes_read: number | null
          mood_at_time: Database["public"]["Enums"]["mood_kind"] | null
          page_from: number | null
          page_to: number | null
          percent_at: number | null
          season_id: string | null
          title: string | null
          updated_at: string
          user_id: string
          visibility: Database["public"]["Enums"]["journal_visibility"]
        }
        Insert: {
          body: string
          book_id: string
          chapter_id?: string | null
          created_at?: string
          entry_date?: string
          id?: string
          is_spoiler?: boolean
          likes_count?: number
          min_percent?: number
          minutes_read?: number | null
          mood_at_time?: Database["public"]["Enums"]["mood_kind"] | null
          page_from?: number | null
          page_to?: number | null
          percent_at?: number | null
          season_id?: string | null
          title?: string | null
          updated_at?: string
          user_id: string
          visibility?: Database["public"]["Enums"]["journal_visibility"]
        }
        Update: {
          body?: string
          book_id?: string
          chapter_id?: string | null
          created_at?: string
          entry_date?: string
          id?: string
          is_spoiler?: boolean
          likes_count?: number
          min_percent?: number
          minutes_read?: number | null
          mood_at_time?: Database["public"]["Enums"]["mood_kind"] | null
          page_from?: number | null
          page_to?: number | null
          percent_at?: number | null
          season_id?: string | null
          title?: string | null
          updated_at?: string
          user_id?: string
          visibility?: Database["public"]["Enums"]["journal_visibility"]
        }
        Relationships: [
          {
            foreignKeyName: "reading_journal_entries_book_id_fkey"
            columns: ["book_id"]
            isOneToOne: false
            referencedRelation: "books"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_journal_entries_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "chapters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_journal_entries_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "v_chapter_audience"
            referencedColumns: ["chapter_id"]
          },
          {
            foreignKeyName: "reading_journal_entries_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_journal_entries_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_journal_entries_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_journal_entries_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      reading_journal_likes: {
        Row: {
          created_at: string
          entry_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          entry_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          entry_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "reading_journal_likes_entry_id_fkey"
            columns: ["entry_id"]
            isOneToOne: false
            referencedRelation: "reading_journal_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_journal_likes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_journal_likes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_journal_likes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      reading_list_collaborators: {
        Row: {
          added_at: string
          can_edit: boolean
          list_id: string
          user_id: string
        }
        Insert: {
          added_at?: string
          can_edit?: boolean
          list_id: string
          user_id: string
        }
        Update: {
          added_at?: string
          can_edit?: boolean
          list_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "reading_list_collaborators_list_id_fkey"
            columns: ["list_id"]
            isOneToOne: false
            referencedRelation: "reading_lists"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_list_collaborators_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_list_collaborators_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_list_collaborators_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      reading_list_items: {
        Row: {
          added_by: string | null
          book_id: string | null
          chapter_id: string | null
          created_at: string
          external_url: string | null
          id: string
          kind: Database["public"]["Enums"]["reading_list_item_kind"]
          list_id: string
          note: string | null
          position: number
          quote_text: string | null
        }
        Insert: {
          added_by?: string | null
          book_id?: string | null
          chapter_id?: string | null
          created_at?: string
          external_url?: string | null
          id?: string
          kind?: Database["public"]["Enums"]["reading_list_item_kind"]
          list_id: string
          note?: string | null
          position?: number
          quote_text?: string | null
        }
        Update: {
          added_by?: string | null
          book_id?: string | null
          chapter_id?: string | null
          created_at?: string
          external_url?: string | null
          id?: string
          kind?: Database["public"]["Enums"]["reading_list_item_kind"]
          list_id?: string
          note?: string | null
          position?: number
          quote_text?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "reading_list_items_added_by_fkey"
            columns: ["added_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_list_items_added_by_fkey"
            columns: ["added_by"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_list_items_added_by_fkey"
            columns: ["added_by"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "reading_list_items_book_id_fkey"
            columns: ["book_id"]
            isOneToOne: false
            referencedRelation: "books"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_list_items_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "chapters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_list_items_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "v_chapter_audience"
            referencedColumns: ["chapter_id"]
          },
          {
            foreignKeyName: "reading_list_items_list_id_fkey"
            columns: ["list_id"]
            isOneToOne: false
            referencedRelation: "reading_lists"
            referencedColumns: ["id"]
          },
        ]
      }
      reading_lists: {
        Row: {
          cover_url: string | null
          created_at: string
          description: string | null
          id: string
          is_collaborative: boolean
          items_count: number
          owner_id: string
          slug: string
          tags: string[] | null
          theme: string | null
          title: string
          updated_at: string
          visibility: Database["public"]["Enums"]["reading_list_visibility"]
        }
        Insert: {
          cover_url?: string | null
          created_at?: string
          description?: string | null
          id?: string
          is_collaborative?: boolean
          items_count?: number
          owner_id: string
          slug: string
          tags?: string[] | null
          theme?: string | null
          title: string
          updated_at?: string
          visibility?: Database["public"]["Enums"]["reading_list_visibility"]
        }
        Update: {
          cover_url?: string | null
          created_at?: string
          description?: string | null
          id?: string
          is_collaborative?: boolean
          items_count?: number
          owner_id?: string
          slug?: string
          tags?: string[] | null
          theme?: string | null
          title?: string
          updated_at?: string
          visibility?: Database["public"]["Enums"]["reading_list_visibility"]
        }
        Relationships: [
          {
            foreignKeyName: "reading_lists_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_lists_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reading_lists_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      seasons: {
        Row: {
          book_id: string
          cover_url: string | null
          created_at: string
          default_time: string | null
          description: string | null
          ends_at: string | null
          id: string
          number: number
          slug: string
          starts_at: string | null
          status: Database["public"]["Enums"]["cycle_status"]
          title: string
        }
        Insert: {
          book_id: string
          cover_url?: string | null
          created_at?: string
          default_time?: string | null
          description?: string | null
          ends_at?: string | null
          id?: string
          number: number
          slug: string
          starts_at?: string | null
          status?: Database["public"]["Enums"]["cycle_status"]
          title: string
        }
        Update: {
          book_id?: string
          cover_url?: string | null
          created_at?: string
          default_time?: string | null
          description?: string | null
          ends_at?: string | null
          id?: string
          number?: number
          slug?: string
          starts_at?: string | null
          status?: Database["public"]["Enums"]["cycle_status"]
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "seasons_book_id_fkey"
            columns: ["book_id"]
            isOneToOne: false
            referencedRelation: "books"
            referencedColumns: ["id"]
          },
        ]
      }
      social_render_jobs: {
        Row: {
          created_at: string
          error: string | null
          id: string
          image_url: string | null
          kind: Database["public"]["Enums"]["social_template_kind"]
          payload: Json
          rendered_at: string | null
          status: Database["public"]["Enums"]["social_render_status"]
          user_id: string
        }
        Insert: {
          created_at?: string
          error?: string | null
          id?: string
          image_url?: string | null
          kind: Database["public"]["Enums"]["social_template_kind"]
          payload?: Json
          rendered_at?: string | null
          status?: Database["public"]["Enums"]["social_render_status"]
          user_id: string
        }
        Update: {
          created_at?: string
          error?: string | null
          id?: string
          image_url?: string | null
          kind?: Database["public"]["Enums"]["social_template_kind"]
          payload?: Json
          rendered_at?: string | null
          status?: Database["public"]["Enums"]["social_render_status"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "social_render_jobs_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "social_render_jobs_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "social_render_jobs_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      user_achievements: {
        Row: {
          achievement_id: string
          unlocked_at: string
          user_id: string
        }
        Insert: {
          achievement_id: string
          unlocked_at?: string
          user_id: string
        }
        Update: {
          achievement_id?: string
          unlocked_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_achievements_achievement_id_fkey"
            columns: ["achievement_id"]
            isOneToOne: false
            referencedRelation: "achievements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_achievements_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_achievements_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_achievements_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      user_challenges: {
        Row: {
          challenge_id: string
          completed_at: string | null
          progress: number
          user_id: string
        }
        Insert: {
          challenge_id: string
          completed_at?: string | null
          progress?: number
          user_id: string
        }
        Update: {
          challenge_id?: string
          completed_at?: string | null
          progress?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_challenges_challenge_id_fkey"
            columns: ["challenge_id"]
            isOneToOne: false
            referencedRelation: "challenges"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_challenges_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_challenges_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_challenges_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      user_club_members: {
        Row: {
          club_id: string
          joined_at: string
          role: string
          user_id: string
        }
        Insert: {
          club_id: string
          joined_at?: string
          role?: string
          user_id: string
        }
        Update: {
          club_id?: string
          joined_at?: string
          role?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_club_members_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "user_clubs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_club_members_club_id_fkey"
            columns: ["club_id"]
            isOneToOne: false
            referencedRelation: "v_club_progress_panel"
            referencedColumns: ["club_id"]
          },
          {
            foreignKeyName: "user_club_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_club_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_club_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      user_clubs: {
        Row: {
          created_at: string
          current_book_id: string | null
          current_ends_at: string | null
          current_season_id: string | null
          current_started_at: string | null
          description: string | null
          id: string
          is_private: boolean
          name: string
          owner_id: string
          slug: string
        }
        Insert: {
          created_at?: string
          current_book_id?: string | null
          current_ends_at?: string | null
          current_season_id?: string | null
          current_started_at?: string | null
          description?: string | null
          id?: string
          is_private?: boolean
          name: string
          owner_id: string
          slug: string
        }
        Update: {
          created_at?: string
          current_book_id?: string | null
          current_ends_at?: string | null
          current_season_id?: string | null
          current_started_at?: string | null
          description?: string | null
          id?: string
          is_private?: boolean
          name?: string
          owner_id?: string
          slug?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_clubs_current_book_id_fkey"
            columns: ["current_book_id"]
            isOneToOne: false
            referencedRelation: "books"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_clubs_current_season_id_fkey"
            columns: ["current_season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_clubs_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_clubs_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_clubs_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      user_match_cache: {
        Row: {
          computed_at: string
          matched_id: string
          shared_books: number
          shared_moods: Database["public"]["Enums"]["mood_kind"][] | null
          similarity: number
          user_id: string
        }
        Insert: {
          computed_at?: string
          matched_id: string
          shared_books?: number
          shared_moods?: Database["public"]["Enums"]["mood_kind"][] | null
          similarity: number
          user_id: string
        }
        Update: {
          computed_at?: string
          matched_id?: string
          shared_books?: number
          shared_moods?: Database["public"]["Enums"]["mood_kind"][] | null
          similarity?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_match_cache_matched_id_fkey"
            columns: ["matched_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_match_cache_matched_id_fkey"
            columns: ["matched_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_match_cache_matched_id_fkey"
            columns: ["matched_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "user_match_cache_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_match_cache_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_match_cache_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      user_membership_perks: {
        Row: {
          expires_at: string | null
          granted_at: string
          payload: Json
          perk_code: string
          user_id: string
        }
        Insert: {
          expires_at?: string | null
          granted_at?: string
          payload?: Json
          perk_code: string
          user_id: string
        }
        Update: {
          expires_at?: string | null
          granted_at?: string
          payload?: Json
          perk_code?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_membership_perks_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_membership_perks_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_membership_perks_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      user_milestone_progress: {
        Row: {
          completed_at: string | null
          created_at: string
          milestone_id: string
          user_id: string
          xp_awarded: boolean
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          milestone_id: string
          user_id: string
          xp_awarded?: boolean
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          milestone_id?: string
          user_id?: string
          xp_awarded?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "user_milestone_progress_milestone_id_fkey"
            columns: ["milestone_id"]
            isOneToOne: false
            referencedRelation: "milestones"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_milestone_progress_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_milestone_progress_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_milestone_progress_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      user_progress: {
        Row: {
          chapter_id: string
          finished_at: string | null
          id: string
          percent: number
          started_at: string | null
          status: Database["public"]["Enums"]["shelf_status"]
          updated_at: string
          user_id: string
        }
        Insert: {
          chapter_id: string
          finished_at?: string | null
          id?: string
          percent?: number
          started_at?: string | null
          status?: Database["public"]["Enums"]["shelf_status"]
          updated_at?: string
          user_id: string
        }
        Update: {
          chapter_id?: string
          finished_at?: string | null
          id?: string
          percent?: number
          started_at?: string | null
          status?: Database["public"]["Enums"]["shelf_status"]
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_progress_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "chapters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_progress_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "v_chapter_audience"
            referencedColumns: ["chapter_id"]
          },
          {
            foreignKeyName: "user_progress_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_progress_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_progress_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      user_quiz_averages: {
        Row: {
          attempts_total: number
          average_percent: number
          best_percent: number
          last_attempt_at: string | null
          score_sum: number
          total_sum: number
          updated_at: string
          user_id: string
        }
        Insert: {
          attempts_total?: number
          average_percent?: number
          best_percent?: number
          last_attempt_at?: string | null
          score_sum?: number
          total_sum?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          attempts_total?: number
          average_percent?: number
          best_percent?: number
          last_attempt_at?: string | null
          score_sum?: number
          total_sum?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_quiz_averages_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_quiz_averages_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_quiz_averages_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      user_reading_embeddings: {
        Row: {
          embedding: string
          source_hash: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          embedding: string
          source_hash?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          embedding?: string
          source_hash?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_reading_embeddings_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_reading_embeddings_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_reading_embeddings_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      user_reading_preferences: {
        Row: {
          annual_goal_books: number | null
          annual_goal_pages: number | null
          avoided_content_warnings: string[] | null
          disliked_genres: string[] | null
          favorite_genres: string[] | null
          favorite_tropes: string[] | null
          preferred_moods: Database["public"]["Enums"]["mood_kind"][] | null
          preferred_pacing: Database["public"]["Enums"]["pace_kind"][] | null
          reading_language: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          annual_goal_books?: number | null
          annual_goal_pages?: number | null
          avoided_content_warnings?: string[] | null
          disliked_genres?: string[] | null
          favorite_genres?: string[] | null
          favorite_tropes?: string[] | null
          preferred_moods?: Database["public"]["Enums"]["mood_kind"][] | null
          preferred_pacing?: Database["public"]["Enums"]["pace_kind"][] | null
          reading_language?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          annual_goal_books?: number | null
          annual_goal_pages?: number | null
          avoided_content_warnings?: string[] | null
          disliked_genres?: string[] | null
          favorite_genres?: string[] | null
          favorite_tropes?: string[] | null
          preferred_moods?: Database["public"]["Enums"]["mood_kind"][] | null
          preferred_pacing?: Database["public"]["Enums"]["pace_kind"][] | null
          reading_language?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_reading_preferences_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_reading_preferences_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_reading_preferences_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      user_streaks: {
        Row: {
          current_streak: number
          last_activity_at: string | null
          longest_streak: number
          updated_at: string
          user_id: string
        }
        Insert: {
          current_streak?: number
          last_activity_at?: string | null
          longest_streak?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          current_streak?: number
          last_activity_at?: string | null
          longest_streak?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_streaks_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_streaks_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_streaks_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      user_subscriptions: {
        Row: {
          cancel_at_period_end: boolean
          canceled_at: string | null
          created_at: string
          current_period_end: string | null
          current_period_start: string | null
          id: string
          metadata: Json
          plan_id: string
          provider: Database["public"]["Enums"]["payment_provider"]
          provider_customer_id: string | null
          provider_subscription_id: string | null
          status: Database["public"]["Enums"]["subscription_status"]
          trial_end: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          cancel_at_period_end?: boolean
          canceled_at?: string | null
          created_at?: string
          current_period_end?: string | null
          current_period_start?: string | null
          id?: string
          metadata?: Json
          plan_id: string
          provider?: Database["public"]["Enums"]["payment_provider"]
          provider_customer_id?: string | null
          provider_subscription_id?: string | null
          status?: Database["public"]["Enums"]["subscription_status"]
          trial_end?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          cancel_at_period_end?: boolean
          canceled_at?: string | null
          created_at?: string
          current_period_end?: string | null
          current_period_start?: string | null
          id?: string
          metadata?: Json
          plan_id?: string
          provider?: Database["public"]["Enums"]["payment_provider"]
          provider_customer_id?: string | null
          provider_subscription_id?: string | null
          status?: Database["public"]["Enums"]["subscription_status"]
          trial_end?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_subscriptions_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "membership_plans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_subscriptions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_subscriptions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_subscriptions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      user_up_next: {
        Row: {
          added_at: string
          book_id: string
          position: number
          user_id: string
        }
        Insert: {
          added_at?: string
          book_id: string
          position: number
          user_id: string
        }
        Update: {
          added_at?: string
          book_id?: string
          position?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_up_next_book_id_fkey"
            columns: ["book_id"]
            isOneToOne: false
            referencedRelation: "books"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_up_next_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_up_next_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_up_next_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      user_xp: {
        Row: {
          season_id: string | null
          season_xp: number
          total_xp: number
          updated_at: string
          user_id: string
        }
        Insert: {
          season_id?: string | null
          season_xp?: number
          total_xp?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          season_id?: string | null
          season_xp?: number
          total_xp?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_xp_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_xp_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_xp_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_xp_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      video_timed_comments: {
        Row: {
          chapter_id: string
          content: string
          created_at: string
          id: string
          likes_count: number
          user_id: string
          video_sec: number
        }
        Insert: {
          chapter_id: string
          content: string
          created_at?: string
          id?: string
          likes_count?: number
          user_id: string
          video_sec: number
        }
        Update: {
          chapter_id?: string
          content?: string
          created_at?: string
          id?: string
          likes_count?: number
          user_id?: string
          video_sec?: number
        }
        Relationships: [
          {
            foreignKeyName: "video_timed_comments_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "chapters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "video_timed_comments_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "v_chapter_audience"
            referencedColumns: ["chapter_id"]
          },
          {
            foreignKeyName: "video_timed_comments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "video_timed_comments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "video_timed_comments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      xp_events: {
        Row: {
          amount: number
          created_at: string
          id: string
          ref_id: string | null
          source: Database["public"]["Enums"]["xp_source"]
          user_id: string
        }
        Insert: {
          amount: number
          created_at?: string
          id?: string
          ref_id?: string | null
          source: Database["public"]["Enums"]["xp_source"]
          user_id: string
        }
        Update: {
          amount?: number
          created_at?: string
          id?: string
          ref_id?: string | null
          source?: Database["public"]["Enums"]["xp_source"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "xp_events_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "xp_events_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "xp_events_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
    }
    Views: {
      v_book_community_stats: {
        Row: {
          avg_rating: number | null
          avg_spice: number | null
          avg_spice_level: number | null
          book_id: string | null
          mood_counts: Json | null
          mood_percent: Json | null
          mood_sample_size: number | null
          pace_percent: Json | null
          plot_vs_character_avg: number | null
          ratings_count: number | null
          review_count: number | null
          sample_size: number | null
          title: string | null
        }
        Relationships: []
      }
      v_chapter_audience: {
        Row: {
          avg_percent: number | null
          chapter_id: string | null
          finished_count: number | null
          not_started_count: number | null
          reading_count: number | null
          season_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "chapters_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
        ]
      }
      v_club_progress_panel: {
        Row: {
          avg_percent: number | null
          chapters_in_progress: number | null
          chapters_read: number | null
          club_id: string | null
          club_name: string | null
          current_book_id: string | null
          current_book_title: string | null
          current_ends_at: string | null
          current_season_id: string | null
          current_season_title: string | null
          current_started_at: string | null
          distinct_readers: number | null
          finished_count: number | null
          not_started_count: number | null
          reading_count: number | null
        }
        Relationships: [
          {
            foreignKeyName: "user_clubs_current_book_id_fkey"
            columns: ["current_book_id"]
            isOneToOne: false
            referencedRelation: "books"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_clubs_current_season_id_fkey"
            columns: ["current_season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
        ]
      }
      v_comments_visible: {
        Row: {
          chapter_id: string | null
          content: string | null
          created_at: string | null
          id: string | null
          is_locked: boolean | null
          is_spoiler: boolean | null
          likes_count: number | null
          parent_id: string | null
          replies_count: number | null
          user_id: string | null
        }
        Relationships: []
      }
      v_feed_post_counters: {
        Row: {
          comments_count: number | null
          fresh_comments_count: number | null
          fresh_likes_count: number | null
          likes_count: number | null
          post_id: string | null
          shares_count: number | null
        }
        Relationships: []
      }
      v_feed_posts_visible: {
        Row: {
          author_id: string | null
          body: string | null
          book_id: string | null
          chapter_id: string | null
          club_id: string | null
          comments_count: number | null
          cover_url: string | null
          created_at: string | null
          id: string | null
          is_locked: boolean | null
          is_spoiler: boolean | null
          kind: Database["public"]["Enums"]["feed_post_kind"] | null
          likes_count: number | null
          link_url: string | null
          metadata: Json | null
          min_percent: number | null
          quote_text: string | null
          season_id: string | null
          shares_count: number | null
          updated_at: string | null
          visibility: Database["public"]["Enums"]["feed_visibility"] | null
        }
        Relationships: []
      }
      v_host_prompt_results: {
        Row: {
          chapter_id: string | null
          option_0_count: number | null
          option_1_count: number | null
          option_2_count: number | null
          options: Json | null
          prompt_id: string | null
          question: string | null
          total_votes: number | null
        }
        Relationships: [
          {
            foreignKeyName: "host_prompts_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "chapters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "host_prompts_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "v_chapter_audience"
            referencedColumns: ["chapter_id"]
          },
        ]
      }
      v_profiles_public: {
        Row: {
          avatar_url: string | null
          bio: string | null
          created_at: string | null
          display_name: string | null
          id: string | null
          level: string | null
          username: string | null
        }
        Insert: {
          avatar_url?: string | null
          bio?: string | null
          created_at?: string | null
          display_name?: string | null
          id?: string | null
          level?: string | null
          username?: string | null
        }
        Update: {
          avatar_url?: string | null
          bio?: string | null
          created_at?: string | null
          display_name?: string | null
          id?: string | null
          level?: string | null
          username?: string | null
        }
        Relationships: []
      }
      v_quiz_questions_public: {
        Row: {
          chapter_id: string | null
          id: string | null
          options: Json | null
          position: number | null
          question: string | null
        }
        Insert: {
          chapter_id?: string | null
          id?: string | null
          options?: Json | null
          position?: number | null
          question?: string | null
        }
        Update: {
          chapter_id?: string | null
          id?: string | null
          options?: Json | null
          position?: number | null
          question?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "quiz_questions_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "chapters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quiz_questions_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "v_chapter_audience"
            referencedColumns: ["chapter_id"]
          },
        ]
      }
      v_season_ranking: {
        Row: {
          avatar_url: string | null
          display_name: string | null
          position: number | null
          season_id: string | null
          season_xp: number | null
          user_id: string | null
          username: string | null
        }
        Relationships: [
          {
            foreignKeyName: "user_xp_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_xp_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_xp_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "v_profiles_public"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_xp_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "v_user_reading_overview"
            referencedColumns: ["user_id"]
          },
        ]
      }
      v_user_reading_overview: {
        Row: {
          books_dnf: number | null
          books_read: number | null
          books_reading: number | null
          books_want: number | null
          read_today: number | null
          reading_days: number | null
          total_minutes: number | null
          user_id: string | null
        }
        Relationships: []
      }
      v_video_timed_comment_stats: {
        Row: {
          chapter_id: string | null
          comment_count: number | null
          distinct_commenters: number | null
          last_comment_at: string | null
          video_sec: number | null
        }
        Relationships: [
          {
            foreignKeyName: "video_timed_comments_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "chapters"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "video_timed_comments_chapter_id_fkey"
            columns: ["chapter_id"]
            isOneToOne: false
            referencedRelation: "v_chapter_audience"
            referencedColumns: ["chapter_id"]
          },
        ]
      }
    }
    Functions: {
      apply_stripe_subscription_event: {
        Args: {
          p_cancel_at_period_end: boolean
          p_customer_id: string
          p_event_id: string
          p_event_type: string
          p_metadata_user: string
          p_payload: Json
          p_period_end: string
          p_period_start: string
          p_plan_id: string
          p_status: string
          p_subscription_id: string
        }
        Returns: string
      }
      award_daily_streak_bonus: { Args: { p_user: string }; Returns: boolean }
      award_xp: {
        Args: {
          p_amount: number
          p_ref?: string
          p_source: Database["public"]["Enums"]["xp_source"]
          p_user: string
        }
        Returns: undefined
      }
      build_user_reading_snapshot: { Args: { p_user: string }; Returns: string }
      cast_book_poll_vote: {
        Args: { p_option: string; p_poll: string; p_user: string }
        Returns: number
      }
      claim_newsletter_dispatch: {
        Args: { p_audience_key: string; p_issue: string }
        Returns: boolean
      }
      claim_newsletter_dispatch_token: {
        Args: { p_audience_key: string; p_issue: string }
        Returns: string
      }
      consume_quiz_rate_limit: {
        Args: { p_chapter: string; p_user: string }
        Returns: boolean
      }
      deliver_meeting_reminder: {
        Args: { p_meeting: string; p_user: string; p_window?: string }
        Returns: boolean
      }
      finish_newsletter_dispatch: {
        Args: { p_audience_key: string; p_issue: string; p_success: boolean }
        Returns: undefined
      }
      finish_newsletter_dispatch_owned: {
        Args: {
          p_audience_key: string
          p_claim_token: string
          p_issue: string
          p_success: boolean
        }
        Returns: undefined
      }
      generate_milestones_for_season: {
        Args: { p_season: string }
        Returns: undefined
      }
      get_my_profile_private: {
        Args: never
        Returns: {
          lgpd_consent: boolean
          lgpd_consent_at: string
          onboarding_done: boolean
          whatsapp: string
        }[]
      }
      get_reader_matches: {
        Args: { p_limit?: number; p_user: string }
        Returns: {
          avatar_url: string
          display_name: string
          matched_id: string
          shared_books: number
          shared_moods: string[]
          similarity: number
          username: string
        }[]
      }
      get_reader_overlaps: {
        Args: { p_candidates: string[]; p_user: string }
        Returns: {
          matched_id: string
          shared_books: number
          shared_moods: Database["public"]["Enums"]["mood_kind"][]
        }[]
      }
      is_admin: { Args: never; Returns: boolean }
      link_stripe_customer: {
        Args: { p_customer_id: string; p_user: string }
        Returns: undefined
      }
      match_books: {
        Args: {
          match_count: number
          match_threshold: number
          query_embedding: string
        }
        Returns: {
          id: string
          similarity: number
          title: string
        }[]
      }
      match_readers: {
        Args: {
          match_count: number
          match_threshold: number
          p_user: string
          query_embedding: string
        }
        Returns: {
          avatar_url: string
          display_name: string
          similarity: number
          user_id: string
          username: string
        }[]
      }
      record_quiz_attempt: {
        Args: {
          p_answers: Json
          p_chapter: string
          p_request_id: string
          p_score: number
          p_total: number
          p_user: string
        }
        Returns: {
          attempt_id: string
          duplicate: boolean
          score: number
          total: number
        }[]
      }
      refresh_book_mood_stats: { Args: { p_book: string }; Returns: undefined }
      set_my_lgpd_consent: { Args: { p_consent: boolean }; Returns: undefined }
      show_limit: { Args: never; Returns: number }
      show_trgm: { Args: { "": string }; Returns: string[] }
      take_rate_limit: {
        Args: {
          p_bucket: string
          p_limit: number
          p_user: string
          p_window_seconds: number
        }
        Returns: boolean
      }
      unaccent: { Args: { "": string }; Returns: string }
    }
    Enums: {
      activity_kind:
        | "quiz"
        | "crossword"
        | "word_search"
        | "poll"
        | "trivia"
        | "flashcards"
        | "debate_prompt"
        | "drawing_prompt"
        | "roleplay"
        | "essay_prompt"
        | "timed_challenge"
      activity_status: "draft" | "published" | "archived"
      content_warning_severity: "minor" | "moderate" | "graphic"
      cycle_status: "planned" | "enrolling" | "active" | "finished"
      editorial_pick_kind:
        | "book_of_the_month"
        | "editorial_pick"
        | "community_pick"
        | "staff_pick"
      extra_content_kind:
        | "pdf"
        | "slides"
        | "audio"
        | "video"
        | "link"
        | "spreadsheet"
        | "deck"
        | "notebook"
        | "dataset"
        | "template"
      feed_post_kind:
        | "quote"
        | "review"
        | "shelf_update"
        | "progress"
        | "list"
        | "club_invite"
        | "link"
        | "photo"
        | "poll"
      feed_visibility: "public" | "followers" | "club" | "private"
      follow_status: "pending" | "accepted" | "blocked"
      journal_visibility: "private" | "friends" | "club" | "public"
      meeting_kind: "online" | "in_person" | "hybrid"
      meeting_status: "scheduled" | "live" | "done" | "cancelled"
      member_tier: "free" | "plus" | "pro" | "patron" | "corporate"
      mood_kind:
        | "adventurous"
        | "emotional"
        | "dark"
        | "funny"
        | "hopeful"
        | "informative"
        | "inspiring"
        | "lighthearted"
        | "mysterious"
        | "reflective"
        | "sad"
        | "tense"
        | "challenging"
      newsletter_frequency: "daily" | "weekly" | "monthly" | "special_only"
      newsletter_status:
        | "pending"
        | "confirmed"
        | "unsubscribed"
        | "bounced"
        | "complained"
      notification_kind:
        | "new_chapter"
        | "meeting_reminder"
        | "reply"
        | "mention"
        | "badge_unlocked"
        | "poll_open"
      pace_kind: "slow" | "medium" | "fast"
      payment_provider: "stripe" | "mercado_pago" | "pagseguro" | "manual"
      poll_status: "open" | "closed"
      proposal_status: "pending" | "approved" | "rejected" | "winner"
      reaction_kind: "like" | "love" | "fire" | "clap" | "thinking"
      reading_list_item_kind: "book" | "chapter" | "quote" | "external"
      reading_list_visibility: "private" | "unlisted" | "public"
      shelf_status: "want_to_read" | "reading" | "read" | "dnf"
      social_render_status: "queued" | "rendered" | "failed" | "expired"
      social_template_kind:
        | "quote_card"
        | "progress_card"
        | "milestone_card"
        | "review_card"
        | "list_card"
        | "aura_card"
        | "streak_card"
      subscription_status:
        | "trialing"
        | "active"
        | "past_due"
        | "canceled"
        | "paused"
        | "incomplete"
      user_role: "reader" | "ambassador" | "editor" | "admin"
      xp_source:
        | "join_meeting"
        | "finish_chapter"
        | "comment"
        | "quiz_answer"
        | "finish_book"
        | "streak_bonus"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      activity_kind: [
        "quiz",
        "crossword",
        "word_search",
        "poll",
        "trivia",
        "flashcards",
        "debate_prompt",
        "drawing_prompt",
        "roleplay",
        "essay_prompt",
        "timed_challenge",
      ],
      activity_status: ["draft", "published", "archived"],
      content_warning_severity: ["minor", "moderate", "graphic"],
      cycle_status: ["planned", "enrolling", "active", "finished"],
      editorial_pick_kind: [
        "book_of_the_month",
        "editorial_pick",
        "community_pick",
        "staff_pick",
      ],
      extra_content_kind: [
        "pdf",
        "slides",
        "audio",
        "video",
        "link",
        "spreadsheet",
        "deck",
        "notebook",
        "dataset",
        "template",
      ],
      feed_post_kind: [
        "quote",
        "review",
        "shelf_update",
        "progress",
        "list",
        "club_invite",
        "link",
        "photo",
        "poll",
      ],
      feed_visibility: ["public", "followers", "club", "private"],
      follow_status: ["pending", "accepted", "blocked"],
      journal_visibility: ["private", "friends", "club", "public"],
      meeting_kind: ["online", "in_person", "hybrid"],
      meeting_status: ["scheduled", "live", "done", "cancelled"],
      member_tier: ["free", "plus", "pro", "patron", "corporate"],
      mood_kind: [
        "adventurous",
        "emotional",
        "dark",
        "funny",
        "hopeful",
        "informative",
        "inspiring",
        "lighthearted",
        "mysterious",
        "reflective",
        "sad",
        "tense",
        "challenging",
      ],
      newsletter_frequency: ["daily", "weekly", "monthly", "special_only"],
      newsletter_status: [
        "pending",
        "confirmed",
        "unsubscribed",
        "bounced",
        "complained",
      ],
      notification_kind: [
        "new_chapter",
        "meeting_reminder",
        "reply",
        "mention",
        "badge_unlocked",
        "poll_open",
      ],
      pace_kind: ["slow", "medium", "fast"],
      payment_provider: ["stripe", "mercado_pago", "pagseguro", "manual"],
      poll_status: ["open", "closed"],
      proposal_status: ["pending", "approved", "rejected", "winner"],
      reaction_kind: ["like", "love", "fire", "clap", "thinking"],
      reading_list_item_kind: ["book", "chapter", "quote", "external"],
      reading_list_visibility: ["private", "unlisted", "public"],
      shelf_status: ["want_to_read", "reading", "read", "dnf"],
      social_render_status: ["queued", "rendered", "failed", "expired"],
      social_template_kind: [
        "quote_card",
        "progress_card",
        "milestone_card",
        "review_card",
        "list_card",
        "aura_card",
        "streak_card",
      ],
      subscription_status: [
        "trialing",
        "active",
        "past_due",
        "canceled",
        "paused",
        "incomplete",
      ],
      user_role: ["reader", "ambassador", "editor", "admin"],
      xp_source: [
        "join_meeting",
        "finish_chapter",
        "comment",
        "quiz_answer",
        "finish_book",
        "streak_bonus",
      ],
    },
  },
} as const
