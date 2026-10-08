-- >>> 20260101002300_rls_complement.sql
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

-- >>> 20260101002400_views_and_counters.sql
-- Source: SDDBD2.md section 6.3; relation-dependent views are in blocked/.
-- 1. Contagem de respostas da enquete por opção ("Concordo/Discordo/Não sei")
-- =====================================================================
create or replace view public.v_host_prompt_results as
select
  hp.id                                              as prompt_id,
  hp.chapter_id,
  hp.question,
  hp.options,
  coalesce(sum(case when v.option_idx = 0 then 1 else 0 end), 0) as option_0_count,
  coalesce(sum(case when v.option_idx = 1 then 1 else 0 end), 0) as option_1_count,
  coalesce(sum(case when v.option_idx = 2 then 1 else 0 end), 0) as option_2_count,
  count(v.user_id)                                              as total_votes
from public.host_prompts hp
left join public.host_prompt_votes v on v.prompt_id = hp.id
group by hp.id, hp.chapter_id, hp.question, hp.options;

-- =====================================================================

-- 2. Pessoas que comentaram cada trecho do vídeo
-- =====================================================================
create or replace view public.v_video_timed_comment_stats as
select
  vtc.chapter_id,
  vtc.video_sec,
  count(distinct vtc.user_id)              as distinct_commenters,
  count(*)                                 as comment_count,
  max(vtc.created_at)                      as last_comment_at
from public.video_timed_comments vtc
group by vtc.chapter_id, vtc.video_sec;
create index if not exists vtc_sec_idx on public.video_timed_comments (chapter_id, video_sec);

-- =====================================================================

-- 4. Estatísticas de usuário (para dashboard de stats)
-- =====================================================================
create or replace view public.v_user_reading_overview as
select
  p.id                                                     as user_id,
  count(distinct up.id) filter (where up.status = 'read')  as books_read,
  count(distinct up.id) filter (where up.status = 'reading') as books_reading,
  count(distinct up.id) filter (where up.status = 'want_to_read') as books_want,
  count(distinct up.id) filter (where up.status = 'dnf')   as books_dnf,
  coalesce(sum(rje.minutes_read), 0)                       as total_minutes,
  coalesce(count(distinct rje.entry_date), 0)              as reading_days,
  coalesce(sum(case when rje.entry_date = current_date then 1 else 0 end), 0) as read_today
from public.profiles p
left join public.user_progress up on up.user_id = p.id
left join public.reading_journal_entries rje on rje.user_id = p.id
group by p.id;

-- =====================================================================

-- 6. Contadores agregados para o feed ("X pessoas comentaram este trecho")
-- =====================================================================
create or replace view public.v_feed_post_counters as
select
  fp.id                                as post_id,
  fp.likes_count,
  fp.comments_count,
  fp.shares_count,
  count(fpl.user_id)                   as fresh_likes_count,
  count(fpc.id)                        as fresh_comments_count
from public.feed_posts fp
left join public.feed_post_likes fpl on fpl.post_id = fp.id
left join public.feed_post_comments fpc on fpc.post_id = fp.id and fpc.deleted_at is null
where fp.deleted_at is null
group by fp.id, fp.likes_count, fp.comments_count, fp.shares_count;

-- =====================================================================

-- 7. View: match de leitores com interesses parecidos
-- =====================================================================
create or replace function public.get_reader_matches(p_user uuid, p_limit int default 20)
returns table (
  matched_id   uuid,
  username     citext,
  display_name text,
  avatar_url   text,
  similarity   numeric,
  shared_books int,
  shared_moods text[]
)
language sql stable as $$
  select
    umc.matched_id,
    p.username,
    p.display_name,
    p.avatar_url,
    umc.similarity,
    umc.shared_books,
    array(select unnest(umc.shared_moods)::text)
  from public.user_match_cache umc
  join public.profiles p on p.id = umc.matched_id
  where umc.user_id = p_user
  order by umc.similarity desc
  limit p_limit;
$$;

