-- Keep the existing profile RPC contract while moving the only privileged
-- read into the non-exposed `private` schema. Public RPCs run as invoker.
create or replace function private.get_my_profile_private()
returns table (whatsapp text, lgpd_consent boolean,
               lgpd_consent_at timestamptz, onboarding_done boolean)
language sql stable security definer set search_path = ''
as $$
  select p.whatsapp, p.lgpd_consent, p.lgpd_consent_at, p.onboarding_done
  from public.profiles p
  where p.id = (select auth.uid()) and (select auth.uid()) is not null;
$$;
revoke all on function private.get_my_profile_private() from public, anon;
grant execute on function private.get_my_profile_private() to authenticated;

create or replace function public.get_my_profile_private()
returns table (whatsapp text, lgpd_consent boolean,
               lgpd_consent_at timestamptz, onboarding_done boolean)
language sql stable security invoker set search_path = ''
as $$
  select * from private.get_my_profile_private();
$$;
revoke all on function public.get_my_profile_private() from public, anon;
grant execute on function public.get_my_profile_private() to authenticated;

-- The consent RPC remains callable, but now uses the caller's own UPDATE
-- privilege and RLS policy instead of elevating privileges.
grant update (lgpd_consent) on table public.profiles to authenticated;

create or replace function private.sync_lgpd_consent_timestamp()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  if new.lgpd_consent is distinct from old.lgpd_consent then
    new.lgpd_consent_at := case
      when new.lgpd_consent then statement_timestamp()
      else null
    end;
    new.updated_at := statement_timestamp();
  end if;
  return new;
end;
$$;
revoke all on function private.sync_lgpd_consent_timestamp() from public, anon, authenticated;
drop trigger if exists profiles_lgpd_consent_timestamp on public.profiles;
create trigger profiles_lgpd_consent_timestamp
before update of lgpd_consent on public.profiles
for each row execute function private.sync_lgpd_consent_timestamp();

create or replace function public.set_my_lgpd_consent(p_consent boolean)
returns void language plpgsql security invoker set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_consent is null then
    raise exception 'consent value is required' using errcode = '22004';
  end if;
  update public.profiles
     set lgpd_consent = p_consent
   where id = (select auth.uid());
  if not found then raise exception 'profile not found' using errcode = 'P0002'; end if;
end;
$$;
revoke all on function public.set_my_lgpd_consent(boolean) from public, anon;
grant execute on function public.set_my_lgpd_consent(boolean) to authenticated;
