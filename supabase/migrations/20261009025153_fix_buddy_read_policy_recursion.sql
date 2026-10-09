-- Correção incremental da recursão de RLS em Buddy Reads.
-- O helper só calcula a condição booleana existente e não aceita identidade do cliente.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated, service_role;

create or replace function private.can_view_buddy_read(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.buddy_reads as br
    where br.id = p_id
      and (
        not br.is_private
        or br.owner_id = (select auth.uid())
        or exists (
          select 1
          from public.buddy_read_members as m
          where m.buddy_read_id = br.id
            and m.user_id = (select auth.uid())
        )
      )
  );
$$;

revoke all on function private.can_view_buddy_read(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.can_view_buddy_read(uuid)
  to anon, authenticated, service_role;

drop policy if exists buddy_reads_visible on public.buddy_reads;
create policy buddy_reads_visible
  on public.buddy_reads
  for select
  to anon, authenticated
  using (private.can_view_buddy_read(id));