-- >>> 20260101002450_realtime_complement.sql
-- Source: SDDBD2.md. Generated idempotent migration.
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'feed_posts') THEN EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.feed_posts'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'feed_post_likes') THEN EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.feed_post_likes'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'feed_post_comments') THEN EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.feed_post_comments'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'reading_journal_entries') THEN EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.reading_journal_entries'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'reading_list_items') THEN EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.reading_list_items'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'user_match_cache') THEN EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.user_match_cache'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'newsletter_issues') THEN EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.newsletter_issues'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'book_content_warning_votes') THEN EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.book_content_warning_votes'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'book_mood_votes') THEN EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.book_mood_votes'; END IF; END $$;

-- >>> 20260101002500_functions_complement.sql
-- Source: SDDBD2.md section 6.4; build_user_reading_snapshot is in blocked/.
-- 1. Atualização materializada das médias de quiz a cada tentativa
-- =====================================================================
create or replace function public.refresh_user_quiz_averages()
returns trigger language plpgsql security definer as $$
declare
  v_user uuid := new.user_id;
begin
  insert into public.user_quiz_averages (
    user_id, attempts_total, score_sum, total_sum, average_percent,
    best_percent, last_attempt_at, updated_at
  )
  select
    v_user,
    count(*),
    coalesce(sum(score), 0),
    coalesce(sum(total), 0),
    case when coalesce(sum(total),0) = 0 then 0
         else round((sum(score)::numeric / sum(total)::numeric) * 100, 2) end,
    coalesce(max(case when total = 0 then 0
                      else round((score::numeric / total::numeric) * 100, 2) end), 0),
    max(created_at),
    now()
  from public.quiz_attempts
  where user_id = v_user
  on conflict (user_id) do update
    set attempts_total  = excluded.attempts_total,
        score_sum       = excluded.score_sum,
        total_sum       = excluded.total_sum,
        average_percent = excluded.average_percent,
        best_percent    = excluded.best_percent,
        last_attempt_at = excluded.last_attempt_at,
        updated_at      = now();
  return null;
end $$;

create trigger trg_refresh_user_quiz_averages
after insert on public.quiz_attempts
for each row execute function public.refresh_user_quiz_averages();

-- Média por capítulo
create or replace function public.refresh_chapter_quiz_averages()
returns trigger language plpgsql security definer as $$
declare
  v_chapter uuid := new.chapter_id;
begin
  insert into public.chapter_quiz_averages (
    chapter_id, attempts_total, average_percent, perfect_count, updated_at
  )
  select
    v_chapter,
    count(*),
    case when coalesce(sum(total),0) = 0 then 0
         else round((sum(score)::numeric / sum(total)::numeric) * 100, 2) end,
    count(*) filter (where score = total),
    now()
  from public.quiz_attempts
  where chapter_id = v_chapter
  on conflict (chapter_id) do update
    set attempts_total  = excluded.attempts_total,
        average_percent = excluded.average_percent,
        perfect_count   = excluded.perfect_count,
        updated_at      = now();
  return null;
end $$;

create trigger trg_refresh_chapter_quiz_averages
after insert on public.quiz_attempts
for each row execute function public.refresh_chapter_quiz_averages();

-- =====================================================================

-- 2. Recalcular book_mood_stats a partir dos votos
-- =====================================================================
create or replace function public.refresh_book_mood_stats(p_book uuid)
returns void language plpgsql security definer as $$
declare
  v_total int;
  v_mood  jsonb := '{}'::jsonb;
  v_pace  jsonb := '{"slow":0,"medium":0,"fast":0}'::jsonb;
  v_pvc   numeric := 0.50;
