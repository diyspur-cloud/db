-- Source: SDDBD2.md. Generated idempotent migration.
-- Habilitar RLS em todas as tabelas do complemento
alter table public.content_warnings                 enable row level security;
alter table public.book_content_warnings            enable row level security;
alter table public.book_content_warning_votes       enable row level security;
alter table public.book_mood_stats                  enable row level security;
alter table public.book_mood_votes                  enable row level security;
alter table public.mood_labels                      enable row level security;
alter table public.editorial_picks                  enable row level security;
alter table public.buddy_reads                      enable row level security;
alter table public.buddy_read_members               enable row level security;
alter table public.buddy_read_checkpoints           enable row level security;
alter table public.reading_journal_entries          enable row level security;
alter table public.reading_journal_attachments      enable row level security;
alter table public.reading_lists                    enable row level security;
alter table public.reading_list_items               enable row level security;
alter table public.reading_list_collaborators       enable row level security;
alter table public.user_up_next                     enable row level security;
alter table public.milestones                       enable row level security;
alter table public.user_milestone_progress          enable row level security;
alter table public.user_quiz_averages               enable row level security;
alter table public.chapter_quiz_averages            enable row level security;
alter table public.reading_goals                    enable row level security;
alter table public.reading_goal_progress            enable row level security;
alter table public.challenge_prompts                enable row level security;
alter table public.feed_posts                       enable row level security;
alter table public.feed_post_media                  enable row level security;
alter table public.feed_post_likes                  enable row level security;
alter table public.feed_post_comments               enable row level security;
alter table public.follows                          enable row level security;
alter table public.user_reading_preferences         enable row level security;
alter table public.user_reading_embeddings          enable row level security;
alter table public.user_match_cache                 enable row level security;
alter table public.membership_plans                 enable row level security;
alter table public.user_subscriptions               enable row level security;
alter table public.payment_events                   enable row level security;
alter table public.user_membership_perks            enable row level security;
alter table public.newsletter_subscribers           enable row level security;
alter table public.newsletter_issues                enable row level security;
alter table public.newsletter_deliveries            enable row level security;
alter table public.affiliate_clicks                 enable row level security;
alter table public.chapter_extra_content            enable row level security;
alter table public.chapter_activities               enable row level security;
alter table public.chapter_activity_attempts        enable row level security;
alter table public.chapter_prompts                  enable row level security;
alter table public.chapter_prompt_responses         enable row level security;

-- ============================================================
-- Conteúdo público de catálogo
-- ============================================================
DROP POLICY IF EXISTS "cw_read" ON public.content_warnings;
CREATE POLICY "cw_read" ON public.content_warnings      for select using (true);
DROP POLICY IF EXISTS "bcw_read" ON public.book_content_warnings;
CREATE POLICY "bcw_read" ON public.book_content_warnings for select using (true);
DROP POLICY IF EXISTS "bcw_admin_write" ON public.book_content_warnings;
CREATE POLICY "bcw_admin_write" ON public.book_content_warnings for all
  using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "bcwv_own" ON public.book_content_warning_votes;
CREATE POLICY "bcwv_own" ON public.book_content_warning_votes for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
DROP POLICY IF EXISTS "bms_read" ON public.book_mood_stats;
CREATE POLICY "bms_read" ON public.book_mood_stats        for select using (true);
DROP POLICY IF EXISTS "bmv_read" ON public.book_mood_votes;
CREATE POLICY "bmv_read" ON public.book_mood_votes        for select using (true);
DROP POLICY IF EXISTS "bmv_own" ON public.book_mood_votes;
CREATE POLICY "bmv_own" ON public.book_mood_votes        for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
DROP POLICY IF EXISTS "mood_labels_read" ON public.mood_labels;
CREATE POLICY "mood_labels_read" ON public.mood_labels            for select using (true);
DROP POLICY IF EXISTS "editorial_read" ON public.editorial_picks;
CREATE POLICY "editorial_read" ON public.editorial_picks        for select using (is_active);
DROP POLICY IF EXISTS "editorial_admin" ON public.editorial_picks;
CREATE POLICY "editorial_admin" ON public.editorial_picks        for all
  using (public.is_admin()) with check (public.is_admin());

