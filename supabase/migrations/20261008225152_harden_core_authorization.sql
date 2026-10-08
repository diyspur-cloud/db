-- Core authorization hardening based on live audit (2026-10-08).
-- Data-preserving except normalization of legacy NULL spoiler thresholds.
-- feed-media was verified empty before it is made private.

-- 1) Profiles: expose only an intentional public projection; role/consent/PII
-- are never directly selectable or updatable by anon/authenticated.
revoke all privileges on table public.profiles from public, anon, authenticated;
grant select (id, username, display_name, avatar_url, bio, level, created_at)
  on table public.profiles to anon, authenticated;
grant insert (id, username, display_name) on table public.profiles to authenticated;
grant update (username, display_name, avatar_url, bio, level)
  on table public.profiles to authenticated;

drop policy if exists profiles_select_all on public.profiles;
create policy profiles_select_public_fields on public.profiles
  for select to anon, authenticated using (true);
drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create or replace view public.v_profiles_public
with (security_invoker = true, security_barrier = true) as
select id, username, display_name, avatar_url, bio, level, created_at
from public.profiles;
revoke all privileges on table public.v_profiles_public from public, anon, authenticated;
grant select on table public.v_profiles_public to anon, authenticated;

create or replace function public.get_my_profile_private()
returns table (whatsapp text, lgpd_consent boolean,
               lgpd_consent_at timestamptz, onboarding_done boolean)
language sql stable security definer set search_path = ''
as $$
  select p.whatsapp, p.lgpd_consent, p.lgpd_consent_at, p.onboarding_done
  from public.profiles p
  where p.id = (select auth.uid()) and (select auth.uid()) is not null;
$$;
revoke all on function public.get_my_profile_private() from public, anon;
grant execute on function public.get_my_profile_private() to authenticated;

create or replace function public.set_my_lgpd_consent(p_consent boolean)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  update public.profiles
     set lgpd_consent = p_consent,
         lgpd_consent_at = case when p_consent then statement_timestamp() else null end,
         updated_at = statement_timestamp()
   where id = (select auth.uid());
  if not found then raise exception 'profile not found' using errcode = 'P0002'; end if;
end;
$$;
revoke all on function public.set_my_lgpd_consent(boolean) from public, anon;
grant execute on function public.set_my_lgpd_consent(boolean) to authenticated;

-- 2) Chapter comments: direct access omits content; the guarded view returns
-- NULL text until the reader's self-reported progress reaches min_percent.
update public.comments set min_percent = case when is_spoiler then 100 else 0 end
where min_percent is null;
alter table public.comments alter column min_percent set default 0;
alter table public.comments alter column min_percent set not null;
do $$ begin
  if not exists (select 1 from pg_constraint where conrelid='public.comments'::regclass
                 and conname='comments_min_percent_range_check') then
    alter table public.comments add constraint comments_min_percent_range_check
      check (min_percent between 0 and 100) not valid;
  end if;
end $$;
alter table public.comments validate constraint comments_min_percent_range_check;
revoke all privileges on table public.comments from public, anon, authenticated;
grant select (id, chapter_id, user_id, parent_id, is_spoiler, min_percent,
              likes_count, replies_count, edited_at, deleted_at, created_at)
  on table public.comments to anon, authenticated;
grant insert (chapter_id, user_id, parent_id, content, is_spoiler, min_percent)
  on table public.comments to authenticated;
grant update (content, is_spoiler, min_percent, edited_at, deleted_at)
  on table public.comments to authenticated;
grant delete on table public.comments to authenticated;
drop policy if exists comments_read on public.comments;
create policy comments_read_active on public.comments
  for select to anon, authenticated using (deleted_at is null);
drop policy if exists comments_insert_auth on public.comments;
create policy comments_insert_own on public.comments
  for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists comments_update_own on public.comments;
create policy comments_update_own on public.comments
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
drop policy if exists comments_delete_own_or_admin on public.comments;
create policy comments_delete_own_or_admin on public.comments
  for delete to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));