begin
  select count(*) into v_total from public.book_mood_votes where book_id = p_book;
  if v_total = 0 then
    insert into public.book_mood_stats (book_id, mood_counts, mood_percent, pace_percent,
                                        plot_vs_character_avg, sample_size, updated_at)
    values (p_book, '{}'::jsonb, '{}'::jsonb, v_pace, 0.50, 0, now())
    on conflict (book_id) do update
      set mood_counts = '{}'::jsonb,
          mood_percent = '{}'::jsonb,
          pace_percent = v_pace,
          plot_vs_character_avg = 0.50,
          sample_size = 0,
          updated_at = now();
    return;
  end if;

  -- contagem por mood
  select jsonb_object_agg(m, c)
    into v_mood
  from (
    select m::text as m, count(*) as c
    from public.book_mood_votes bmv, unnest(bmv.moods) m
    where bmv.book_id = p_book
    group by m
  ) t;

  -- contagem por pace
  select jsonb_build_object(
    'slow',   coalesce(count(*) filter (where pace = 'slow'),0),
    'medium', coalesce(count(*) filter (where pace = 'medium'),0),
    'fast',   coalesce(count(*) filter (where pace = 'fast'),0)
  ) into v_pace
  from public.book_mood_votes where book_id = p_book;

  select coalesce(avg(plot_vs_character), 0.50)
    into v_pvc
  from public.book_mood_votes
  where book_id = p_book and plot_vs_character is not null;

  insert into public.book_mood_stats (book_id, mood_counts, mood_percent, pace_percent,
                                      plot_vs_character_avg, sample_size, updated_at)
  values (
    p_book,
    coalesce(v_mood, '{}'::jsonb),
    (select coalesce(jsonb_object_agg(key, round((value::numeric / v_total), 4)), '{}'::jsonb)
       from jsonb_each_text(coalesce(v_mood,'{}'::jsonb))),
    (select jsonb_build_object(
       'slow',   round((coalesce((v_pace->>'slow')::numeric,   0) / v_total), 4),
       'medium', round((coalesce((v_pace->>'medium')::numeric, 0) / v_total), 4),
       'fast',   round((coalesce((v_pace->>'fast')::numeric,   0) / v_total), 4))),
    round(v_pvc, 2),
    v_total,
    now()
  )
  on conflict (book_id) do update
    set mood_counts = excluded.mood_counts,
        mood_percent = excluded.mood_percent,
        pace_percent = excluded.pace_percent,
        plot_vs_character_avg = excluded.plot_vs_character_avg,
        sample_size = excluded.sample_size,
        updated_at = now();
end $$;

create or replace function public.trg_refresh_book_mood_stats()
returns trigger language plpgsql as $$
begin
  perform public.refresh_book_mood_stats(coalesce(new.book_id, old.book_id));
  return null;
end $$;

create trigger trg_bmv_refresh
after insert or update or delete on public.book_mood_votes
for each row execute function public.trg_refresh_book_mood_stats();

-- =====================================================================

-- 3. Recalcular community_votes de content warnings
-- =====================================================================
create or replace function public.refresh_content_warning_votes()
returns trigger language plpgsql security definer as $$
declare
  v_row uuid := coalesce(new.warning_row_id, old.warning_row_id);
begin
  update public.book_content_warnings
     set community_votes = (
       select count(*) from public.book_content_warning_votes
        where warning_row_id = v_row and agrees = true
     ) - (
       select count(*) from public.book_content_warning_votes
        where warning_row_id = v_row and agrees = false
     )
   where id = v_row;
  return null;
end $$;

create trigger trg_bcwv_refresh
after insert or update or delete on public.book_content_warning_votes
for each row execute function public.refresh_content_warning_votes();

-- =====================================================================

-- 4. Contadores do feed
-- =====================================================================
create or replace function public.bump_feed_post_counters()
returns trigger language plpgsql as $$
begin
  if tg_table_name = 'feed_post_likes' then
    if tg_op = 'INSERT' then
      update public.feed_posts set likes_count = likes_count + 1 where id = new.post_id;
    elsif tg_op = 'DELETE' then
      update public.feed_posts set likes_count = greatest(likes_count - 1, 0) where id = old.post_id;
    end if;
  elsif tg_table_name = 'feed_post_comments' then
    if tg_op = 'INSERT' then
      update public.feed_posts set comments_count = comments_count + 1 where id = new.post_id;
    elsif tg_op = 'DELETE' then
      update public.feed_posts set comments_count = greatest(comments_count - 1, 0) where id = old.post_id;
    end if;
  end if;
  return null;