-- ============================================================
-- Buddy Reads
-- ============================================================
DROP POLICY IF EXISTS "buddy_reads_visible" ON public.buddy_reads;
CREATE POLICY "buddy_reads_visible" ON public.buddy_reads for select
  using (
    not is_private
    or owner_id = auth.uid()
    or exists (select 1 from public.buddy_read_members m
               where m.buddy_read_id = id and m.user_id = auth.uid())
  );
DROP POLICY IF EXISTS "buddy_reads_owner_write" ON public.buddy_reads;
CREATE POLICY "buddy_reads_owner_write" ON public.buddy_reads for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
DROP POLICY IF EXISTS "buddy_members_read" ON public.buddy_read_members;
CREATE POLICY "buddy_members_read" ON public.buddy_read_members for select
  using (
    exists (select 1 from public.buddy_reads br
            where br.id = buddy_read_id
              and (not br.is_private or br.owner_id = auth.uid()))
  );
DROP POLICY IF EXISTS "buddy_members_self_join" ON public.buddy_read_members;
CREATE POLICY "buddy_members_self_join" ON public.buddy_read_members for insert
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.buddy_reads br
                where br.id = buddy_read_id
                  and (not br.is_private or br.owner_id = auth.uid()
                       or exists (select 1 from public.buddy_read_members m2
                                  where m2.buddy_read_id = br.id and m2.user_id = auth.uid())))
  );
DROP POLICY IF EXISTS "buddy_members_self_leave" ON public.buddy_read_members;
CREATE POLICY "buddy_members_self_leave" ON public.buddy_read_members for delete
  using (user_id = auth.uid()
         or exists (select 1 from public.buddy_reads br
                    where br.id = buddy_read_id and br.owner_id = auth.uid()));
DROP POLICY IF EXISTS "buddy_checkpoints_read" ON public.buddy_read_checkpoints;
CREATE POLICY "buddy_checkpoints_read" ON public.buddy_read_checkpoints for select
  using (
    exists (select 1 from public.buddy_reads br
            where br.id = buddy_read_id
              and (not br.is_private or br.owner_id = auth.uid()
                   or exists (select 1 from public.buddy_read_members m
                              where m.buddy_read_id = br.id and m.user_id = auth.uid())))
  );
DROP POLICY IF EXISTS "buddy_checkpoints_write" ON public.buddy_read_checkpoints;
CREATE POLICY "buddy_checkpoints_write" ON public.buddy_read_checkpoints for all
  using (
    exists (select 1 from public.buddy_reads br
            where br.id = buddy_read_id and br.owner_id = auth.uid())
  )
  with check (
    exists (select 1 from public.buddy_reads br
            where br.id = buddy_read_id and br.owner_id = auth.uid())
  );

-- ============================================================
-- Diário de leitura
-- ============================================================
DROP POLICY IF EXISTS "journal_read_own" ON public.reading_journal_entries;
CREATE POLICY "journal_read_own" ON public.reading_journal_entries for select
  using (
    user_id = auth.uid()
    or visibility = 'public'
    or (visibility = 'friends' and exists (
         select 1 from public.follows f
          where f.follower_id = auth.uid()
            and f.followed_id = reading_journal_entries.user_id
            and f.status = 'accepted'))
    or (visibility = 'club' and exists (
         select 1 from public.user_club_members m1
         join public.user_club_members m2 on m1.club_id = m2.club_id
         where m1.user_id = auth.uid()
           and m2.user_id = reading_journal_entries.user_id))
  );
DROP POLICY IF EXISTS "journal_write_own" ON public.reading_journal_entries;
CREATE POLICY "journal_write_own" ON public.reading_journal_entries for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
DROP POLICY IF EXISTS "journal_attach_read" ON public.reading_journal_attachments;
CREATE POLICY "journal_attach_read" ON public.reading_journal_attachments for select
  using (
    exists (select 1 from public.reading_journal_entries e
            where e.id = entry_id
              and (e.user_id = auth.uid() or e.visibility = 'public'))
  );
DROP POLICY IF EXISTS "journal_attach_write" ON public.reading_journal_attachments;
CREATE POLICY "journal_attach_write" ON public.reading_journal_attachments for all
  using (
    exists (select 1 from public.reading_journal_entries e
            where e.id = entry_id and e.user_id = auth.uid())
  )
  with check (
    exists (select 1 from public.reading_journal_entries e
            where e.id = entry_id and e.user_id = auth.uid())
  );

