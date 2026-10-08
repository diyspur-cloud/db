-- Gera índice B-tree quando os atributos da FK não são cobertos pelo prefixo
-- de nenhuma chave de índice completa e válida. O catálogo auditado apontou
-- 63 FKs sem índice no estado anterior a esta migration.
-- São índices aditivos: não alteram linhas nem constraints.
do $$
declare
  fk record;
begin
  for fk in
    select
      c.conrelid,
      c.conname,
      c.conkey,
      string_agg(format('%I', a.attname), ', ' order by k.ord) as columns_sql
    from pg_constraint as c
    join pg_namespace as n on n.oid = c.connamespace
    cross join lateral unnest(c.conkey) with ordinality as k(attnum, ord)
    join pg_attribute as a
      on a.attrelid = c.conrelid and a.attnum = k.attnum
    where c.contype = 'f'
      and n.nspname = 'public'
      and not exists (
        select 1
        from pg_index as i
        where i.indrelid = c.conrelid
          and i.indisvalid
          and i.indisready
          and i.indpred is null
          and i.indnkeyatts >= cardinality(c.conkey)
          and (
            select array_agg(x.attnum::smallint order by x.ord)
            from unnest(i.indkey::smallint[]) with ordinality as x(attnum, ord)
            where x.ord <= cardinality(c.conkey)
          ) = c.conkey
      )
    group by c.conrelid, c.conname, c.conkey
    order by c.conrelid::regclass::text, c.conname
  loop
    execute format(
      'create index if not exists %I on %s (%s)',
      'idx_fk_' || substr(md5(fk.conrelid::regclass::text || ':' || fk.conname), 1, 24),
      fk.conrelid::regclass,
      fk.columns_sql
    );
  end loop;
end;
$$;
