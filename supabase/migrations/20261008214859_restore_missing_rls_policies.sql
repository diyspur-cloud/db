-- As três tabelas já tinham RLS habilitado, mas estavam sem policies.
-- A leitura de votos é restrita ao titular: permitir SELECT público na tabela
-- revelaria user_id e option_idx, e não apenas as contagens agregadas.

create policy meeting_rsvps_read_owner_or_admin
  on public.meeting_rsvps for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select public.is_admin())
  );
create policy meeting_rsvps_owner_write
  on public.meeting_rsvps for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy host_prompt_votes_read_owner
  on public.host_prompt_votes for select to authenticated
  using (user_id = (select auth.uid()));
create policy host_prompt_votes_owner_write
  on public.host_prompt_votes for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy user_challenges_read_owner_or_admin
  on public.user_challenges for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select public.is_admin())
  );
create policy user_challenges_owner_write
  on public.user_challenges for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
