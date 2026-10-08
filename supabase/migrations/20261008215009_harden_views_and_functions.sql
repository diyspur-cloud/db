-- Views passam a respeitar os privilégios e RLS do chamador.
-- v_chapter_audience e v_host_prompt_results usam agregadores estreitos em
-- private, definidos na migration imediatamente anterior.
alter view public.v_chapter_audience set (security_invoker = true);
alter view public.v_season_ranking set (security_invoker = true);
alter view public.v_comments_visible set (security_invoker = true);
alter view public.v_host_prompt_results set (security_invoker = true);
alter view public.v_video_timed_comment_stats set (security_invoker = true);
alter view public.v_user_reading_overview set (security_invoker = true);
alter view public.v_feed_post_counters set (security_invoker = true);
alter view public.v_book_community_stats set (security_invoker = true);
alter view public.v_club_progress_panel set (security_invoker = true);

-- Reduzir ACL de tabelas privadas. RLS permanece como segunda camada de controle.
revoke all on table public.meeting_rsvps, public.host_prompt_votes,
  public.user_challenges from anon;
revoke insert, update, delete on table public.book_reviews from anon;
grant select on table public.book_reviews to anon;

-- Fixar search_path das funções de aplicação encontradas na auditoria.
alter function public.is_admin() set search_path = pg_catalog, public;
alter function public.handle_new_user() set search_path = pg_catalog, public;
alter function public.award_xp(uuid, public.xp_source, integer, uuid)
  set search_path = pg_catalog, public;
alter function public.bump_comment_likes() set search_path = pg_catalog, public;
alter function public.bump_comment_replies() set search_path = pg_catalog, public;
alter function public.touch_streak() set search_path = pg_catalog, public;
alter function public.match_books(public.vector, double precision, integer)
  set search_path = pg_catalog, public;
alter function public.get_reader_matches(uuid, integer)
  set search_path = pg_catalog, public;
alter function public.refresh_user_quiz_averages()
  set search_path = pg_catalog, public;
alter function public.refresh_chapter_quiz_averages()
  set search_path = pg_catalog, public;
alter function public.refresh_book_mood_stats(uuid)
  set search_path = pg_catalog, public;
alter function public.trg_refresh_book_mood_stats()
  set search_path = pg_catalog, public;
alter function public.refresh_content_warning_votes()
  set search_path = pg_catalog, public;
alter function public.bump_feed_post_counters()
  set search_path = pg_catalog, public;
alter function public.bump_journal_likes()
  set search_path = pg_catalog, public;
alter function public.generate_milestones_for_season(uuid)
  set search_path = pg_catalog, public;
alter function public.refresh_reading_goal_progress()
  set search_path = pg_catalog, public;
alter function public.match_readers(public.vector, double precision, integer, uuid)
  set search_path = pg_catalog, public;

-- O trigger wrapper executa com o owner confiável para poder invocar o helper
-- de agregação que deixa de ser exposto ao cliente.
create or replace function public.trg_refresh_book_mood_stats()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform public.refresh_book_mood_stats(coalesce(new.book_id, old.book_id));
  return null;
end;
$$;

-- Nenhuma role de cliente pode conceder XP ou acionar helpers SECURITY DEFINER.
-- Edge Functions devem invocar award_xp com uma sessão service_role separada.
revoke execute on function public.award_xp(uuid, public.xp_source, integer, uuid)
  from public, anon, authenticated;
grant execute on function public.award_xp(uuid, public.xp_source, integer, uuid)
  to service_role;

revoke execute on function public.generate_milestones_for_season(uuid)
  from public, anon, authenticated;
grant execute on function public.generate_milestones_for_season(uuid)
  to service_role;

revoke execute on function public.refresh_book_mood_stats(uuid)
  from public, anon, authenticated;
grant execute on function public.refresh_book_mood_stats(uuid)
  to service_role;

revoke execute on function public.handle_new_user()
  from public, anon, authenticated;
revoke execute on function public.refresh_user_quiz_averages()
  from public, anon, authenticated;
revoke execute on function public.refresh_chapter_quiz_averages()
  from public, anon, authenticated;
revoke execute on function public.refresh_content_warning_votes()
  from public, anon, authenticated;
revoke execute on function public.refresh_reading_goal_progress()
  from public, anon, authenticated;
revoke execute on function public.rls_auto_enable()
  from public, anon, authenticated;
revoke execute on function public.trg_refresh_book_mood_stats()
  from public, anon, authenticated;
