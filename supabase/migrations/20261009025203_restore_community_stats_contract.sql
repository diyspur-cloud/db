-- Compatibilidade de API para as estatísticas comunitárias de livros.
-- O materialized view permanece privado; a view pública conserva as nove
-- colunas existentes na mesma ordem e acrescenta aliases ao final.
create or replace view public.v_book_community_stats
with (security_invoker = true)
as
select
  mv.book_id,
  mv.title,
  mv.mood_counts,
  mv.pace_percent,
  mv.plot_vs_character_avg,
  mv.mood_sample_size,
  mv.review_count,
  coalesce(mv.avg_rating, 0::numeric) as avg_rating,
  mv.avg_spice,
  coalesce(ms.mood_percent, '{}'::jsonb) as mood_percent,
  mv.mood_sample_size as sample_size,
  mv.review_count as ratings_count,
  coalesce(mv.avg_spice, 0::numeric) as avg_spice_level
from private.mv_book_community_stats as mv
left join public.book_mood_stats as ms
  on ms.book_id = mv.book_id;

grant select on public.v_book_community_stats
  to anon, authenticated, service_role;