create or replace function private.get_visible_comments()
returns table (id uuid, chapter_id uuid, user_id uuid, parent_id uuid,
               created_at timestamptz, likes_count integer, replies_count integer,
               is_spoiler boolean, content text, is_locked boolean)
language sql stable security definer set search_path = ''
as $$
  select c.id, c.chapter_id, c.user_id, c.parent_id, c.created_at,
         c.likes_count, c.replies_count, c.is_spoiler,
         case when c.is_spoiler and coalesce(up.percent,0)<coalesce(c.min_percent,100)
              then null::text else c.content end,
         (c.is_spoiler and coalesce(up.percent,0)<coalesce(c.min_percent,100))
  from public.comments c
  left join public.user_progress up on up.chapter_id=c.chapter_id
    and up.user_id=(select auth.uid())
  where c.deleted_at is null;
$$;
revoke all on function private.get_visible_comments() from public;
grant usage on schema private to anon, authenticated;
grant execute on function private.get_visible_comments() to anon, authenticated;
create or replace view public.v_comments_visible
with (security_invoker = true, security_barrier = true) as
select * from private.get_visible_comments();
revoke all privileges on table public.v_comments_visible from public, anon, authenticated;
grant select on table public.v_comments_visible to anon, authenticated;

-- 3) Centralized private authorization predicates. SECURITY DEFINER is
-- intentional: policies/views need to inspect protected parent/membership rows.
create or replace function private.can_view_feed_post(p_post_id uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.feed_posts p
    where p.id=p_post_id and p.deleted_at is null
      and (p.visibility='public' or p.author_id=(select auth.uid())
        or (p.visibility='followers' and exists (
          select 1 from public.follows f where f.follower_id=(select auth.uid())
            and f.followed_id=p.author_id and f.status='accepted'))
        or (p.visibility='club' and exists (
          select 1 from public.user_club_members m where m.club_id=p.club_id
            and m.user_id=(select auth.uid())))
      )
  );
$$;
revoke all on function private.can_view_feed_post(uuid) from public;
grant usage on schema private to anon, authenticated;
grant execute on function private.can_view_feed_post(uuid) to anon, authenticated;