-- ============================================================
-- Listas personalizadas
-- ============================================================
DROP POLICY IF EXISTS "lists_read" ON public.reading_lists;
CREATE POLICY "lists_read" ON public.reading_lists for select
  using (
    visibility = 'public'
    or owner_id = auth.uid()
    or exists (select 1 from public.reading_list_collaborators c
               where c.list_id = id and c.user_id = auth.uid())
  );
DROP POLICY IF EXISTS "lists_owner_write" ON public.reading_lists;
CREATE POLICY "lists_owner_write" ON public.reading_lists for all
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
DROP POLICY IF EXISTS "list_items_read" ON public.reading_list_items;
CREATE POLICY "list_items_read" ON public.reading_list_items for select
  using (
    exists (select 1 from public.reading_lists l
            where l.id = list_id
              and (l.visibility = 'public'
                   or l.owner_id = auth.uid()
                   or exists (select 1 from public.reading_list_collaborators c
                              where c.list_id = l.id and c.user_id = auth.uid())))
  );
DROP POLICY IF EXISTS "list_items_write" ON public.reading_list_items;
CREATE POLICY "list_items_write" ON public.reading_list_items for all
  using (
    exists (select 1 from public.reading_lists l
            where l.id = list_id
              and (l.owner_id = auth.uid()
                   or (l.is_collaborative and exists (
                        select 1 from public.reading_list_collaborators c
                         where c.list_id = l.id and c.user_id = auth.uid() and c.can_edit))))
  )
  with check (true);
DROP POLICY IF EXISTS "list_collab_read" ON public.reading_list_collaborators;
CREATE POLICY "list_collab_read" ON public.reading_list_collaborators for select
  using (
    user_id = auth.uid()
    or exists (select 1 from public.reading_lists l
               where l.id = list_id and l.owner_id = auth.uid())
  );
DROP POLICY IF EXISTS "list_collab_owner" ON public.reading_list_collaborators;
CREATE POLICY "list_collab_owner" ON public.reading_list_collaborators for all
  using (
    exists (select 1 from public.reading_lists l
            where l.id = list_id and l.owner_id = auth.uid())
  )
  with check (true);

-- Up Next
DROP POLICY IF EXISTS "up_next_own" ON public.user_up_next;
CREATE POLICY "up_next_own" ON public.user_up_next for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ============================================================
-- Milestones
-- ============================================================
DROP POLICY IF EXISTS "milestones_read" ON public.milestones;
CREATE POLICY "milestones_read" ON public.milestones              for select using (true);
DROP POLICY IF EXISTS "milestones_admin" ON public.milestones;
CREATE POLICY "milestones_admin" ON public.milestones              for all
  using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "um_progress_read" ON public.user_milestone_progress;
CREATE POLICY "um_progress_read" ON public.user_milestone_progress for select using (true);
DROP POLICY IF EXISTS "um_progress_write" ON public.user_milestone_progress;
CREATE POLICY "um_progress_write" ON public.user_milestone_progress for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ============================================================
-- Médias de quiz
-- ============================================================
DROP POLICY IF EXISTS "uqa_read" ON public.user_quiz_averages;
CREATE POLICY "uqa_read" ON public.user_quiz_averages    for select using (true);
DROP POLICY IF EXISTS "uqa_admin_write" ON public.user_quiz_averages;
CREATE POLICY "uqa_admin_write" ON public.user_quiz_averages    for all
  using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "cqa_read" ON public.chapter_quiz_averages;
CREATE POLICY "cqa_read" ON public.chapter_quiz_averages for select using (true);

-- ============================================================
-- Metas e desafios
-- ============================================================
DROP POLICY IF EXISTS "goals_own" ON public.reading_goals;
CREATE POLICY "goals_own" ON public.reading_goals         for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
DROP POLICY IF EXISTS "goal_progress_read" ON public.reading_goal_progress;
CREATE POLICY "goal_progress_read" ON public.reading_goal_progress for select using (true);
DROP POLICY IF EXISTS "challenge_prompts_read" ON public.challenge_prompts;
CREATE POLICY "challenge_prompts_read" ON public.challenge_prompts     for select using (true);

