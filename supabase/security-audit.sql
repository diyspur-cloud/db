-- Consultas somente leitura para validar RLS e objetos após a implantação.
-- RLS habilitado por tabela no schema public.
select n.nspname as schema_name, c.relname as table_name,
       c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
order by c.relname;

-- Policies ativas.
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname in ('public', 'storage')
order by schemaname, tablename, policyname;

-- Buckets declarados pelo SDD.
select id, name, public from storage.buckets
where id in ('avatars','book-covers','manuscripts','meeting-slides','journal-media',
             'chapter-extras','feed-media','newsletter-assets','social-cards','ebooks')
order by id;
