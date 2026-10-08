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
