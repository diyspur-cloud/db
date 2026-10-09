-- DEV ONLY. Não aplicar no projeto remoto de produção.
-- Requer o seed de Verity e ao menos um perfil role='admin'.
-- Se não houver perfil administrador, o INSERT afetará zero linhas.
insert into public.book_reviews (book_id, user_id, rating, spice_level, review_text)
select
  b.id,
  p.id,
  4.50,
  1,
  'Verity combina suspense psicológico e uma narrativa cheia de versões.'
from public.profiles p
cross join public.books b
where p.role = 'admin'
  and b.slug = 'verity'
order by p.id, b.id
limit 1
on conflict (book_id, user_id) do update
set rating = excluded.rating,
    spice_level = excluded.spice_level,
    review_text = excluded.review_text,
    deleted_at = null,
    updated_at = now();

-- Refresh manual apenas neste seed de desenvolvimento; em produção há pg_cron.
refresh materialized view concurrently private.mv_book_community_stats;
