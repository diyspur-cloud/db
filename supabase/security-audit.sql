-- Auditoria read-only do estado pós-implementação. Não conceder permissões nem
-- executar statements de DDL a partir destas consultas.

-- RLS habilitado por tabela no schema public.
select n.nspname as schema_name, c.relname as table_name,
       c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
order by c.relname;

-- Policies ativas em tabelas e Storage.
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname in ('public', 'storage')
order by schemaname, tablename, policyname;

-- Buckets declarados pelo SDD.
select id, name, public from storage.buckets
where id in ('avatars','book-covers','manuscripts','meeting-slides','journal-media',
             'chapter-extras','feed-media','newsletter-assets','social-cards','ebooks')
order by id;

-- Views e materialized views públicas/internas, incluindo o security_invoker.
select n.nspname as schema_name, c.relname as object_name,
       c.relkind, c.reloptions
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname in ('public', 'private') and c.relkind in ('v', 'm')
order by n.nspname, c.relname
limit 100;

-- Contagem de FKs sem índice válido, pronto e não parcial que cubra a FK
-- como prefixo; resultado esperado após as migrations: 0.
select count(*) as unindexed_foreign_keys
from pg_constraint c
join pg_namespace n on n.oid = c.connamespace
where c.contype = 'f' and n.nspname = 'public'
  and not exists (
    select 1
    from pg_index i
    where i.indrelid = c.conrelid
      and i.indisvalid and i.indisready and i.indpred is null
      and i.indnkeyatts >= cardinality(c.conkey)
      and (
        select array_agg(x.attnum::smallint order by x.ord)
        from unnest(i.indkey::smallint[]) with ordinality as x(attnum, ord)
        where x.ord <= cardinality(c.conkey)
      ) = c.conkey
  )
limit 1;

-- Policies que ainda avaliam auth.uid() diretamente (esperado: 0).
select count(*) as direct_auth_uid_policy_expressions
from pg_policies
where schemaname = 'public'
  and (
    (position('auth.uid()' in lower(coalesce(qual, ''))) > 0
      and position('select auth.uid()' in lower(coalesce(qual, ''))) = 0)
    or
    (position('auth.uid()' in lower(coalesce(with_check, ''))) > 0
      and position('select auth.uid()' in lower(coalesce(with_check, ''))) = 0)
  )
limit 1;

-- Funções próprias sem search_path explícito: revise assinaturas e extensões.
select n.nspname as schema_name, p.proname, pg_get_function_identity_arguments(p.oid) as arguments,
       p.proconfig
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prokind = 'f'
  and (p.proconfig is null or not (p.proconfig @> array['search_path=pg_catalog, public']))
order by p.proname
limit 100;

-- Extensões ainda instaladas em public; não mover sem análise de dependências.
select e.extname, n.nspname as schema_name
from pg_extension e
join pg_namespace n on n.oid = e.extnamespace
where n.nspname = 'public'
order by e.extname
limit 50;
