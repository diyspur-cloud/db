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

do $$
declare
  stats_column_count integer;
  stats_numeric_count integer;
  overview_invoker boolean;
  snapshot_definition text;
  quiz_constraint text;
begin
  select count(*)::integer
    into stats_column_count
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'v_book_community_stats';

  if stats_column_count <> 8 then
    raise exception
      'SDD contract failed: public.v_book_community_stats exposes % columns; expected 8',
      stats_column_count;
  end if;

  select count(*)::integer
    into stats_numeric_count
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'v_book_community_stats'
     and column_name in ('avg_rating', 'avg_spice_level')
     and data_type = 'numeric';

  if stats_numeric_count <> 2 then
    raise exception
      'SDD contract failed: community averages are not numeric';
  end if;

  if to_regclass('public.v_user_reading_overview') is not null then
    select coalesce('security_invoker=true' = any(c.reloptions), false)
      into overview_invoker
      from pg_class as c
     where c.oid = 'public.v_user_reading_overview'::regclass;

    if not overview_invoker then
      raise exception
        'SDD contract failed: v_user_reading_overview is not security_invoker';
    end if;
  end if;

  select pg_get_functiondef(
    'public.build_user_reading_snapshot(uuid)'::regprocedure
  )
    into snapshot_definition;

  if position('book_title' in lower(snapshot_definition)) > 0
     or position('title' in lower(snapshot_definition)) = 0 then
    raise exception
      'SDD contract failed: reading snapshot keys are not title-based';
  end if;

  if to_regclass('public.quiz_answers') is not null then
    select pg_get_constraintdef(pc.oid)
      into quiz_constraint
      from pg_constraint as pc
     where pc.conrelid = 'public.quiz_answers'::regclass
       and pc.conname = 'quiz_answers_chosen_idx_original_check';

    if quiz_constraint is null or position('-1' in quiz_constraint) = 0 then
      raise exception
        'SDD contract failed: quiz_answers does not allow chosen_idx=-1';
    end if;
  end if;
end;
$$;

commit;

select 'PASS: SDD community replay contract' as result;
