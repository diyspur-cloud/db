-- Agregação coletiva autorizada sem expor linhas individuais de progresso.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated, service_role;

create or replace function private.club_progress_counts(p_club uuid)
returns table (
  finished_count bigint,
  reading_count bigint,
  not_started_count bigint,
  avg_percent numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    count(*) filter (where up.status = 'read'::public.shelf_status),
    count(*) filter (where up.status = 'reading'::public.shelf_status),
    count(*) filter (where up.status = 'want_to_read'::public.shelf_status),
    coalesce(round(avg(up.percent)::numeric, 2), 0::numeric)
  from public.user_clubs as uc
  join public.user_club_members as member_scope
    on member_scope.club_id = uc.id
  left join public.user_progress as up
    on up.user_id = member_scope.user_id
   and up.chapter_id in (
     select c.id
     from public.chapters as c
     join public.seasons as s on s.id = c.season_id
     where s.book_id = uc.current_book_id
   )
  where uc.id = p_club
    and (not uc.is_private or uc.owner_id = (select auth.uid()));
$$;

revoke all on function private.club_progress_counts(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.club_progress_counts(uuid)
  to anon, authenticated, service_role;

-- Mantém as 12 colunas atuais na mesma ordem/tipos/contexto e acrescenta
-- os aliases contratuais ao final. A view continua security-invoker.
create or replace view public.v_club_progress_panel
with (security_invoker = true)
as
select
  uc.id as club_id,
  uc.name as club_name,
  uc.current_book_id,
  b.title as current_book_title,
  uc.current_season_id,
  cs.title as current_season_title,
  uc.current_started_at,
  uc.current_ends_at,
  old_panel.distinct_readers,
  aggregates.finished_count as chapters_read,
  aggregates.reading_count as chapters_in_progress,
  aggregates.avg_percent,
  aggregates.finished_count,
  aggregates.reading_count,
  aggregates.not_started_count
from public.user_clubs as uc
join public.user_club_members as member_scope
  on member_scope.club_id = uc.id
left join public.books as b
  on b.id = uc.current_book_id
left join public.seasons as cs
  on cs.id = uc.current_season_id
cross join lateral private.club_progress_counts(uc.id) as aggregates
cross join lateral (
  select count(distinct up.user_id)
    filter (where reading_season.id is not null) as distinct_readers
  from public.user_club_members as m
  left join public.user_progress as up
    on up.user_id = m.user_id
  left join public.chapters as c
    on c.id = up.chapter_id
  left join public.seasons as reading_season
    on reading_season.id = c.season_id
   and reading_season.book_id = uc.current_book_id
   and (uc.current_season_id is null or reading_season.id = uc.current_season_id)
  where m.club_id = uc.id
) as old_panel
where uc.current_book_id is not null
group by
  uc.id,
  uc.name,
  uc.current_book_id,
  b.title,
  uc.current_season_id,
  cs.title,
  uc.current_started_at,
  uc.current_ends_at,
  old_panel.distinct_readers,
  aggregates.finished_count,
  aggregates.reading_count,
  aggregates.not_started_count,
  aggregates.avg_percent;

grant select on public.v_club_progress_panel
  to anon, authenticated, service_role;
