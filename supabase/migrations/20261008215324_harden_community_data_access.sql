-- O materialized view é detalhe de implementação. A API pública usa apenas a
-- view v_book_community_stats; mover o MV para private evita exposição direta.
alter materialized view public.mv_book_community_stats set schema private;
revoke all on table private.mv_book_community_stats from public, anon, authenticated, service_role;
grant select on table private.mv_book_community_stats to anon, authenticated, service_role;

-- RSVP e progresso: leitura própria/admin; escrita própria. Comandos separados
-- evitam que policy FOR ALL sobreponha a policy SELECT e preservam o limite de
-- privilégio administrativo definido anteriormente.
drop policy if exists meeting_rsvps_read_owner_or_admin on public.meeting_rsvps;
drop policy if exists meeting_rsvps_owner_write on public.meeting_rsvps;
create policy meeting_rsvps_read_owner_or_admin
  on public.meeting_rsvps for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy meeting_rsvps_insert_owner
  on public.meeting_rsvps for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy meeting_rsvps_update_owner
  on public.meeting_rsvps for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy meeting_rsvps_delete_owner
  on public.meeting_rsvps for delete to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists host_prompt_votes_read_owner on public.host_prompt_votes;
-- Esta policy única cobre leitura e escrita do próprio usuário, sem duplicidade.
drop policy if exists host_prompt_votes_owner_write on public.host_prompt_votes;
create policy host_prompt_votes_owner_all
  on public.host_prompt_votes for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists user_challenges_read_owner_or_admin on public.user_challenges;
drop policy if exists user_challenges_owner_write on public.user_challenges;
create policy user_challenges_read_owner_or_admin
  on public.user_challenges for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy user_challenges_insert_owner
  on public.user_challenges for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy user_challenges_update_owner
  on public.user_challenges for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy user_challenges_delete_owner
  on public.user_challenges for delete to authenticated
  using (user_id = (select auth.uid()));

-- Avaliações: uma policy de leitura pública para conteúdo ativo e policies de
-- escrita próprias/admin, sem sobrepor as quatro ações no papel authenticated.
drop policy if exists book_reviews_read_active_or_owner on public.book_reviews;
drop policy if exists book_reviews_owner_write on public.book_reviews;
drop policy if exists book_reviews_admin_all on public.book_reviews;
create policy book_reviews_read_active_or_owner
  on public.book_reviews for select to anon, authenticated
  using (
    deleted_at is null
    or user_id = (select auth.uid())
    or (select public.is_admin())
  );
create policy book_reviews_insert_owner_or_admin
  on public.book_reviews for insert to authenticated
  with check (
    user_id = (select auth.uid())
    or (select public.is_admin())
  );
create policy book_reviews_update_owner_or_admin
  on public.book_reviews for update to authenticated
  using (
    user_id = (select auth.uid())
    or (select public.is_admin())
  )
  with check (
    user_id = (select auth.uid())
    or (select public.is_admin())
  );
create policy book_reviews_delete_owner_or_admin
  on public.book_reviews for delete to authenticated
  using (
    user_id = (select auth.uid())
    or (select public.is_admin())
  );
