-- Restaura somente os campos de onboarding previstos no contrato.
-- role, lgpd_consent, lgpd_consent_at e timestamps permanecem protegidos.
grant update (level, onboarding_done)
  on table public.profiles to authenticated;

grant update (whatsapp)
  on table public.profiles to authenticated;

-- Reafirma ownership da policy sem ampliar a superfície de escrita.
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own
  on public.profiles
  for update
  to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);
