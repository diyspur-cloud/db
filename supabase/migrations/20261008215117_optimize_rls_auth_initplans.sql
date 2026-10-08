-- Captura auth.uid() em um initplan por statement, evitando reavaliação por
-- linha. A expressão lógica das policies é preservada; a única policy baseada
-- em auth.role() é normalizada para TO authenticated, com o mesmo público-alvo.
do $$
declare
  p record;
  role_sql text;
  using_sql text;
  check_sql text;
  ddl text;
begin
  for p in
    select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
    from pg_policies
    where schemaname = 'public'
      and (
        (coalesce(qual, '') ~ 'auth\.uid\(\)'
          and coalesce(qual, '') !~ '\(select auth\.uid\(\)\)')
        or
        (coalesce(with_check, '') ~ 'auth\.uid\(\)'
          and coalesce(with_check, '') !~ '\(select auth\.uid\(\)\)')
        or (tablename = 'quiz_questions' and policyname = 'quiz_q_read_auth')
      )
    order by schemaname, tablename, policyname
  loop
    select string_agg(quote_ident(r), ', ' order by r)
      into role_sql
      from unnest(p.roles) as roles(r);

    using_sql := p.qual;
    check_sql := p.with_check;

    if p.tablename = 'quiz_questions' and p.policyname = 'quiz_q_read_auth' then
      role_sql := 'authenticated';
      using_sql := 'true';
      check_sql := null;
    else
      using_sql := case when using_sql is null then null else
        regexp_replace(using_sql, 'auth\.uid\(\)', '(select auth.uid())', 'g') end;
      check_sql := case when check_sql is null then null else
        regexp_replace(check_sql, 'auth\.uid\(\)', '(select auth.uid())', 'g') end;
    end if;

    execute format('drop policy %I on %I.%I', p.policyname, p.schemaname, p.tablename);

    ddl := format(
      'create policy %I on %I.%I as %s for %s to %s',
      p.policyname, p.schemaname, p.tablename,
      lower(p.permissive), lower(p.cmd), role_sql
    );
    if using_sql is not null then
      ddl := ddl || format(' using (%s)', using_sql);
    end if;
    if check_sql is not null then
      ddl := ddl || format(' with check (%s)', check_sql);
    end if;
    execute ddl;
  end loop;
end;
$$;