-- ============================================================
-- Feed social
-- ============================================================
DROP POLICY IF EXISTS "feed_posts_read" ON public.feed_posts;
CREATE POLICY "feed_posts_read" ON public.feed_posts for select
  using (
    deleted_at is null and (
      visibility = 'public'
      or author_id = auth.uid()
      or (visibility = 'followers' and exists (
           select 1 from public.follows f
            where f.follower_id = auth.uid()
              and f.followed_id = feed_posts.author_id
              and f.status = 'accepted'))
      or (visibility = 'club' and exists (
           select 1 from public.user_club_members m
            where m.club_id = feed_posts.club_id and m.user_id = auth.uid()))
    )
  );
DROP POLICY IF EXISTS "feed_posts_author_write" ON public.feed_posts;
CREATE POLICY "feed_posts_author_write" ON public.feed_posts for all
  using (author_id = auth.uid()) with check (author_id = auth.uid());
DROP POLICY IF EXISTS "feed_media_read" ON public.feed_post_media;
CREATE POLICY "feed_media_read" ON public.feed_post_media for select
  using (exists (select 1 from public.feed_posts p
                 where p.id = post_id and p.deleted_at is null));
DROP POLICY IF EXISTS "feed_media_author" ON public.feed_post_media;
CREATE POLICY "feed_media_author" ON public.feed_post_media for all
  using (exists (select 1 from public.feed_posts p
                 where p.id = post_id and p.author_id = auth.uid()))
  with check (true);
DROP POLICY IF EXISTS "feed_likes_read" ON public.feed_post_likes;
CREATE POLICY "feed_likes_read" ON public.feed_post_likes    for select using (true);
DROP POLICY IF EXISTS "feed_likes_own" ON public.feed_post_likes;
CREATE POLICY "feed_likes_own" ON public.feed_post_likes    for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
DROP POLICY IF EXISTS "feed_comments_read" ON public.feed_post_comments;
CREATE POLICY "feed_comments_read" ON public.feed_post_comments for select
  using (deleted_at is null);
DROP POLICY IF EXISTS "feed_comments_write_own" ON public.feed_post_comments;
CREATE POLICY "feed_comments_write_own" ON public.feed_post_comments for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ============================================================
-- Seguir / preferências / embeddings / matches
-- ============================================================
DROP POLICY IF EXISTS "follows_read" ON public.follows;
CREATE POLICY "follows_read" ON public.follows for select using (true);
DROP POLICY IF EXISTS "follows_own" ON public.follows;
CREATE POLICY "follows_own" ON public.follows for all
  using (follower_id = auth.uid()) with check (follower_id = auth.uid());
DROP POLICY IF EXISTS "prefs_own" ON public.user_reading_preferences;
CREATE POLICY "prefs_own" ON public.user_reading_preferences for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
DROP POLICY IF EXISTS "embed_own_read" ON public.user_reading_embeddings;
CREATE POLICY "embed_own_read" ON public.user_reading_embeddings for select
  using (user_id = auth.uid());
DROP POLICY IF EXISTS "embed_admin" ON public.user_reading_embeddings;
CREATE POLICY "embed_admin" ON public.user_reading_embeddings for all
  using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "match_read_own" ON public.user_match_cache;
CREATE POLICY "match_read_own" ON public.user_match_cache for select
  using (user_id = auth.uid());

-- ============================================================
-- Monetização / Newsletter
-- ============================================================
DROP POLICY IF EXISTS "plans_read" ON public.membership_plans;
CREATE POLICY "plans_read" ON public.membership_plans for select using (is_active);
DROP POLICY IF EXISTS "plans_admin" ON public.membership_plans;
CREATE POLICY "plans_admin" ON public.membership_plans for all
  using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "subs_own_read" ON public.user_subscriptions;
CREATE POLICY "subs_own_read" ON public.user_subscriptions for select
  using (user_id = auth.uid() or public.is_admin());
DROP POLICY IF EXISTS "subs_admin" ON public.user_subscriptions;
CREATE POLICY "subs_admin" ON public.user_subscriptions for all
  using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "pevents_admin" ON public.payment_events;
