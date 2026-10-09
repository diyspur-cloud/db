-- Correção final do lease de newsletter.
-- Migrations históricas permanecem inalteradas.

alter table private.newsletter_dispatch_runs
  add column if not exists claim_token uuid;

-- Claims já existentes recebem identidade antes de a coluna ficar obrigatória.
update private.newsletter_dispatch_runs
   set claim_token = gen_random_uuid()
 where claim_token is null;

alter table private.newsletter_dispatch_runs
  alter column claim_token set default gen_random_uuid(),
  alter column claim_token set not null;

-- Claim e recuperação de lease produzem um token novo na mesma operação.
-- Um request antigo não consegue finalizar ou liberar o claim recuperado.
create or replace function public.claim_newsletter_dispatch_token(
  p_issue uuid,
  p_audience_key text
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_now timestamptz := statement_timestamp();
  v_new_token uuid := gen_random_uuid();
  v_claim_token uuid;
begin
  if p_issue is null
     or p_audience_key is null
     or length(p_audience_key) not between 1 and 128 then
    raise exception 'invalid newsletter dispatch key' using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.newsletter_issues as issue
    where issue.id = p_issue
      and issue.sent_at is not null
  ) then
    return null;
  end if;

  insert into private.newsletter_dispatch_runs (
    issue_id, audience_key, started_at, claim_token
  ) values (
    p_issue, p_audience_key, v_now, v_new_token
  )
  on conflict (issue_id, audience_key) do update
    set started_at = v_now,
        claim_token = excluded.claim_token
    where private.newsletter_dispatch_runs.completed_at is null
      and private.newsletter_dispatch_runs.started_at
        < v_now - interval '24 hours'
  returning claim_token into v_claim_token;

  return v_claim_token;
end;
$$;

-- Mantém a assinatura histórica booleana para callers antigos, mas delega a
-- mesma operação atômica com token.
create or replace function public.claim_newsletter_dispatch(
  p_issue uuid,
  p_audience_key text
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
begin
  return public.claim_newsletter_dispatch_token(p_issue, p_audience_key) is not null;
end;
$$;

-- A assinatura histórica não aceita false como uma liberação sem ownership:
-- isso evita que um request atrasado limpe um claim já concluído ou recuperado.
create or replace function public.finish_newsletter_dispatch(
  p_issue uuid,
  p_audience_key text,
  p_success boolean
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_rows integer;
begin
  if coalesce(p_success, false) then
    update private.newsletter_dispatch_runs
       set completed_at = statement_timestamp()
     where issue_id = p_issue
       and audience_key = p_audience_key
       and completed_at is null;
    get diagnostics v_rows = row_count;

    if v_rows > 0 then
      update public.newsletter_issues
         set sent_at = coalesce(sent_at, statement_timestamp())
       where id = p_issue;
    end if;
  end if;
end;
$$;

-- Finalização segura: somente o request que recebeu o token pode marcar
-- sucesso ou remover seu claim falho. DELETE libera retry imediato sem tocar
-- em claim concluído ou recuperado.
create or replace function public.finish_newsletter_dispatch_owned(
  p_issue uuid,
  p_audience_key text,
  p_success boolean,
  p_claim_token uuid
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_rows integer;
begin
  if p_issue is null
     or p_audience_key is null
     or p_claim_token is null then
    raise exception 'newsletter claim ownership is required' using errcode = '22023';
  end if;

  if coalesce(p_success, false) then
    update private.newsletter_dispatch_runs
       set completed_at = statement_timestamp()
     where issue_id = p_issue
       and audience_key = p_audience_key
       and claim_token = p_claim_token
       and completed_at is null;
    get diagnostics v_rows = row_count;

    if v_rows > 0 then
      update public.newsletter_issues
         set sent_at = coalesce(sent_at, statement_timestamp())
       where id = p_issue;
    end if;
  else
    delete from private.newsletter_dispatch_runs
     where issue_id = p_issue
       and audience_key = p_audience_key
       and claim_token = p_claim_token
       and completed_at is null;
  end if;
end;
$$;

revoke all on function public.claim_newsletter_dispatch_token(uuid, text),
  public.claim_newsletter_dispatch(uuid, text),
  public.finish_newsletter_dispatch(uuid, text, boolean),
  public.finish_newsletter_dispatch_owned(uuid, text, boolean, uuid)
  from public, anon, authenticated;
grant execute on function public.claim_newsletter_dispatch_token(uuid, text),
  public.claim_newsletter_dispatch(uuid, text),
  public.finish_newsletter_dispatch(uuid, text, boolean),
  public.finish_newsletter_dispatch_owned(uuid, text, boolean, uuid)
  to service_role;