create or replace function private.can_edit_reading_list(p_list_id uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null and exists (
    select 1 from public.reading_lists l where l.id=p_list_id
      and (l.owner_id=(select auth.uid()) or (l.is_collaborative and exists (
        select 1 from public.reading_list_collaborators c
        where c.list_id=l.id and c.user_id=(select auth.uid()) and c.can_edit)))
  );
$$;
revoke all on function private.can_edit_reading_list(uuid) from public, anon;
grant execute on function private.can_edit_reading_list(uuid) to authenticated;

-- Feed post spoiler payload is available only from this security-barrier view.
revoke all privileges on table public.feed_posts from public, anon, authenticated;
grant select (id, author_id, kind, visibility, club_id, book_id, chapter_id,
              season_id, is_spoiler, min_percent, likes_count, comments_count,
              shares_count, deleted_at, created_at, updated_at)
  on table public.feed_posts to anon, authenticated;
grant insert (author_id, kind, visibility, club_id, book_id, chapter_id, season_id,
              body, quote_text, link_url, cover_url, metadata, is_spoiler, min_percent)
  on table public.feed_posts to authenticated;
grant update (kind, visibility, club_id, book_id, chapter_id, season_id, body,
              quote_text, link_url, cover_url, metadata, is_spoiler, min_percent,
              deleted_at, updated_at) on table public.feed_posts to authenticated;
grant delete on table public.feed_posts to authenticated;
do $$ begin
  if not exists (select 1 from pg_constraint where conrelid='public.feed_posts'::regclass
                 and conname='feed_posts_min_percent_range_check') then
    alter table public.feed_posts add constraint feed_posts_min_percent_range_check
      check (min_percent between 0 and 100) not valid;
  end if;
end $$;
alter table public.feed_posts validate constraint feed_posts_min_percent_range_check;
drop policy if exists feed_posts_read on public.feed_posts;
create policy feed_posts_read_visible on public.feed_posts
  for select to anon, authenticated
  using (deleted_at is null and (visibility='public' or author_id=(select auth.uid())
    or (visibility='followers' and exists (
      select 1 from public.follows f where f.follower_id=(select auth.uid())
        and f.followed_id=feed_posts.author_id and f.status='accepted'))
    or (visibility='club' and exists (
      select 1 from public.user_club_members m where m.club_id=feed_posts.club_id
        and m.user_id=(select auth.uid())))));
drop policy if exists feed_posts_author_write on public.feed_posts;
create policy feed_posts_insert_own on public.feed_posts
  for insert to authenticated with check (author_id=(select auth.uid()));
create policy feed_posts_update_own on public.feed_posts
  for update to authenticated using (author_id=(select auth.uid()))
  with check (author_id=(select auth.uid()));
create policy feed_posts_delete_own on public.feed_posts
  for delete to authenticated using (author_id=(select auth.uid()));
create or replace function private.get_visible_feed_posts()
returns table (id uuid, author_id uuid, kind public.feed_post_kind,
               visibility public.feed_visibility, club_id uuid, book_id uuid,
               chapter_id uuid, season_id uuid, body text, quote_text text,
               link_url text, cover_url text, metadata jsonb, is_spoiler boolean,
               is_locked boolean, min_percent numeric, likes_count integer,
               comments_count integer, shares_count integer,
               created_at timestamptz, updated_at timestamptz)
language sql stable security definer set search_path = ''
as $$
  select p.id,p.author_id,p.kind,p.visibility,p.club_id,p.book_id,p.chapter_id,p.season_id,
         case when p.is_spoiler and coalesce(up.percent,0)<p.min_percent then null::text else p.body end,
         case when p.is_spoiler and coalesce(up.percent,0)<p.min_percent then null::text else p.quote_text end,
         case when p.is_spoiler and coalesce(up.percent,0)<p.min_percent then null::text else p.link_url end,
         p.cover_url,
         case when p.is_spoiler and coalesce(up.percent,0)<p.min_percent then '{}'::jsonb else p.metadata end,
         p.is_spoiler,(p.is_spoiler and coalesce(up.percent,0)<p.min_percent),
         p.min_percent,p.likes_count,p.comments_count,p.shares_count,p.created_at,p.updated_at
  from public.feed_posts p
  left join public.user_progress up on up.user_id=(select auth.uid()) and up.chapter_id=p.chapter_id
  where private.can_view_feed_post(p.id);
$$;
revoke all on function private.get_visible_feed_posts() from public;
grant execute on function private.get_visible_feed_posts() to anon, authenticated;
create or replace view public.v_feed_posts_visible
with (security_invoker = true, security_barrier = true) as
select * from private.get_visible_feed_posts();
revoke all privileges on table public.v_feed_posts_visible from public, anon, authenticated;
grant select on table public.v_feed_posts_visible to anon, authenticated;

-- 4) Quiz answers and scored attempts cannot be fabricated by a browser client.
create or replace view public.v_quiz_questions_public
with (security_invoker = true, security_barrier = true) as
select id,chapter_id,position,question,options from public.quiz_questions;
revoke all privileges on table public.v_quiz_questions_public from public, anon, authenticated;
grant select on table public.v_quiz_questions_public to authenticated;
revoke all privileges on table public.quiz_questions from public, anon, authenticated;
grant select (id, chapter_id, position, question, options)
  on table public.quiz_questions to authenticated;
