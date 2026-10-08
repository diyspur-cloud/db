-- Source: SDDBD2.md. Generated idempotent migration.
-- Habilitar RLS em todas as tabelas públicas
alter table public.profiles             enable row level security;
alter table public.authors              enable row level security;
alter table public.books                enable row level security;
alter table public.seasons              enable row level security;
alter table public.chapters             enable row level security;
alter table public.meetings             enable row level security;
alter table public.meeting_rsvps        enable row level security;
alter table public.user_progress        enable row level security;
alter table public.comments             enable row level security;
alter table public.reactions            enable row level security;
alter table public.host_prompts         enable row level security;
alter table public.host_prompt_votes    enable row level security;
alter table public.quiz_questions       enable row level security;
alter table public.quiz_attempts        enable row level security;
alter table public.quiz_answers         enable row level security;
alter table public.xp_events            enable row level security;
alter table public.user_xp              enable row level security;
alter table public.user_streaks         enable row level security;
alter table public.book_polls           enable row level security;
alter table public.book_poll_options    enable row level security;
alter table public.book_poll_votes      enable row level security;
alter table public.achievements         enable row level security;
alter table public.user_achievements    enable row level security;
alter table public.notifications        enable row level security;
alter table public.push_subscriptions   enable row level security;
alter table public.video_timed_comments enable row level security;
alter table public.challenges           enable row level security;
alter table public.user_challenges      enable row level security;
alter table public.user_clubs           enable row level security;
alter table public.user_club_members    enable row level security;

-- Helper: admin?
create or replace function public.is_admin() returns boolean language sql stable as $$
  select coalesce((select role = 'admin' from public.profiles where id = auth.uid()), false);
$$;

-- PROFILES
DROP POLICY IF EXISTS "profiles_select_all" ON public.profiles;
CREATE POLICY "profiles_select_all" ON public.profiles for select using (true);
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
CREATE POLICY "profiles_update_own" ON public.profiles for update
  using (auth.uid() = id) with check (auth.uid() = id);
DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
CREATE POLICY "profiles_insert_own" ON public.profiles for insert
  with check (auth.uid() = id);

-- CONTEÚDO PÚBLICO (leitura livre, escrita via service_role)
DROP POLICY IF EXISTS "authors_read" ON public.authors;
CREATE POLICY "authors_read" ON public.authors      for select using (true);
DROP POLICY IF EXISTS "books_read" ON public.books;
CREATE POLICY "books_read" ON public.books        for select using (true);
DROP POLICY IF EXISTS "seasons_read" ON public.seasons;
CREATE POLICY "seasons_read" ON public.seasons      for select using (true);
DROP POLICY IF EXISTS "chapters_read" ON public.chapters;
CREATE POLICY "chapters_read" ON public.chapters     for select using (true);
DROP POLICY IF EXISTS "meetings_read" ON public.meetings;
CREATE POLICY "meetings_read" ON public.meetings     for select using (true);
DROP POLICY IF EXISTS "prompts_read" ON public.host_prompts;
CREATE POLICY "prompts_read" ON public.host_prompts for select using (true);
DROP POLICY IF EXISTS "achievements_read" ON public.achievements;
CREATE POLICY "achievements_read" ON public.achievements for select using (true);
DROP POLICY IF EXISTS "challenges_read" ON public.challenges;
CREATE POLICY "challenges_read" ON public.challenges   for select using (true);

DROP POLICY IF EXISTS "authors_admin_write" ON public.authors;
CREATE POLICY "authors_admin_write" ON public.authors      for all
  using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "books_admin_write" ON public.books;
CREATE POLICY "books_admin_write" ON public.books        for all
  using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "seasons_admin_write" ON public.seasons;
CREATE POLICY "seasons_admin_write" ON public.seasons      for all
  using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "chapters_admin_write" ON public.chapters;
CREATE POLICY "chapters_admin_write" ON public.chapters     for all
  using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "meetings_admin_write" ON public.meetings;
CREATE POLICY "meetings_admin_write" ON public.meetings     for all
  using (public.is_admin()) with check (public.is_admin());
DROP POLICY IF EXISTS "prompts_admin_write" ON public.host_prompts;
CREATE POLICY "prompts_admin_write" ON public.host_prompts for all
  using (public.is_admin()) with check (public.is_admin());

-- PROGRESSO
DROP POLICY IF EXISTS "progress_self_read" ON public.user_progress;
CREATE POLICY "progress_self_read" ON public.user_progress for select
  using (auth.uid() = user_id);
