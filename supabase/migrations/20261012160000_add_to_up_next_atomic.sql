-- Adiciona RPC atômica para inserção na fila de leitura (Up Next)
-- Garante lock transacional por usuário, posição entre 1 e 5 e tratamento de duplicatas

create or replace function public.add_to_up_next_atomic(p_book uuid)
returns integer language plpgsql security invoker set search_path = '' as $$
declare
  v_user uuid := (select auth.uid());
  v_position integer;
begin
  if v_user is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  -- Bloqueio transacional por usuário para evitar corrida de cálculo de posição
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user::text, 0)
  );

  -- Se o livro já estiver na fila do usuário, retorna a posição atual sem duplicar
  select q.position into v_position from public.user_up_next q
    where q.user_id = v_user and q.book_id = p_book;
  if found then
    return v_position;
  end if;

  -- Seleciona a primeira posição livre entre 1 e 5
  select n into v_position from pg_catalog.generate_series(1, 5) as n
    where not exists (
      select 1 from public.user_up_next q
      where q.user_id = v_user and q.position = n
    ) order by n limit 1;

  if v_position is null then
    raise exception 'queue_full' using errcode = 'P0001';
  end if;

  insert into public.user_up_next(user_id, book_id, position)
    values (v_user, p_book, v_position);

  return v_position;
end;
$$;

revoke all on function public.add_to_up_next_atomic(uuid) from public, anon;
grant execute on function public.add_to_up_next_atomic(uuid) to authenticated;
