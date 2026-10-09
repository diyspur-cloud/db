-- Repara is_admin sem reabrir SELECT direto de profiles.
-- A identidade é sempre auth.uid(); não há parâmetro de usuário controlável.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated, service_role;

create or replace function private.current_user_is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select p.role = 'admin'::public.user_role
      from public.profiles as p
      where p.id = (select auth.uid())
    ),
    false
  );
$$;

revoke all on function private.current_user_is_admin()
  from public, anon, authenticated, service_role;
grant execute on function private.current_user_is_admin()
  to anon, authenticated, service_role;

create or replace function public.is_admin()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select private.current_user_is_admin();
$$;

revoke all on function public.is_admin()
  from public, anon, authenticated, service_role;
grant execute on function public.is_admin()
  to anon, authenticated, service_role;