end $$;

create trigger trg_feed_likes_counters
after insert or delete on public.feed_post_likes
for each row execute function public.bump_feed_post_counters();

create trigger trg_feed_comments_counters
after insert or delete on public.feed_post_comments
for each row execute function public.bump_feed_post_counters();

-- =====================================================================

-- 5. Contadores do diário (likes em entradas públicas)
-- =====================================================================
create or replace function public.bump_journal_likes()
returns trigger language plpgsql as $$
begin
  if tg_table_name = 'feed_post_likes' then
    return null;
  end if;
  return null;
end $$;

-- =====================================================================

-- 6. Milestones automáticos por capítulo
-- =====================================================================
create or replace function public.generate_milestones_for_season(p_season uuid)
returns void language plpgsql security definer as $$
declare
  v_book       uuid;
  v_chapter    record;
  v_position   int := 0;
begin
  select book_id into v_book from public.seasons where id = p_season;
  if v_book is null then return; end if;

  for v_chapter in
    select id, number, title from public.chapters
     where season_id = p_season
     order by number
  loop
    v_position := v_position + 1;
    insert into public.milestones (
      chapter_id, season_id, book_id, position, title, description, kind
    )
    values (
      v_chapter.id, p_season, v_book, v_position,
      format('Marco %s — %s', v_position, v_chapter.title),
      'Marco gerado automaticamente a partir do capítulo.',
      'auto'
    )
    on conflict (season_id, position) do nothing;
  end loop;
end $$;

-- =====================================================================

-- 7. Recalcular metas anuais
-- =====================================================================
create or replace function public.refresh_reading_goal_progress()
returns trigger language plpgsql security definer as $$
declare
  v_user uuid := coalesce(new.user_id, old.user_id);
  v_year int := extract(year from current_date)::int;
  v_goal uuid;
begin
  select id into v_goal from public.reading_goals
   where user_id = v_user and year = v_year;
  if v_goal is null then return null; end if;

  insert into public.reading_goal_progress (goal_id, books_done, pages_done, minutes_done, updated_at)
  select
    v_goal,
    (select count(*) from public.user_progress
       where user_id = v_user and status = 'read'
         and finished_at >= make_date(v_year,1,1)),
    (select coalesce(sum(page_to - page_from), 0) from public.reading_journal_entries
       where user_id = v_user and entry_date >= make_date(v_year,1,1)),
    (select coalesce(sum(minutes_read), 0) from public.reading_journal_entries
       where user_id = v_user and entry_date >= make_date(v_year,1,1)),
    now()
  on conflict (goal_id) do update
    set books_done   = excluded.books_done,
        pages_done   = excluded.pages_done,
        minutes_done = excluded.minutes_done,
        updated_at   = now();
  return null;
end $$;

create trigger trg_goal_progress_refresh
after insert or update or delete on public.user_progress
for each row execute function public.refresh_reading_goal_progress();

create trigger trg_goal_progress_refresh_journal
after insert or update or delete on public.reading_journal_entries
for each row execute function public.refresh_reading_goal_progress();

-- =====================================================================

-- 9. RPC: match de leitores (similaridade de embeddings)
-- =====================================================================
create or replace function public.match_readers(
  query_embedding vector(1536),
  match_threshold float,
  match_count     int,
  p_user          uuid
) returns table (
  user_id      uuid,
  username     citext,
  display_name text,
  avatar_url   text,
  similarity   float
)
language sql stable as $$
  select
    ure.user_id,
    p.username,
    p.display_name,
    p.avatar_url,
    1 - (ure.embedding <=> query_embedding) as similarity
  from public.user_reading_embeddings ure
  join public.profiles p on p.id = ure.user_id
  where ure.user_id <> p_user
    and ure.embedding is not null
    and 1 - (ure.embedding <=> query_embedding) > match_threshold
  order by ure.embedding <=> query_embedding
  limit match_count;
$$;
