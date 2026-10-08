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
