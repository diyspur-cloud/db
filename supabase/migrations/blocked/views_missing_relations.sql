-- NOT APPLIED: missing public.book_reviews and public.clubs.current_book_id.
-- 3. Estatísticas por livro (humor, pace, ratings)
-- =====================================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_book_community_stats as
select
  b.id                                                as book_id,
  coalesce(bms.mood_percent, '{}'::jsonb)             as mood_percent,
  coalesce(bms.pace_percent, '{"slow":0,"medium":0,"fast":0}'::jsonb) as pace_percent,
  bms.plot_vs_character_avg,
  bms.sample_size,
  coalesce(avg(br.rating), 0)                         as avg_rating,
  count(br.id)                                        as ratings_count,
  coalesce(avg(br.spice_level), 0)                    as avg_spice_level
from public.books b
left join public.book_mood_stats bms on bms.book_id = b.id
left join public.book_reviews br on br.book_id = b.id
group by b.id, bms.mood_percent, bms.pace_percent, bms.plot_vs_character_avg, bms.sample_size;
CREATE UNIQUE INDEX IF NOT EXISTS mv_book_community_stats_pk on public.mv_book_community_stats (book_id);

-- =====================================================================

-- 5. Ranking de clube (não-competitivo — usado para painel de progresso)
-- =====================================================================
create or replace view public.v_club_progress_panel as
select
  ucm.club_id,
  count(*) filter (where up.status = 'read')         as finished_count,
  count(*) filter (where up.status = 'reading')      as reading_count,
  count(*) filter (where up.status = 'want_to_read') as not_started_count,
  coalesce(round(avg(up.percent)::numeric, 2), 0)    as avg_percent
from public.user_club_members ucm
left join public.user_progress up
  on up.user_id = ucm.user_id
 and up.chapter_id in (select id from public.chapters c
                       join public.seasons s on s.id = c.season_id
                       join public.user_clubs uc on uc.id = ucm.club_id
                       where s.book_id = (select current_book_id
                                          from public.clubs c2
                                          where c2.id = ucm.club_id))
group by ucm.club_id;

-- =====================================================================
