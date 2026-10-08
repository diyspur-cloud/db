-- Prevent self-assigned club privileges, client-edited levels, and redundant
-- FOR ALL policies on journal and prompt response tables.

-- `level` is a server-derived progression attribute, never user-editable.
revoke update (level) on table public.profiles from anon, authenticated;

-- The only supported membership roles are explicit. Existing rows were audited
-- before adding this constraint; the table currently contains no memberships.
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.user_club_members'::regclass
      and conname='user_club_members_role_check'
  ) then
    alter table public.user_club_members
      add constraint user_club_members_role_check
      check (role in ('owner','moderator','member')) not valid;
  end if;
end $$;
alter table public.user_club_members
  validate constraint user_club_members_role_check;

-- A reader may self-join a public club only as an ordinary member. Only the
-- owning account may assign a privileged membership role or manage others.
drop policy if exists uclub_members_insert_authorized on public.user_club_members;
create policy uclub_members_insert_authorized on public.user_club_members
  for insert to authenticated with check (
    (user_id=(select auth.uid()) and role='member' and exists (
      select 1 from public.user_clubs c
      where c.id=club_id and (not c.is_private or c.owner_id=(select auth.uid()))))
    or (role in ('owner','moderator','member') and exists (
      select 1 from public.user_clubs c
      where c.id=club_id and c.owner_id=(select auth.uid())))
  );
drop policy if exists uclub_members_update_authorized on public.user_club_members;
create policy uclub_members_update_authorized on public.user_club_members
  for update to authenticated
  using (user_id=(select auth.uid()) or exists (
    select 1 from public.user_clubs c
    where c.id=club_id and c.owner_id=(select auth.uid())))
  with check (
    (user_id=(select auth.uid()) and role='member' and exists (
      select 1 from public.user_clubs c
      where c.id=club_id and (not c.is_private or c.owner_id=(select auth.uid()))))
    or (role in ('owner','moderator','member') and exists (
      select 1 from public.user_clubs c
      where c.id=club_id and c.owner_id=(select auth.uid())))
  );

-- Keep read-sharing rules separate from write ownership to avoid two
-- permissive SELECT policies where an ALL policy overlaps with SELECT.
drop policy if exists journal_write_own on public.reading_journal_entries;
create policy journal_insert_own on public.reading_journal_entries
  for insert to authenticated with check (user_id=(select auth.uid()));
create policy journal_update_own on public.reading_journal_entries
  for update to authenticated using (user_id=(select auth.uid()))
  with check (user_id=(select auth.uid()));
create policy journal_delete_own on public.reading_journal_entries
  for delete to authenticated using (user_id=(select auth.uid()));

drop policy if exists cpr_own on public.chapter_prompt_responses;
create policy cpr_insert_own on public.chapter_prompt_responses
  for insert to authenticated with check (user_id=(select auth.uid()));
create policy cpr_update_own on public.chapter_prompt_responses
  for update to authenticated using (user_id=(select auth.uid()))
  with check (user_id=(select auth.uid()));
create policy cpr_delete_own on public.chapter_prompt_responses
  for delete to authenticated using (user_id=(select auth.uid()));