DROP POLICY IF EXISTS "progress_self_write" ON public.user_progress;
CREATE POLICY "progress_self_write" ON public.user_progress for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- COMENTÁRIOS
DROP POLICY IF EXISTS "comments_read" ON public.comments;
CREATE POLICY "comments_read" ON public.comments for select using (deleted_at is null);
DROP POLICY IF EXISTS "comments_insert_auth" ON public.comments;
CREATE POLICY "comments_insert_auth" ON public.comments for insert
  with check (auth.uid() = user_id);
DROP POLICY IF EXISTS "comments_update_own" ON public.comments;
CREATE POLICY "comments_update_own" ON public.comments for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
DROP POLICY IF EXISTS "comments_delete_own_or_admin" ON public.comments;
CREATE POLICY "comments_delete_own_or_admin" ON public.comments for delete
  using (auth.uid() = user_id or public.is_admin());

-- REAÇÕES
DROP POLICY IF EXISTS "reactions_read" ON public.reactions;
CREATE POLICY "reactions_read" ON public.reactions for select using (true);
DROP POLICY IF EXISTS "reactions_own" ON public.reactions;
CREATE POLICY "reactions_own" ON public.reactions for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- QUIZ (perguntas: leitura autenticada; respostas: apenas dono)
DROP POLICY IF EXISTS "quiz_q_read_auth" ON public.quiz_questions;
CREATE POLICY "quiz_q_read_auth" ON public.quiz_questions for select
  using (auth.role() = 'authenticated');
DROP POLICY IF EXISTS "quiz_attempt_own" ON public.quiz_attempts;
CREATE POLICY "quiz_attempt_own" ON public.quiz_attempts for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
DROP POLICY IF EXISTS "quiz_answers_own" ON public.quiz_answers;
CREATE POLICY "quiz_answers_own" ON public.quiz_answers for all
  using (exists(select 1 from public.quiz_attempts a
                where a.id = attempt_id and a.user_id = auth.uid()))
  with check (exists(select 1 from public.quiz_attempts a
                where a.id = attempt_id and a.user_id = auth.uid()));

-- XP / STREAK (leitura pública agregada, escrita via service_role/trigger)
DROP POLICY IF EXISTS "xp_events_own_read" ON public.xp_events;
CREATE POLICY "xp_events_own_read" ON public.xp_events         for select using (auth.uid() = user_id);
DROP POLICY IF EXISTS "user_xp_read" ON public.user_xp;
CREATE POLICY "user_xp_read" ON public.user_xp           for select using (true);
DROP POLICY IF EXISTS "user_streaks_read" ON public.user_streaks;
CREATE POLICY "user_streaks_read" ON public.user_streaks      for select using (true);
DROP POLICY IF EXISTS "user_achievements_read" ON public.user_achievements;
CREATE POLICY "user_achievements_read" ON public.user_achievements for select using (true);

-- POLLS
DROP POLICY IF EXISTS "poll_read" ON public.book_polls;
CREATE POLICY "poll_read" ON public.book_polls        for select using (true);
DROP POLICY IF EXISTS "poll_opts_read" ON public.book_poll_options;
CREATE POLICY "poll_opts_read" ON public.book_poll_options for select using (true);
DROP POLICY IF EXISTS "poll_vote_own" ON public.book_poll_votes;
CREATE POLICY "poll_vote_own" ON public.book_poll_votes   for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- NOTIFICAÇÕES
DROP POLICY IF EXISTS "notif_own" ON public.notifications;
CREATE POLICY "notif_own" ON public.notifications      for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
DROP POLICY IF EXISTS "push_own" ON public.push_subscriptions;
CREATE POLICY "push_own" ON public.push_subscriptions for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- VIDEO TIMED COMMENTS
DROP POLICY IF EXISTS "vtc_read" ON public.video_timed_comments;
CREATE POLICY "vtc_read" ON public.video_timed_comments for select using (true);
DROP POLICY IF EXISTS "vtc_own" ON public.video_timed_comments;
CREATE POLICY "vtc_own" ON public.video_timed_comments for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- CLUBES UGC
DROP POLICY IF EXISTS "uclubs_read_public" ON public.user_clubs;
CREATE POLICY "uclubs_read_public" ON public.user_clubs for select
  using (not is_private or owner_id = auth.uid());
DROP POLICY IF EXISTS "uclubs_owner" ON public.user_clubs;
CREATE POLICY "uclubs_owner" ON public.user_clubs for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
DROP POLICY IF EXISTS "uclub_members_read" ON public.user_club_members;
CREATE POLICY "uclub_members_read" ON public.user_club_members for select using (true);
DROP POLICY IF EXISTS "uclub_members_self" ON public.user_club_members;
CREATE POLICY "uclub_members_self" ON public.user_club_members for all
  using (auth.uid() = user_id or exists(
    select 1 from public.user_clubs c where c.id = club_id and c.owner_id = auth.uid()
  )) with check (true);
