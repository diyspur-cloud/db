-- Correção incremental da recursão de RLS em listas personalizadas.
-- A visibilidade de unlisted permanece não pública, como no contrato existente.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated, service_role;

create or replace function private.can_view_reading_list(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.reading_lists as l
    where l.id = p_id
      and (
        l.visibility = 'public'::public.reading_list_visibility
        or l.owner_id = (select auth.uid())
        or exists (
          select 1
          from public.reading_list_collaborators as c
          where c.list_id = l.id
            and c.user_id = (select auth.uid())
        )
      )
  );
$$;

revoke all on function private.can_view_reading_list(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.can_view_reading_list(uuid)
  to anon, authenticated, service_role;

drop policy if exists lists_read on public.reading_lists;
create policy lists_read
  on public.reading_lists
  for select
  to anon, authenticated
  using (private.can_view_reading_list(id));