CREATE POLICY "pevents_admin" ON public.payment_events for all
  using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "perks_own" ON public.user_membership_perks;
CREATE POLICY "perks_own" ON public.user_membership_perks for select
  using (user_id = auth.uid() or public.is_admin());

DROP POLICY IF EXISTS "news_self_read" ON public.newsletter_subscribers;
CREATE POLICY "news_self_read" ON public.newsletter_subscribers for select
  using (user_id = auth.uid() or public.is_admin());
DROP POLICY IF EXISTS "news_self_write" ON public.newsletter_subscribers;
CREATE POLICY "news_self_write" ON public.newsletter_subscribers for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
DROP POLICY IF EXISTS "news_admin" ON public.newsletter_subscribers;
CREATE POLICY "news_admin" ON public.newsletter_subscribers for all
  using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "news_issues_read" ON public.newsletter_issues;
CREATE POLICY "news_issues_read" ON public.newsletter_issues for select
  using (sent_at is not null or public.is_admin());
DROP POLICY IF EXISTS "news_issues_admin" ON public.newsletter_issues;
CREATE POLICY "news_issues_admin" ON public.newsletter_issues for all
  using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "news_deliv_self" ON public.newsletter_deliveries;
CREATE POLICY "news_deliv_self" ON public.newsletter_deliveries for select
  using (exists (select 1 from public.newsletter_subscribers s
                 where s.id = subscriber_id and s.user_id = auth.uid())
         or public.is_admin());
DROP POLICY IF EXISTS "news_deliv_admin" ON public.newsletter_deliveries;
CREATE POLICY "news_deliv_admin" ON public.newsletter_deliveries for all
  using (public.is_admin()) with check (public.is_admin());

DROP POLICY IF EXISTS "affiliate_insert_auth" ON public.affiliate_clicks;
CREATE POLICY "affiliate_insert_auth" ON public.affiliate_clicks for insert
  with check (auth.uid() = user_id or user_id is null);
DROP POLICY IF EXISTS "affiliate_admin_read" ON public.affiliate_clicks;
CREATE POLICY "affiliate_admin_read" ON public.affiliate_clicks for select
  using (public.is_admin());

-- ============================================================
-- Conteúdo extra e atividades
-- ============================================================
DROP POLICY IF EXISTS "cec_read" ON public.chapter_extra_content;
CREATE POLICY "cec_read" ON public.chapter_extra_content for select
  using (is_public or public.is_admin());
DROP POLICY IF EXISTS "cec_admin" ON public.chapter_extra_content;
CREATE POLICY "cec_admin" ON public.chapter_extra_content for all
  using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "ca_read" ON public.chapter_activities;
CREATE POLICY "ca_read" ON public.chapter_activities for select
  using (status = 'published' or public.is_admin());
DROP POLICY IF EXISTS "ca_admin" ON public.chapter_activities;
CREATE POLICY "ca_admin" ON public.chapter_activities for all
  using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "caa_own_read" ON public.chapter_activity_attempts;
CREATE POLICY "caa_own_read" ON public.chapter_activity_attempts for select
  using (user_id = auth.uid() or public.is_admin());
DROP POLICY IF EXISTS "caa_own_write" ON public.chapter_activity_attempts;
CREATE POLICY "caa_own_write" ON public.chapter_activity_attempts for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
DROP POLICY IF EXISTS "cp_read" ON public.chapter_prompts;
CREATE POLICY "cp_read" ON public.chapter_prompts for select using (true);
DROP POLICY IF EXISTS "cp_admin" ON public.chapter_prompts;
CREATE POLICY "cp_admin" ON public.chapter_prompts for all
  using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "cpr_read" ON public.chapter_prompt_responses;
CREATE POLICY "cpr_read" ON public.chapter_prompt_responses for select
  using (
    user_id = auth.uid()
    or visibility = 'public'
    or (visibility = 'friends' and exists (
         select 1 from public.follows f
          where f.follower_id = auth.uid()
            and f.followed_id = chapter_prompt_responses.user_id
            and f.status = 'accepted'))
  );
DROP POLICY IF EXISTS "cpr_own" ON public.chapter_prompt_responses;
CREATE POLICY "cpr_own" ON public.chapter_prompt_responses for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
