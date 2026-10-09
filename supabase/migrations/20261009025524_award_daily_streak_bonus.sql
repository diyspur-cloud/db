-- Bônus diário decidido pelo contrato: uma vez por dia com atividade real.
-- Não há trigger automático; o handler award-xp chama esta RPC após requestUser.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to service_role;

create or replace function private.award_daily_streak_bonus(p_user uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ref uuid;
begin
  if p_user is null then
    raise exception 'streak bonus identity is required' using errcode = '22023';
  end if;

  -- A atividade é independente do próprio bônus, evitando prova circular.
  -- A data usa a mesma current_date que private.touch_streak().
  if not exists (
    select 1
    from public.user_streaks as us
    where us.user_id = p_user
      and us.last_activity_at = current_date
      and us.current_streak > 0
  ) then
    return false;
  end if;

  if not exists (
    select 1
    from public.user_progress as up
    where up.user_id = p_user
      and up.updated_at::date = current_date
    union all
    select 1
    from public.xp_events as xe
    where xe.user_id = p_user
      and xe.source <> 'streak_bonus'::public.xp_source
      and xe.created_at::date = current_date
  ) then
    return false;
  end if;

  -- md5 fornece somente um identificador diário determinístico; não é segredo.
  v_ref := md5(p_user::text || ':' || current_date::text)::uuid;
  perform public.award_xp(
    p_user,
    'streak_bonus'::public.xp_source,
    25,
    v_ref
  );

  -- Tanto a primeira chamada quanto retries idempotentes deixam o ledger
  -- contendo exatamente a referência diária, graças ao índice existente.
  return exists (
    select 1
    from public.xp_events as xe
    where xe.user_id = p_user
      and xe.source = 'streak_bonus'::public.xp_source
      and xe.ref_id = v_ref
  );
end;
$$;

revoke all on function private.award_daily_streak_bonus(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.award_daily_streak_bonus(uuid)
  to service_role;

create or replace function public.award_daily_streak_bonus(p_user uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  select private.award_daily_streak_bonus(p_user);
$$;

revoke all on function public.award_daily_streak_bonus(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.award_daily_streak_bonus(uuid)
  to service_role;
