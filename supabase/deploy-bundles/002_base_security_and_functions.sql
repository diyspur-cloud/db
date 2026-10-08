-- >>> 20260101001300_rls_policies.sql
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

-- >>> 20260101001400_functions_and_triggers.sql
-- Source: SDDBD2.md sections 6.1-6.2.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, username, display_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email,'@',1)),
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email,'@',1)),
    new.raw_user_meta_data->>'avatar_url'
  )
  on conflict (id) do nothing;

  insert into public.user_xp (user_id) values (new.id)
    on conflict do nothing;
  insert into public.user_streaks (user_id) values (new.id)
    on conflict do nothing;
  return new;
end $$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created after insert ON auth.users
for each row execute function public.handle_new_user();

create or replace function public.award_xp(
  p_user uuid,
  p_source xp_source,
  p_amount int,
  p_ref uuid default null
) returns void language plpgsql security definer as $$
begin
  insert into public.xp_events (user_id, source, amount, ref_id)
  values (p_user, p_source, p_amount, p_ref);

  insert into public.user_xp (user_id, total_xp, updated_at)
  values (p_user, p_amount, now())
  on conflict (user_id) do update
    set total_xp = public.user_xp.total_xp + excluded.total_xp,
        updated_at = now();
end $$;

create or replace function public.bump_comment_likes()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    update public.comments set likes_count = likes_count + 1 where id = new.comment_id;
  elsif tg_op = 'DELETE' then
    update public.comments set likes_count = likes_count - 1 where id = old.comment_id;
  end if;
  return null;
end $$;

DROP TRIGGER IF EXISTS trg_comment_likes ON public.reactions;
CREATE TRIGGER trg_comment_likes after insert or delete ON public.reactions
for each row execute function public.bump_comment_likes();

create or replace function public.bump_comment_replies()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' and new.parent_id is not null then
    update public.comments set replies_count = replies_count + 1 where id = new.parent_id;
  elsif tg_op = 'DELETE' and old.parent_id is not null then
    update public.comments set replies_count = replies_count - 1 where id = old.parent_id;
  end if;
  return null;
end $$;

DROP TRIGGER IF EXISTS trg_comment_replies ON public.comments;
CREATE TRIGGER trg_comment_replies after insert or delete ON public.comments
for each row execute function public.bump_comment_replies();

create or replace function public.touch_streak()
returns trigger language plpgsql as $$
declare
  v_user uuid;
  v_last date;
  v_today date := current_date;
  v_curr int;
  v_long int;
begin
  -- quem gerou atividade?
  if tg_table_name = 'user_progress' then v_user := new.user_id;
  elsif tg_table_name = 'xp_events'   then v_user := new.user_id;
  else return null; end if;

  select last_activity_at, current_streak, longest_streak
    into v_last, v_curr, v_long
  from public.user_streaks where user_id = v_user for update;

  if v_last = v_today then return null; end if;

  if v_last = v_today - 1 then
    v_curr := coalesce(v_curr,0) + 1;
  else
    v_curr := 1;
  end if;
  v_long := greatest(coalesce(v_long,0), v_curr);

  update public.user_streaks
     set current_streak = v_curr,
         longest_streak = v_long,
         last_activity_at = v_today,
         updated_at = now()
   where user_id = v_user;

  return null;
end $$;

DROP TRIGGER IF EXISTS trg_streak_progress ON public.user_progress;
CREATE TRIGGER trg_streak_progress after insert or update ON public.user_progress
for each row execute function public.touch_streak();

DROP TRIGGER IF EXISTS trg_streak_xp ON public.xp_events;
CREATE TRIGGER trg_streak_xp after insert ON public.xp_events
for each row execute function public.touch_streak();

create or replace function public.match_books(
  query_embedding vector(1536),
  match_threshold float,
  match_count int
) returns table (id uuid, title text, similarity float)
language sql stable as $$
  select b.id, b.title, 1 - (b.embedding <=> query_embedding) as similarity
  from public.books b
  where b.embedding is not null
    and 1 - (b.embedding <=> query_embedding) > match_threshold
  order by b.embedding <=> query_embedding
  limit match_count;
$$;

create or replace view public.v_chapter_audience as
select
  c.id                                  as chapter_id,
  c.season_id,
  count(*) filter (where p.status = 'read')             as finished_count,
  count(*) filter (where p.status = 'reading')          as reading_count,
  count(*) filter (where p.status = 'want_to_read')     as not_started_count,
  round(avg(p.percent)::numeric, 2)                     as avg_percent
from public.chapters c
left join public.user_progress p on p.chapter_id = c.id
group by c.id, c.season_id;

create or replace view public.v_season_ranking as
select
  ux.season_id,
  ux.user_id,
  p.username,
  p.display_name,
  p.avatar_url,
  ux.season_xp,
  row_number() over (partition by ux.season_id order by ux.season_xp desc) as position
from public.user_xp ux
join public.profiles p on p.id = ux.user_id
where ux.season_id is not null;

create or replace view public.v_comments_visible as
select
  c.id, c.chapter_id, c.user_id, c.parent_id, c.created_at, c.likes_count,
  c.replies_count, c.is_spoiler,
  case
    when c.is_spoiler and coalesce(up.percent,0) < c.min_percent then null
    else c.content
  end as content,
  case
    when c.is_spoiler and coalesce(up.percent,0) < c.min_percent then true
    else false
  end as is_locked
from public.comments c
left join public.user_progress up
  on up.chapter_id = c.chapter_id and up.user_id = auth.uid()
where c.deleted_at is null;