revoke all privileges on table public.quiz_attempts from public, anon, authenticated;
revoke all privileges on table public.quiz_answers from public, anon, authenticated;
grant select on table public.quiz_attempts, public.quiz_answers to authenticated;
do $$ begin
  if not exists (select 1 from pg_constraint where conrelid='public.quiz_attempts'::regclass and conname='quiz_attempts_score_total_check') then
    alter table public.quiz_attempts add constraint quiz_attempts_score_total_check check (total>0 and score>=0 and score<=total) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conrelid='public.quiz_attempts'::regclass and conname='quiz_attempts_duration_nonnegative_check') then
    alter table public.quiz_attempts add constraint quiz_attempts_duration_nonnegative_check check (duration_ms is null or duration_ms>=0) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conrelid='public.quiz_answers'::regclass and conname='quiz_answers_chosen_idx_nonnegative_check') then
    alter table public.quiz_answers add constraint quiz_answers_chosen_idx_nonnegative_check check (chosen_idx>=0) not valid;
  end if;
end $$;
alter table public.quiz_attempts validate constraint quiz_attempts_score_total_check;
alter table public.quiz_attempts validate constraint quiz_attempts_duration_nonnegative_check;
alter table public.quiz_answers validate constraint quiz_answers_chosen_idx_nonnegative_check;
create index if not exists quiz_attempts_user_created_idx
  on public.quiz_attempts (user_id, created_at desc);

-- 5) Ownership must hold both before and after a list/media/club mutation.
drop policy if exists list_items_write on public.reading_list_items;
create policy list_items_insert_authorized on public.reading_list_items
  for insert to authenticated with check ((added_by is null or added_by=(select auth.uid()))
    and private.can_edit_reading_list(list_id));
create policy list_items_update_authorized on public.reading_list_items
  for update to authenticated using (private.can_edit_reading_list(list_id))
  with check (private.can_edit_reading_list(list_id));
create policy list_items_delete_authorized on public.reading_list_items
  for delete to authenticated using (private.can_edit_reading_list(list_id));
drop policy if exists list_collab_owner on public.reading_list_collaborators;
create policy list_collab_insert_owner on public.reading_list_collaborators
  for insert to authenticated with check (exists (select 1 from public.reading_lists l
    where l.id=list_id and l.owner_id=(select auth.uid())));
create policy list_collab_update_owner on public.reading_list_collaborators
  for update to authenticated using (exists (select 1 from public.reading_lists l
    where l.id=list_id and l.owner_id=(select auth.uid())))
  with check (exists (select 1 from public.reading_lists l
    where l.id=list_id and l.owner_id=(select auth.uid())));
create policy list_collab_delete_owner on public.reading_list_collaborators
  for delete to authenticated using (exists (select 1 from public.reading_lists l
    where l.id=list_id and l.owner_id=(select auth.uid())));

drop policy if exists feed_media_read on public.feed_post_media;
create policy feed_media_read_visible_post on public.feed_post_media
  for select to anon, authenticated using (private.can_view_feed_post(post_id));
drop policy if exists feed_media_author on public.feed_post_media;
create policy feed_media_insert_own_post on public.feed_post_media
  for insert to authenticated with check (exists (select 1 from public.feed_posts p
    where p.id=post_id and p.author_id=(select auth.uid())));
create policy feed_media_update_own_post on public.feed_post_media
  for update to authenticated using (exists (select 1 from public.feed_posts p
    where p.id=post_id and p.author_id=(select auth.uid())))
  with check (exists (select 1 from public.feed_posts p
    where p.id=post_id and p.author_id=(select auth.uid())));
create policy feed_media_delete_own_post on public.feed_post_media
  for delete to authenticated using (exists (select 1 from public.feed_posts p
    where p.id=post_id and p.author_id=(select auth.uid())));

drop policy if exists uclub_members_read on public.user_club_members;
create policy uclub_members_read_visible on public.user_club_members
  for select to anon, authenticated using (user_id=(select auth.uid()) or exists (
    select 1 from public.user_clubs c where c.id=club_id
      and (not c.is_private or c.owner_id=(select auth.uid()))));
drop policy if exists uclub_members_self on public.user_club_members;
create policy uclub_members_insert_authorized on public.user_club_members
  for insert to authenticated with check (
    (user_id=(select auth.uid()) and exists (select 1 from public.user_clubs c
      where c.id=club_id and (not c.is_private or c.owner_id=(select auth.uid()))))
    or exists (select 1 from public.user_clubs c where c.id=club_id and c.owner_id=(select auth.uid())));
