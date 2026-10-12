-- Cria RPC atômica para cadastro editorial de livros com auditoria transacional
-- Exige privilégio de administrador verificado via public.is_admin()

create or replace function public.create_editorial_book(
  p_title text,
  p_slug text,
  p_author uuid,
  p_synopsis text default null,
  p_cover text default null,
  p_pages integer default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_actor uuid := (select auth.uid());
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  if p_title is null or length(btrim(p_title)) not between 1 and 200
    or p_slug is null or length(p_slug) > 200
    or p_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
    or p_author is null
    or (p_pages is not null and p_pages <= 0)
    or (p_cover is not null and p_cover <> '' and p_cover !~ '^https://')
    or length(coalesce(p_synopsis, '')) > 20000 then
    raise exception 'invalid_book' using errcode = '22023';
  end if;

  insert into public.books(title, slug, author_id, synopsis, cover_url, total_pages)
    values (btrim(p_title), p_slug, p_author, nullif(btrim(p_synopsis), ''), nullif(btrim(p_cover), ''), p_pages)
    returning id into v_id;

  insert into public.editorial_audit_log(actor_id, entity_type, entity_id, action, changes)
    values (
      v_actor,
      'book',
      v_id,
      'create',
      pg_catalog.jsonb_build_object(
        'title', btrim(p_title),
        'slug', p_slug,
        'author_id', p_author,
        'total_pages', p_pages
      )
    );

  return v_id;
end;
$$;

revoke all on function public.create_editorial_book(text, text, uuid, text, text, integer) from public, anon;
grant execute on function public.create_editorial_book(text, text, uuid, text, text, integer) to authenticated, service_role;
