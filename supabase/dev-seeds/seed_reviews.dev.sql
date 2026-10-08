-- DEV ONLY. Não aplicar no projeto remoto de produção.
-- Requer o seed de Dom Casmurro e ao menos um perfil role='admin'.
-- Se não houver perfil administrador, o INSERT afetará zero linhas.
insert into public.book_reviews (book_id, user_id, rating, spice_level, review_text)
select
  '22222222-2222-2222-2222-222222222222'::uuid,
  p.id,
  4.50,
  1,
  'Dom Casmurro segue sendo uma das obras mais enigmáticas da literatura brasileira.'
from public.profiles p
where p.role = 'admin'
  and exists (
    select 1 from public.books b
    where b.id = '22222222-2222-2222-2222-222222222222'::uuid
  )
order by p.id
limit 1
on conflict (book_id, user_id) do update
set rating = excluded.rating,
    spice_level = excluded.spice_level,
    review_text = excluded.review_text,
    deleted_at = null,
    updated_at = now();

-- Refresh manual apenas neste seed de desenvolvimento; em produção há pg_cron.
refresh materialized view concurrently private.mv_book_community_stats;