create policy uclub_members_update_authorized on public.user_club_members
  for update to authenticated using (user_id=(select auth.uid()) or exists (
    select 1 from public.user_clubs c where c.id=club_id and c.owner_id=(select auth.uid())))
  with check ((user_id=(select auth.uid()) and exists (select 1 from public.user_clubs c
      where c.id=club_id and (not c.is_private or c.owner_id=(select auth.uid()))))
    or exists (select 1 from public.user_clubs c where c.id=club_id and c.owner_id=(select auth.uid())));
create policy uclub_members_delete_authorized on public.user_club_members
  for delete to authenticated using (user_id=(select auth.uid()) or exists (
    select 1 from public.user_clubs c where c.id=club_id and c.owner_id=(select auth.uid())));

-- 6) Social replies/reactions inherit their parent post visibility.
drop policy if exists feed_comments_read on public.feed_post_comments;
create policy feed_comments_read_visible_post on public.feed_post_comments
  for select to anon, authenticated using (deleted_at is null and private.can_view_feed_post(post_id));
drop policy if exists feed_comments_write_own on public.feed_post_comments;
create policy feed_comments_insert_visible_post on public.feed_post_comments
  for insert to authenticated with check (user_id=(select auth.uid()) and private.can_view_feed_post(post_id));
create policy feed_comments_update_own on public.feed_post_comments
  for update to authenticated using (user_id=(select auth.uid()))
  with check (user_id=(select auth.uid()) and private.can_view_feed_post(post_id));
create policy feed_comments_delete_own on public.feed_post_comments
  for delete to authenticated using (user_id=(select auth.uid()));
drop policy if exists feed_likes_read on public.feed_post_likes;
create policy feed_likes_read_visible_post on public.feed_post_likes
  for select to anon, authenticated using (private.can_view_feed_post(post_id));
drop policy if exists feed_likes_own on public.feed_post_likes;
create policy feed_likes_insert_own on public.feed_post_likes
  for insert to authenticated with check (user_id=(select auth.uid()) and private.can_view_feed_post(post_id));
create policy feed_likes_update_own on public.feed_post_likes
  for update to authenticated using (user_id=(select auth.uid()))
  with check (user_id=(select auth.uid()) and private.can_view_feed_post(post_id));
create policy feed_likes_delete_own on public.feed_post_likes
  for delete to authenticated using (user_id=(select auth.uid()));

drop policy if exists bmv_read on public.book_mood_votes;
drop policy if exists bmv_own on public.book_mood_votes;
create policy bmv_select_own on public.book_mood_votes for select to authenticated using (user_id=(select auth.uid()));
create policy bmv_insert_own on public.book_mood_votes for insert to authenticated with check (user_id=(select auth.uid()));
create policy bmv_update_own on public.book_mood_votes for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy bmv_delete_own on public.book_mood_votes for delete to authenticated using (user_id=(select auth.uid()));

