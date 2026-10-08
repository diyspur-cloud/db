-- NOT APPLIED: public.book_reviews is not defined in the supplied SDD.
-- 8. Gerar embeddings do usuário (a partir do histórico)
-- =====================================================================
-- A função abaixo apenas monta o texto fonte; a chamada ao provedor
-- de embeddings é feita pela Edge Function `ai-user-embeddings`.
create or replace function public.build_user_reading_snapshot(p_user uuid)
returns text language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'title', b.title,
           'moods', bmv.moods,
           'pace',  bmv.pace,
           'rating', br.rating,
           'review', br.review_text
         ))::text, '[]')
  from public.user_progress up
  join public.chapters c on c.id = up.chapter_id
  join public.seasons  s on s.id = c.season_id
  join public.books    b on b.id = s.book_id
  left join public.book_mood_votes bmv on bmv.book_id = b.id and bmv.user_id = p_user
  left join public.book_reviews    br  on br.book_id  = b.id and br.user_id  = p_user
  where up.user_id = p_user;
$$;

-- =====================================================================
