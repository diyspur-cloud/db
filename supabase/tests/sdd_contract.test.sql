-- SDD community replay contract.
-- This file is executable with `supabase db query --local --file` or psql.
-- It assumes the database has already been migrated/replayed; it does not
-- create fixtures, alter schema, or insert data.

begin;

do $$
declare
  club_view_definition text;
  club_column_count integer;
  expected_index_count integer;
begin
  if to_regclass('public.v_club_progress_panel') is null then
    raise exception 'SDD contract failed: public.v_club_progress_panel is missing';
  end if;

  if to_regclass('public.v_book_community_stats') is null then
    raise exception 'SDD contract failed: public.v_book_community_stats is missing';
  end if;

  if to_regclass('public.mv_book_community_stats') is null
     and to_regclass('private.mv_book_community_stats') is null then
    raise exception 'SDD contract failed: community stats materialized view is missing';
  end if;

  select count(*)::integer
    into club_column_count
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'v_club_progress_panel';

  if club_column_count < 12 then
    raise exception
      'SDD contract failed: club panel exposes % columns; expected at least 12',
      club_column_count;
  end if;

  club_view_definition := lower(
    pg_get_viewdef('public.v_club_progress_panel'::regclass, true)
  );

  -- The original 42803 shape is `s.title ... GROUP BY current_season.title`.
  -- Later contract migrations may use `cs.title`; both are valid corrected
  -- aliases, but the invalid `s.title` projection must not survive.
  if position('s.title' in club_view_definition) > 0 then
    raise exception
      'SDD contract failed: club panel still projects s.title (42803 source shape)';
  end if;

  if position('current_season.title' in club_view_definition) = 0
     and position('cs.title' in club_view_definition) = 0 then
    raise exception
      'SDD contract failed: club panel has no grouped current-season title alias';
  end if;

  select count(*)::integer
    into expected_index_count
    from pg_indexes
   where schemaname in ('public', 'private')
     and indexname = 'mv_book_community_stats_book_id_idx';

  if expected_index_count = 0
     and to_regclass('public.mv_book_community_stats') is not null then
    raise exception
      'SDD contract failed: public community stats unique index is missing';
  end if;

  if to_regprocedure('public.build_user_reading_snapshot(uuid)') is null then
    raise exception
      'SDD contract failed: reading snapshot function is missing';
  end if;
end;
$$;

commit;

select 'PASS: SDD community replay contract' as result;