-- Friends-only journal entries require accepted follows in both directions.
drop policy if exists journal_read_own on public.reading_journal_entries;
create or replace function private.can_view_club_journal(p_author_id uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null and exists (
    select 1 from public.user_clubs uc
    where ((uc.owner_id=(select auth.uid()) or exists (
             select 1 from public.user_club_members m
             where m.club_id=uc.id and m.user_id=(select auth.uid())))
       and (uc.owner_id=p_author_id or exists (
             select 1 from public.user_club_members m
             where m.club_id=uc.id and m.user_id=p_author_id)))
  );
$$;
revoke all on function private.can_view_club_journal(uuid) from public, anon;
grant execute on function private.can_view_club_journal(uuid) to authenticated;
create policy journal_read_own on public.reading_journal_entries
  for select to authenticated using (user_id=(select auth.uid()) or visibility='public'
    or (visibility='friends' and exists (select 1 from public.follows f1
      where f1.follower_id=(select auth.uid()) and f1.followed_id=user_id and f1.status='accepted'
        and exists (select 1 from public.follows f2 where f2.follower_id=user_id
          and f2.followed_id=(select auth.uid()) and f2.status='accepted')))
    or (visibility='club' and (select private.can_view_club_journal(user_id))));

create or replace function private.can_view_club_prompt_response(p_prompt_id uuid,p_author_id uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null and exists (
    select 1 from public.chapter_prompts cp
    join public.chapters ch on ch.id=cp.chapter_id
    join public.seasons s on s.id=ch.season_id
    join public.user_clubs uc on uc.current_book_id=s.book_id
      and (uc.current_season_id is null or uc.current_season_id=s.id)
    where cp.id=p_prompt_id
      and (uc.owner_id=(select auth.uid()) or exists (select 1 from public.user_club_members m
        where m.club_id=uc.id and m.user_id=(select auth.uid())))
      and (uc.owner_id=p_author_id or exists (select 1 from public.user_club_members m
        where m.club_id=uc.id and m.user_id=p_author_id))
  );
$$;
revoke all on function private.can_view_club_prompt_response(uuid,uuid) from public, anon;
grant execute on function private.can_view_club_prompt_response(uuid,uuid) to authenticated;
drop policy if exists cpr_read on public.chapter_prompt_responses;
create policy cpr_read on public.chapter_prompt_responses for select to authenticated
  using (user_id=(select auth.uid()) or visibility='public'
    or (visibility='friends' and exists (select 1 from public.follows f1
      where f1.follower_id=(select auth.uid()) and f1.followed_id=user_id and f1.status='accepted'
        and exists (select 1 from public.follows f2 where f2.follower_id=user_id
          and f2.followed_id=(select auth.uid()) and f2.status='accepted')))
    or (visibility='club' and (select private.can_view_club_prompt_response(prompt_id,user_id))));

-- 7) Storage: feed-media is empty; privatize it and bind object reads to posts.
do $$ begin
  if exists (select 1 from storage.objects where bucket_id='feed-media' limit 1) then
    raise exception 'feed-media is no longer empty; review existing objects before privatizing';
  end if;
end $$;
update storage.buckets set public=false where id='feed-media';
drop policy if exists feed_media_read on storage.objects;
create policy feed_media_read_visible_post on storage.objects
  for select to anon, authenticated using (bucket_id='feed-media' and (
    auth.uid()::text=(storage.foldername(name))[1]
    or exists (select 1 from public.feed_post_media fm
      where fm.storage_path=storage.objects.name and private.can_view_feed_post(fm.post_id))));
drop policy if exists feed_media_author_write on storage.objects;
create policy feed_media_author_insert on storage.objects
  for insert to authenticated with check (bucket_id='feed-media'
    and auth.uid()::text=(storage.foldername(name))[1]);
drop policy if exists feed_media_author_update on storage.objects;
create policy feed_media_author_update on storage.objects
  for update to authenticated using (bucket_id='feed-media'
    and auth.uid()::text=(storage.foldername(name))[1])
  with check (bucket_id='feed-media' and auth.uid()::text=(storage.foldername(name))[1]);
create policy feed_media_author_delete on storage.objects
  for delete to authenticated using (bucket_id='feed-media'
    and auth.uid()::text=(storage.foldername(name))[1]);

drop policy if exists chapter_extras_read_auth on storage.objects;
create policy chapter_extras_read_public_or_admin on storage.objects
  for select to authenticated using (bucket_id='chapter-extras' and (
    (select public.is_admin()) or exists (select 1 from public.chapter_extra_content cec
      where cec.storage_path=storage.objects.name and cec.is_public)));
drop policy if exists manuscripts_admin_only on storage.objects;
create policy manuscripts_admin_only on storage.objects for all to authenticated
  using (bucket_id='manuscripts' and (select public.is_admin()))
  with check (bucket_id='manuscripts' and (select public.is_admin()));
