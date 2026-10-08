-- Funções internas de agregação. O schema private não deve ser incluído nas
-- schemas expostas pela Data API. Estas funções retornam apenas totais, nunca
-- IDs de leitores ou linhas de votos.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated, service_role;

create or replace function private.get_chapter_audience(p_chapter_id uuid)
returns table (
  finished_count bigint,
  reading_count bigint,
  not_started_count bigint,
  avg_percent numeric
)
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select
    count(*) filter (where p.status = 'read'),
    count(*) filter (where p.status = 'reading'),
    count(*) filter (where p.status = 'want_to_read'),
    round(avg(p.percent)::numeric, 2)
  from public.user_progress as p
  where p.chapter_id = p_chapter_id;
$$;

create or replace function private.get_host_prompt_aggregate(p_prompt_id uuid)
returns table (
  option_0_count bigint,
  option_1_count bigint,
  option_2_count bigint,
  total_votes bigint
)
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select
    count(*) filter (where v.option_idx = 0),
    count(*) filter (where v.option_idx = 1),
    count(*) filter (where v.option_idx = 2),
    count(*)
  from public.host_prompt_votes as v
  where v.prompt_id = p_prompt_id;
$$;

grant execute on function private.get_chapter_audience(uuid)
  to anon, authenticated, service_role;
grant execute on function private.get_host_prompt_aggregate(uuid)
  to anon, authenticated, service_role;

-- Recria a view de público por capítulo sem permitir acesso às linhas pessoais
-- de user_progress. A saída continua contendo somente métricas agregadas.
create or replace view public.v_chapter_audience
with (security_invoker = true)
as
select
  c.id as chapter_id,
  c.season_id,
  a.finished_count,
  a.reading_count,
  a.not_started_count,
  a.avg_percent
from public.chapters as c
cross join lateral private.get_chapter_audience(c.id) as a;

-- Mantém contagens públicas de enquetes, mas não expõe votos individualizados.
create or replace view public.v_host_prompt_results
with (security_invoker = true)
as
select
  hp.id as prompt_id,
  hp.chapter_id,
  hp.question,
  hp.options,
  a.option_0_count,
  a.option_1_count,
  a.option_2_count,
  a.total_votes
from public.host_prompts as hp
cross join lateral private.get_host_prompt_aggregate(hp.id) as a;

-- Resumo público, limitado a agregados por livro.
create materialized view public.mv_book_community_stats as
select
  b.id as book_id,
  b.title,
  coalesce(bms.mood_counts, '{}'::jsonb) as mood_counts,
  coalesce(bms.pace_percent, '{"slow":0,"medium":0,"fast":0}'::jsonb) as pace_percent,
  bms.plot_vs_character_avg,
  bms.sample_size as mood_sample_size,
  count(br.id) filter (where br.deleted_at is null) as review_count,
  round(avg(br.rating) filter (where br.deleted_at is null), 2) as avg_rating,
  round(avg(br.spice_level) filter (where br.deleted_at is null), 2) as avg_spice
from public.books as b
left join public.book_mood_stats as bms on bms.book_id = b.id
left join public.book_reviews as br on br.book_id = b.id
  and br.deleted_at is null
group by b.id, b.title, bms.mood_counts, bms.pace_percent,
         bms.plot_vs_character_avg, bms.sample_size;

create unique index mv_book_community_stats_book_id_idx
  on public.mv_book_community_stats (book_id);

grant select on public.mv_book_community_stats to anon, authenticated, service_role;

create or replace view public.v_book_community_stats
with (security_invoker = true)
as
select * from public.mv_book_community_stats;
grant select on public.v_book_community_stats to anon, authenticated, service_role;

-- O resumo do clube respeita RLS das tabelas subjacentes: cada membro só
-- contribui com as linhas de progresso que tem permissão de ler.
create or replace view public.v_club_progress_panel
with (security_invoker = true)
as
select
  uc.id as club_id,
  uc.name as club_name,
  uc.current_book_id,
  b.title as current_book_title,
  uc.current_season_id,
  s.title as current_season_title,
  uc.current_started_at,
  uc.current_ends_at,
  count(distinct up.user_id) filter (where s.id is not null) as distinct_readers,
  count(*) filter (where s.id is not null and up.status = 'read') as chapters_read,
  count(*) filter (where s.id is not null and up.status = 'reading') as chapters_in_progress,
  round(avg(up.percent) filter (where s.id is not null), 2) as avg_percent
from public.user_clubs as uc
join public.user_club_members as ucm on ucm.club_id = uc.id
left join public.books as b on b.id = uc.current_book_id
left join public.seasons as current_season on current_season.id = uc.current_season_id
left join public.user_progress as up on up.user_id = ucm.user_id
left join public.chapters as c on c.id = up.chapter_id
left join public.seasons as s on s.id = c.season_id
  and s.book_id = uc.current_book_id
  and (uc.current_season_id is null or s.id = uc.current_season_id)
where uc.current_book_id is not null
group by uc.id, uc.name, uc.current_book_id, b.title,
         uc.current_season_id, current_season.title,
         uc.current_started_at, uc.current_ends_at;

grant select on public.v_club_progress_panel to anon, authenticated, service_role;

-- Snapshot sempre passa pelo RLS do invocador, e um JWT de usuário não pode
-- solicitar o histórico de outro user_id. service_role/backend confiável pode
-- calcular embeddings sob seu próprio contrato.
create or replace function public.build_user_reading_snapshot(p_user uuid)
returns text
language sql
stable
security invoker
set search_path = pg_catalog, public
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'book_id', b.id,
        'book_title', b.title,
        'status', up.status,
        'percent', up.percent,
        'moods', bmv.moods,
        'pace', bmv.pace,
        'review', br.review_text,
        'rating', br.rating
      ) order by b.title
    )::text,
    '[]'
  )
  from public.user_progress as up
  join public.chapters as c on c.id = up.chapter_id
  join public.seasons as s on s.id = c.season_id
  join public.books as b on b.id = s.book_id
  left join public.book_mood_votes as bmv
    on bmv.book_id = b.id and bmv.user_id = up.user_id
  left join public.book_reviews as br
    on br.book_id = b.id and br.user_id = up.user_id and br.deleted_at is null
  where up.user_id = p_user
    and (auth.uid() is null or auth.uid() = p_user);
$$;
revoke all on function public.build_user_reading_snapshot(uuid) from public, anon;
grant execute on function public.build_user_reading_snapshot(uuid)
  to authenticated, service_role;
