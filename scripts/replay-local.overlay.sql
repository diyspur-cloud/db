-- REPLAY-ONLY OVERLAY. Do not apply this file to a hosted project and do not
-- add it to Supabase migration history. The historical migration remains
-- byte-for-byte intact.
--
-- The source SELECT names s.title but groups current_season.title. PostgreSQL
-- correctly rejects that source at 42803. The reduced replay removes only the
-- offending source block from the scratch pipeline and applies this corrected
-- view at the same point in ordering, before the source migration's snapshot
-- function remainder is executed.

create or replace view public.v_club_progress_panel
with (security_invoker = true)
as
select
  uc.id as club_id,
  uc.name as club_name,
  uc.current_book_id,
  b.title as current_book_title,
  uc.current_season_id,
  current_season.title as current_season_title,
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
