import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const db = new PGlite();
const bootstrap = `
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth; create schema private; create schema storage;
create function auth.uid() returns uuid language sql stable as $$
 select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create function auth.role() returns text language sql stable as $$
 select nullif(current_setting('request.jwt.claim.role',true),'') $$;
grant usage on schema auth to anon, authenticated;
grant execute on all functions in schema auth to anon, authenticated;
create function storage.foldername(text) returns text[] language sql immutable as $$
 select (string_to_array($1,'/'))[1:greatest(array_length(string_to_array($1,'/'),1)-1,0)] $$;
create type public.xp_source as enum ('join_meeting','finish_chapter','comment','quiz_answer','finish_book','streak_bonus');
create type public.user_role as enum ('reader','ambassador','editor','admin');
create type public.journal_visibility as enum ('private','friends','club','public');
create type public.reading_list_visibility as enum ('private','unlisted','public');
create type public.feed_post_kind as enum ('quote','note');
create type public.feed_visibility as enum ('public','followers','club','private');
create table public.profiles(id uuid primary key,username text,display_name text,avatar_url text,bio text,level text,created_at timestamptz default now(),role public.user_role not null default 'reader',whatsapp text,lgpd_consent boolean,lgpd_consent_at timestamptz,onboarding_done boolean,updated_at timestamptz default now());
create table public.comments(id uuid primary key default gen_random_uuid(),chapter_id uuid not null,user_id uuid not null,parent_id uuid,content text not null,is_spoiler boolean not null default false,min_percent numeric default 0,likes_count integer not null default 0,replies_count integer not null default 0,edited_at timestamptz,deleted_at timestamptz,created_at timestamptz not null default now());
create table public.reactions(id uuid primary key default gen_random_uuid(),comment_id uuid not null,user_id uuid not null,kind text not null default 'like');
create table public.user_progress(user_id uuid,chapter_id uuid,percent numeric default 0,updated_at timestamptz not null default now(),primary key(user_id,chapter_id));
create table public.user_streaks(user_id uuid primary key,current_streak integer not null default 0,longest_streak integer not null default 0,last_activity_at date,updated_at timestamptz not null default now());
create table public.xp_events(id uuid primary key default gen_random_uuid(),user_id uuid not null,source public.xp_source not null,amount integer not null,ref_id uuid,created_at timestamptz not null default now());
create unique index xp_events_daily_ref on public.xp_events(user_id,source,ref_id) where ref_id is not null;
create table public.user_xp(user_id uuid primary key,total_xp integer not null default 0,season_xp integer not null default 0,updated_at timestamptz not null default now());
create table public.feed_posts(id uuid primary key,author_id uuid not null,kind public.feed_post_kind,visibility public.feed_visibility not null,club_id uuid,book_id uuid,chapter_id uuid,season_id uuid,body text,quote_text text,link_url text,cover_url text,metadata jsonb not null default '{}',is_spoiler boolean not null default false,min_percent numeric not null default 0,likes_count integer not null default 0,comments_count integer not null default 0,shares_count integer not null default 0,deleted_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.follows(follower_id uuid,followed_id uuid,status text);
create table public.user_clubs(id uuid primary key,owner_id uuid not null,is_private boolean not null default false,current_book_id uuid,current_season_id uuid);
create table public.user_club_members(club_id uuid,user_id uuid,role text not null default 'member',primary key(club_id,user_id));
create table public.reading_lists(id uuid primary key,owner_id uuid not null,is_collaborative boolean not null default false,visibility public.reading_list_visibility not null default 'private');
create table public.reading_list_collaborators(list_id uuid,user_id uuid,can_edit boolean not null default true);
create table public.reading_list_items(id uuid primary key,list_id uuid not null,added_by uuid,kind text,position integer default 0);
create table public.buddy_reads(id uuid primary key,book_id uuid not null,owner_id uuid not null,is_private boolean not null default true,max_members integer not null default 3);
create table public.buddy_read_members(buddy_read_id uuid not null,user_id uuid not null,primary key(buddy_read_id,user_id));
create table public.buddy_read_checkpoints(id uuid primary key,buddy_read_id uuid not null,position integer not null,title text not null);
create table public.editorial_picks(id uuid primary key,book_id uuid not null,is_active boolean not null default true,title text);
create table public.chapter_extra_content(id uuid primary key,storage_path text,is_public boolean not null default false,created_by uuid);
create table public.feed_post_media(id uuid primary key,post_id uuid not null,storage_path text);
create table public.feed_post_comments(id uuid primary key,post_id uuid not null,user_id uuid not null,deleted_at timestamptz);
create table public.feed_post_likes(post_id uuid,user_id uuid,primary key(post_id,user_id));
create table public.book_mood_votes(user_id uuid,book_id uuid);
create table public.reading_journal_entries(id uuid primary key,user_id uuid not null,visibility journal_visibility not null);
create table public.chapter_prompts(id uuid primary key,chapter_id uuid not null);
create table public.chapters(id uuid primary key,season_id uuid);
create table public.seasons(id uuid primary key,book_id uuid);
create table public.chapter_prompt_responses(prompt_id uuid,user_id uuid,response text,visibility journal_visibility);
create table public.quiz_questions(id uuid primary key,chapter_id uuid not null,position integer not null,question text not null,options jsonb not null,correct_idx integer not null,explanation text);
create table public.quiz_attempts(id uuid primary key,user_id uuid not null,chapter_id uuid not null,score integer not null,total integer not null,duration_ms integer,created_at timestamptz not null default now());
create table public.quiz_answers(attempt_id uuid not null,question_id uuid not null,chosen_idx integer not null,is_correct boolean not null);
create table storage.buckets(id text primary key,public boolean not null);
create table storage.objects(bucket_id text,name text);
create function public.is_admin() returns boolean language sql stable security invoker as $$ select false $$;

grant usage on schema storage to anon,authenticated,service_role;

grant all on public.profiles,public.comments,public.reactions,public.user_progress,public.user_streaks,public.xp_events,public.user_xp,public.quiz_questions,public.quiz_attempts,public.quiz_answers,public.follows,public.reading_lists,public.reading_list_items,public.reading_list_collaborators,public.buddy_reads,public.buddy_read_members,public.buddy_read_checkpoints,public.editorial_picks,public.user_clubs,public.user_club_members,public.feed_post_media,public.feed_post_comments,public.feed_post_likes,public.book_mood_votes,public.reading_journal_entries,public.chapter_prompt_responses,public.chapter_prompts,public.chapters,public.seasons,public.chapter_extra_content,storage.objects,storage.buckets to anon,authenticated;
grant select on public.xp_events to service_role;
insert into storage.buckets values ('feed-media',true),('chapter-extras',false),('manuscripts',false);
create function public.award_xp(p_user uuid,p_source public.xp_source,p_amount integer,p_ref uuid default null)
returns void language plpgsql security definer set search_path='' as $$
begin
  insert into public.xp_events(user_id,source,amount,ref_id) values (p_user,p_source,p_amount,p_ref)
  on conflict (user_id,source,ref_id) where ref_id is not null do nothing;
  if found then
    insert into public.user_xp(user_id,total_xp) values (p_user,p_amount)
    on conflict (user_id) do update set total_xp=public.user_xp.total_xp+excluded.total_xp;
  end if;
end $$;
grant execute on function public.award_xp(uuid,public.xp_source,integer,uuid) to service_role;
create function public.bump_comment_likes() returns trigger language plpgsql as $$ begin return null; end $$;
create function public.bump_comment_replies() returns trigger language plpgsql as $$ begin return null; end $$;
create function public.touch_streak() returns trigger language plpgsql as $$ begin return null; end $$;
create function public.bump_feed_post_counters() returns trigger language plpgsql as $$ begin return null; end $$;
`;

await db.exec(bootstrap);
for (const table of ['profiles','comments','reactions','user_progress','user_streaks','xp_events','user_xp','feed_posts','quiz_questions','quiz_attempts','quiz_answers','reading_lists','reading_list_items','reading_list_collaborators','buddy_reads','buddy_read_members','buddy_read_checkpoints','editorial_picks','chapter_extra_content','user_club_members','feed_post_media','feed_post_comments','feed_post_likes','book_mood_votes','reading_journal_entries','chapter_prompt_responses']) {
  await db.exec(`alter table public.${table} enable row level security;`);
}
await db.exec('alter table storage.objects enable row level security;');
for (const filename of [
  '20261008225152_harden_core_authorization.sql',
  '20261008225535_prevent_client_privilege_escalation.sql',
  '20261008225856_encapsulate_profile_consent_privilege.sql',
  '20261009025153_fix_buddy_read_policy_recursion.sql',
  '20261009025155_fix_reading_list_policy_recursion.sql',
  '20261009025157_restore_admin_predicate.sql',
  '20261009025159_restore_internal_counter_triggers.sql',
  '20261009025201_restore_profile_onboarding_contract.sql',
  '20261009025524_award_daily_streak_bonus.sql',
]) {
  await db.exec(await readFile(resolve(repoRoot, 'supabase/migrations', filename), 'utf8'));
}
await db.exec(`
drop policy if exists buddy_reads_owner_write on public.buddy_reads;
create policy buddy_reads_owner_write on public.buddy_reads for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
drop policy if exists buddy_members_read on public.buddy_read_members;
create policy buddy_members_read on public.buddy_read_members for select to anon, authenticated
  using (exists (select 1 from public.buddy_reads br where br.id = buddy_read_id
    and (not br.is_private or br.owner_id = (select auth.uid()))));
drop policy if exists buddy_members_self_join on public.buddy_read_members;
create policy buddy_members_self_join on public.buddy_read_members for insert to authenticated
  with check (user_id = (select auth.uid()) and exists (select 1 from public.buddy_reads br
    where br.id = buddy_read_id and (not br.is_private or br.owner_id = (select auth.uid())
      or exists (select 1 from public.buddy_read_members m2 where m2.buddy_read_id = br.id
        and m2.user_id = (select auth.uid())))));
drop policy if exists buddy_members_self_leave on public.buddy_read_members;
create policy buddy_members_self_leave on public.buddy_read_members for delete to authenticated
  using (user_id = (select auth.uid()) or exists (select 1 from public.buddy_reads br
    where br.id = buddy_read_id and br.owner_id = (select auth.uid())));
drop policy if exists buddy_checkpoints_read on public.buddy_read_checkpoints;
create policy buddy_checkpoints_read on public.buddy_read_checkpoints for select to anon, authenticated
  using (private.can_view_buddy_read(buddy_read_id));
drop policy if exists buddy_checkpoints_write on public.buddy_read_checkpoints;
create policy buddy_checkpoints_write on public.buddy_read_checkpoints for all to authenticated
  using (exists (select 1 from public.buddy_reads br where br.id = buddy_read_id
    and br.owner_id = (select auth.uid())))
  with check (exists (select 1 from public.buddy_reads br where br.id = buddy_read_id
    and br.owner_id = (select auth.uid())));
drop policy if exists lists_owner_write on public.reading_lists;
create policy lists_owner_write on public.reading_lists for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
drop policy if exists list_items_read on public.reading_list_items;
create policy list_items_read on public.reading_list_items for select to anon, authenticated
  using (exists (select 1 from public.reading_lists l where l.id = list_id and
    (l.visibility = 'public' or l.owner_id = (select auth.uid()) or exists (
      select 1 from public.reading_list_collaborators c where c.list_id = l.id
        and c.user_id = (select auth.uid())))));
drop policy if exists list_items_insert_authorized on public.reading_list_items;
create policy list_items_insert_authorized on public.reading_list_items for insert to authenticated
  with check ((added_by is null or added_by = (select auth.uid()))
    and private.can_edit_reading_list(list_id));
drop policy if exists list_items_update_authorized on public.reading_list_items;
create policy list_items_update_authorized on public.reading_list_items for update to authenticated
  using (private.can_edit_reading_list(list_id))
  with check (private.can_edit_reading_list(list_id));
drop policy if exists list_items_delete_authorized on public.reading_list_items;
create policy list_items_delete_authorized on public.reading_list_items for delete to authenticated
  using (private.can_edit_reading_list(list_id));
drop policy if exists list_collab_read on public.reading_list_collaborators;
create policy list_collab_read on public.reading_list_collaborators for select to anon, authenticated
  using (user_id = (select auth.uid()) or exists (select 1 from public.reading_lists l
    where l.id = list_id and l.owner_id = (select auth.uid())));
drop policy if exists list_collab_insert_owner on public.reading_list_collaborators;
create policy list_collab_insert_owner on public.reading_list_collaborators for insert to authenticated
  with check (exists (select 1 from public.reading_lists l where l.id = list_id
    and l.owner_id = (select auth.uid())));
drop policy if exists list_collab_update_owner on public.reading_list_collaborators;
create policy list_collab_update_owner on public.reading_list_collaborators for update to authenticated
  using (exists (select 1 from public.reading_lists l where l.id = list_id
    and l.owner_id = (select auth.uid())))
  with check (exists (select 1 from public.reading_lists l where l.id = list_id
    and l.owner_id = (select auth.uid())));
drop policy if exists list_collab_delete_owner on public.reading_list_collaborators;
create policy list_collab_delete_owner on public.reading_list_collaborators for delete to authenticated
  using (exists (select 1 from public.reading_lists l where l.id = list_id
    and l.owner_id = (select auth.uid())));
drop policy if exists editorial_read on public.editorial_picks;
create policy editorial_read on public.editorial_picks for select to anon, authenticated using (is_active);
drop policy if exists editorial_admin on public.editorial_picks;
create policy editorial_admin on public.editorial_picks for all to anon, authenticated
  using (public.is_admin()) with check (public.is_admin());
drop policy if exists cec_read on public.chapter_extra_content;
create policy cec_read on public.chapter_extra_content for select to anon, authenticated
  using (is_public or public.is_admin());
drop policy if exists cec_admin on public.chapter_extra_content;
create policy cec_admin on public.chapter_extra_content for all to anon, authenticated
  using (public.is_admin()) with check (public.is_admin());
drop policy if exists reactions_read on public.reactions;
create policy reactions_read on public.reactions for select to anon, authenticated using (true);
drop policy if exists reactions_own on public.reactions;
create policy reactions_own on public.reactions for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy if exists progress_own on public.user_progress;
create policy progress_own on public.user_progress for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy if exists feed_media_read_visible_post on storage.objects;
create policy feed_media_read_visible_post on storage.objects for select to anon, authenticated
  using (bucket_id = 'feed-media' and (auth.uid()::text = (storage.foldername(name))[1]
    or exists (select 1 from public.feed_post_media fm where fm.storage_path = storage.objects.name
      and private.can_view_feed_post(fm.post_id))));
drop policy if exists feed_media_author_insert on storage.objects;
create policy feed_media_author_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'feed-media' and auth.uid()::text = (storage.foldername(name))[1]);
drop policy if exists chapter_extras_read_public_or_admin on storage.objects;
create policy chapter_extras_read_public_or_admin on storage.objects for select to authenticated
  using (bucket_id = 'chapter-extras' and (public.is_admin() or exists (
    select 1 from public.chapter_extra_content cec where cec.storage_path = storage.objects.name
      and cec.is_public)));
drop policy if exists manuscripts_admin_only on storage.objects;
create policy manuscripts_admin_only on storage.objects for all to authenticated
  using (bucket_id = 'manuscripts' and public.is_admin())
  with check (bucket_id = 'manuscripts' and public.is_admin());
`);
console.log('MIGRATIONS APPLY OK (PostgreSQL WASM)');
const publicProfileDefiners=await db.query(`select count(*)::int as total from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('get_my_profile_private','set_my_lgpd_consent') and p.prosecdef`);
assert.equal(publicProfileDefiners.rows[0]?.total,0,'profile RPCs exposed in public must be SECURITY INVOKER');

const uid1='11111111-1111-4111-8111-111111111111';
const uid2='22222222-2222-4222-8222-222222222222';
const uid3='33333333-3333-4333-8333-333333333334';
const uid4='44444444-4444-4444-8444-444444444445';
const chapter='33333333-3333-4333-8333-333333333333';
const publicPost='44444444-4444-4444-8444-444444444444';
const list='55555555-5555-4555-8555-555555555555';
const ownerList='55555555-5555-4555-8555-555555555556';
const listItem='55555555-5555-4555-8555-555555555557';
const privateBuddy='77777777-7777-4777-8777-777777777771';
const publicBuddy='77777777-7777-4777-8777-777777777772';
const privateClub='66666666-6666-4666-8666-666666666666';
const publicClub='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const privatePost='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
await db.query(`insert into public.profiles(id,username,display_name,role,whatsapp,lgpd_consent,level) values
  ($1,'owner','Owner','admin','secret',true,'junior'),($2,'other','Other','reader','private',false,'estudante'),
  ($3,'editor','Editor','reader','editor-secret',false,'pleno'),($4,'third','Third','reader','third-secret',false,'senior')`,[uid1,uid2,uid3,uid4]);
await db.query(`insert into public.user_streaks(user_id) values ($1),($2),($3),($4)`,[uid1,uid2,uid3,uid4]);
await db.query(`insert into public.comments(id,chapter_id,user_id,content,is_spoiler,min_percent) values ('77777777-7777-4777-8777-777777777777',$1,$2,'secret spoiler',true,50)`,[chapter,uid1]);
await db.query(`insert into public.feed_posts(id,author_id,kind,visibility,chapter_id,body,quote_text,metadata,is_spoiler,min_percent) values ($1,$2,'quote','public',$3,'secret post','secret quote','{"secret":true}',true,50),($4,$5,'note','private',$3,'private post',null,'{"private":true}',false,0)`,[publicPost,uid1,chapter,privatePost,uid2]);
await db.query(`insert into public.feed_post_media(id,post_id,storage_path) values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd',$1,'${uid1}/post.png')`,[publicPost]);
await db.query(`insert into public.quiz_questions values ('88888888-8888-4888-8888-888888888888',$1,1,'Q','["a","b"]',1,'answer')`,[chapter]);
await db.query(`insert into public.reading_lists values ($1,$2,false,'private')`,[list,uid2]);
await db.query(`insert into public.reading_lists values ($1,$2,true,'private')`,[ownerList,uid1]);
await db.query(`insert into public.reading_list_collaborators(list_id,user_id,can_edit) values ($1,$2,true),($1,$3,false)`,[ownerList,uid3,uid2]);
await db.query(`insert into public.reading_list_items(id,list_id,added_by,kind) values ($1,$2,$3,'book')`,[listItem,ownerList,uid1]);
await db.query(`insert into public.buddy_reads(id,book_id,owner_id,is_private) values ($1,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',$2,true),($3,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',$4,false)`,[privateBuddy,uid1,publicBuddy,uid1]);
await db.query(`insert into public.buddy_read_members(buddy_read_id,user_id) values ($1,$2)`,[privateBuddy,uid2]);
await db.query(`insert into public.buddy_read_checkpoints(id,buddy_read_id,position,title) values ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',$1,1,'Checkpoint')`,[privateBuddy]);
await db.query(`insert into public.editorial_picks(id,book_id,title,is_active) values ('99999999-9999-4999-8999-999999999991','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Active pick',true),('99999999-9999-4999-8999-999999999992','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Inactive pick',false)`);
await db.query(`insert into public.chapter_extra_content(id,storage_path,is_public,created_by) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1','extras/public.pdf',true,$1),('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2','extras/private.pdf',false,$1)`,[uid1]);
await db.query(`insert into storage.objects(bucket_id,name) values ('feed-media',$1),('chapter-extras','extras/public.pdf'),('chapter-extras','extras/private.pdf'),('manuscripts','secret.docx')`,[`${uid1}/post.png`]);
await db.query(`insert into public.user_clubs(id,owner_id,is_private) values ($1,$2,true),($3,$2,false)`,[privateClub,uid2,publicClub]);
await db.query(`insert into public.user_progress(user_id,chapter_id,percent) values ($1,$2,0)`,[uid1,chapter]);

const commentView=await db.query('select content,is_locked from public.v_comments_visible');
assert.equal(commentView.rows[0]?.content,null,'comment spoiler must be masked without sufficient progress');
assert.equal(commentView.rows[0]?.is_locked,true);
const postView=await db.query('select body,quote_text,metadata,is_locked from public.v_feed_posts_visible');
assert.equal(postView.rows.length,1,'private post must not be visible anonymously');
assert.equal(postView.rows[0]?.body,null,'feed spoiler body must be masked');
assert.equal(postView.rows[0]?.quote_text,null,'feed spoiler quote must be masked');
assert.equal(postView.rows[0]?.metadata?.secret,undefined,'feed spoiler metadata must be masked');
assert.equal(postView.rows[0]?.is_locked,true);
const quizView=await db.query('select id,question,options from public.v_quiz_questions_public');
assert.equal(quizView.rows.length,1);
assert.equal('correct_idx' in quizView.rows[0],false,'quiz answer fields must not be projected');
console.log('PASS: anonymous views mask spoilers, private posts, and quiz answers');

async function expectDenied(label, sql) {
  try { await db.exec(sql); throw new Error(`${label}: operation unexpectedly succeeded`); }
  catch (error) {
    if (String(error.message).includes('unexpectedly succeeded')) throw error;
    console.log(`PASS denied: ${label}`);
  }
}
async function expectNoRows(label, sql, params = []) {
  const result = await db.query(sql, params);
  assert.equal(result.rows.length, 0, `${label}: RLS unexpectedly affected a row`);
  console.log(`PASS no rows: ${label}`);
}
await db.exec('set role anon');
await expectDenied('anon direct comment body', 'select content from public.comments limit 1');
await expectDenied('anon direct profile PII', 'select whatsapp from public.profiles limit 1');
await expectDenied('anon private profile RPC', 'select * from public.get_my_profile_private()');
await db.exec('reset role');
await db.exec(`select set_config('request.jwt.claim.sub','${uid1}',false); set role authenticated`);
const ownProfile=await db.query('select username from public.v_profiles_public where id=$1',[uid1]);
assert.equal(ownProfile.rows.length,1,'safe profile view must remain available');
await expectDenied('authenticated direct profile PII',`select whatsapp from public.profiles where id='${uid1}'`);
const privateProfile=await db.query('select whatsapp,lgpd_consent,lgpd_consent_at from public.get_my_profile_private()');
assert.equal(privateProfile.rows[0]?.whatsapp,'secret','profile RPC must return only the signed-in user profile');
assert.equal(privateProfile.rows[0]?.lgpd_consent,true);
await db.query('select public.set_my_lgpd_consent(false)');
const withdrawnConsent=await db.query('select lgpd_consent,lgpd_consent_at from public.get_my_profile_private()');
assert.equal(withdrawnConsent.rows[0]?.lgpd_consent,false);
assert.equal(withdrawnConsent.rows[0]?.lgpd_consent_at,null,'withdrawal clears the consent timestamp');
await db.query('select public.set_my_lgpd_consent(true)');
const grantedConsent=await db.query('select lgpd_consent,lgpd_consent_at from public.get_my_profile_private()');
assert.equal(grantedConsent.rows[0]?.lgpd_consent,true);
assert.ok(grantedConsent.rows[0]?.lgpd_consent_at,'grant timestamp must be database-generated');
await expectDenied('client-edited consent timestamp',`update public.profiles set lgpd_consent_at='2000-01-01' where id='${uid1}'`);
await expectDenied('role escalation',`update public.profiles set role='admin' where id='${uid1}'`);
await db.query(`update public.profiles set level='senior',onboarding_done=true where id=$1`,[uid1]);
assert.equal((await db.query('select level from public.v_profiles_public where id=$1',[uid1])).rows[0]?.level,'senior');
assert.equal((await db.query('select onboarding_done from public.get_my_profile_private()')).rows[0]?.onboarding_done,true);
await expectNoRows('cross-owner onboarding update',`update public.profiles set level='lideranca' where id='${uid2}' returning id`);
await expectDenied('client quiz attempt insert',`insert into public.quiz_attempts(id,user_id,chapter_id,score,total) values ('99999999-9999-4999-8999-999999999999','${uid1}','${chapter}',1,1)`);
await expectDenied('cross-owner list mutation',`insert into public.reading_list_items(id,list_id,added_by,kind) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','${list}','${uid1}','book')`);
await expectDenied('self-join private club',`insert into public.user_club_members(club_id,user_id) values ('${privateClub}','${uid1}')`);
await expectDenied('self-assign club owner role',`insert into public.user_club_members(club_id,user_id,role) values ('${publicClub}','${uid1}','owner')`);
await db.query(`insert into public.user_club_members(club_id,user_id,role) values ($1,$2,'member')`,[publicClub,uid1]);
await expectDenied('self-promote club role',`update public.user_club_members set role='moderator' where club_id='${publicClub}' and user_id='${uid1}'`);
const privateFeedAsOther=await db.query(`select id from public.v_feed_posts_visible where id=$1`,[privatePost]);
assert.equal(privateFeedAsOther.rows.length,0,'non-member must not see another user private post');
const lockedAsReader=await db.query(`select content,is_locked from public.v_comments_visible`);
assert.equal(lockedAsReader.rows[0]?.content,null);
await db.exec('reset role');
await db.query(`update public.user_progress set percent=100 where user_id=$1 and chapter_id=$2`,[uid1,chapter]);
await db.exec(`select set_config('request.jwt.claim.sub','${uid1}',false); set role authenticated`);
const unlockedComment=await db.query('select content,is_locked from public.v_comments_visible');
assert.equal(unlockedComment.rows[0]?.content,'secret spoiler','eligible reader must see the unmasked comment');
assert.equal(unlockedComment.rows[0]?.is_locked,false);
await db.exec('reset role');
await db.exec(`select set_config('request.jwt.claim.sub','${uid2}',false); set role authenticated`);
await db.query(`update public.user_club_members set role='moderator' where club_id=$1 and user_id=$2`,[publicClub,uid1]);
const promotedByOwner=await db.query(`select role from public.user_club_members where club_id=$1 and user_id=$2`,[publicClub,uid1]);
assert.equal(promotedByOwner.rows[0]?.role,'moderator','club owner must retain ability to assign roles');
const ownPrivateFeed=await db.query(`select id from public.v_feed_posts_visible where id=$1`,[privatePost]);
assert.equal(ownPrivateFeed.rows.length,1,'author must retain access to own private post');
console.log('PASS: eligible-reader spoiler unlock and owner-authorized club/private-feed access');

// The admin helper is the real private SECURITY DEFINER implementation, not a
// privileged public stub.  Direct profile role/PII access remains denied.
await db.exec(`reset role; select set_config('request.jwt.claim.sub','',false); set role anon`);
assert.equal((await db.query('select public.is_admin() as value')).rows[0].value,false);
assert.equal((await db.query('select id from public.editorial_picks where is_active')).rows.length,1);
assert.equal((await db.query("select id from public.editorial_picks where not is_active")).rows.length,0);
await expectDenied('anon direct profile role', 'select role from public.profiles limit 1');
await db.exec(`reset role; select set_config('request.jwt.claim.sub','${uid2}',false); set role authenticated`);
assert.equal((await db.query('select public.is_admin() as value')).rows[0].value,false);
await expectDenied('reader editorial write', `insert into public.editorial_picks(id,book_id,title) values ('99999999-9999-4999-8999-999999999993','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','forbidden')`);
await expectDenied('reader manuscript write', `insert into storage.objects(bucket_id,name) values ('manuscripts','reader.docx')`);
const readerExtras = await db.query("select name from storage.objects where bucket_id='chapter-extras' order by name");
assert.deepEqual(readerExtras.rows.map((row) => row.name), ['extras/public.pdf']);
assert.equal((await db.query("select name from storage.objects where bucket_id='manuscripts'")).rows.length,0);
await db.exec(`reset role; select set_config('request.jwt.claim.sub','${uid1}',false); set role authenticated`);
assert.equal((await db.query('select public.is_admin() as value')).rows[0].value,true);
await db.query(`insert into public.editorial_picks(id,book_id,title) values ('99999999-9999-4999-8999-999999999993','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','admin pick')`);
await db.query("insert into storage.objects(bucket_id,name) values ('manuscripts','admin.docx')");
assert.equal((await db.query("select name from storage.objects where bucket_id='manuscripts' order by name")).rows.length,2);
await expectDenied('admin direct profile role grant', `select role from public.profiles where id='${uid1}'`);
console.log('PASS: is_admin false/true identities, editorial policy, and Storage admin boundaries');

// Buddy Reads and custom lists exercise the fixed parent/helper policies and
// explicitly cover the no-recursion and no-IDOR cases.
await db.exec(`reset role; select set_config('request.jwt.claim.sub','',false); set role anon`);
assert.equal((await db.query('select id from public.buddy_reads where id=$1',[privateBuddy])).rows.length,0);
assert.equal((await db.query('select id from public.buddy_reads where id=$1',[publicBuddy])).rows.length,1);
assert.equal((await db.query('select buddy_read_id from public.buddy_read_members where buddy_read_id=$1',[privateBuddy])).rows.length,0);
assert.equal((await db.query('select id from public.reading_lists where id=$1',[ownerList])).rows.length,0);
await db.exec(`reset role; select set_config('request.jwt.claim.sub','${uid2}',false); set role authenticated`);
assert.equal((await db.query('select id from public.buddy_reads where id=$1',[privateBuddy])).rows.length,1);
assert.equal((await db.query('select id from public.buddy_read_checkpoints where buddy_read_id=$1',[privateBuddy])).rows.length,1);
assert.equal((await db.query('select id from public.reading_lists where id=$1',[ownerList])).rows.length,1);
assert.equal((await db.query('select id from public.reading_list_items where id=$1',[listItem])).rows.length,1);
await expectNoRows('buddy member cannot edit owner checkpoint', `update public.buddy_read_checkpoints set title='forbidden' where buddy_read_id='${privateBuddy}' returning id`);
await expectNoRows('read-only collaborator cannot edit list item', `update public.reading_list_items set position=9 where id='${listItem}' returning id`);
await db.exec(`reset role; select set_config('request.jwt.claim.sub','${uid3}',false); set role authenticated`);
assert.equal((await db.query('select id from public.buddy_reads where id=$1',[privateBuddy])).rows.length,0);
assert.equal((await db.query('select id from public.reading_lists where id=$1',[ownerList])).rows.length,1);
await db.query(`update public.reading_list_items set position=2 where id=$1`,[listItem]);
assert.equal((await db.query('select position from public.reading_list_items where id=$1',[listItem])).rows[0].position,2);
await expectDenied('collaborator list IDOR through list_id swap', `update public.reading_list_items set list_id='${list}' where id='${listItem}'`);
await db.exec(`reset role; select set_config('request.jwt.claim.sub','${uid1}',false); set role authenticated`);
await db.query(`insert into public.buddy_read_checkpoints(id,buddy_read_id,position,title) values ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeef',$1,2,'Owner checkpoint')`,[privateBuddy]);
console.log('PASS: Buddy Reads/List selects, edit ownership, collaborator can_edit, and IDOR checks');

// Counters and streak are maintained by private trigger functions while the
// input mutations still happen through ordinary authenticated clients.
await db.exec(`reset role; select set_config('request.jwt.claim.sub','${uid2}',false); set role authenticated`);
await db.query(`insert into public.reactions(id,comment_id,user_id) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2','77777777-7777-4777-8777-777777777777',$1)`,[uid2]);
assert.equal((await db.query("select likes_count from public.comments where id='77777777-7777-4777-8777-777777777777'")).rows[0].likes_count,1);
await db.query(`delete from public.reactions where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'`);
assert.equal((await db.query("select likes_count from public.comments where id='77777777-7777-4777-8777-777777777777'")).rows[0].likes_count,0);
const reply = await db.query(`insert into public.comments(chapter_id,user_id,parent_id,content) values ($1,$2,'77777777-7777-4777-8777-777777777777','reply') returning id`,[chapter,uid2]);
assert.equal((await db.query("select replies_count from public.comments where id='77777777-7777-4777-8777-777777777777'")).rows[0].replies_count,1);
await db.query(`delete from public.comments where id=$1`,[reply.rows[0].id]);
assert.equal((await db.query("select replies_count from public.comments where id='77777777-7777-4777-8777-777777777777'")).rows[0].replies_count,0);
await db.query(`insert into public.feed_post_likes(post_id,user_id) values ($1,$2)`,[publicPost,uid2]);
assert.equal((await db.query('select likes_count from public.feed_posts where id=$1',[publicPost])).rows[0].likes_count,1);
await db.query(`delete from public.feed_post_likes where post_id=$1 and user_id=$2`,[publicPost,uid2]);
await db.query(`insert into public.feed_post_comments(id,post_id,user_id) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4',$1,$2)`,[publicPost,uid2]);
assert.equal((await db.query('select comments_count from public.feed_posts where id=$1',[publicPost])).rows[0].comments_count,1);
await db.query(`delete from public.feed_post_comments where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'`);
await db.query(`insert into public.user_progress(user_id,chapter_id,percent) values ($1,$2,25)`,[uid2,chapter]);
await expectNoRows('reader direct streak mutation', `update public.user_streaks set current_streak=99 where user_id='${uid2}' returning user_id`);
await db.exec('reset role');
const streakAfterActivity = await db.query('select current_streak,longest_streak,last_activity_at::text as last_activity_at from public.user_streaks where user_id=$1',[uid2]);
assert.equal(streakAfterActivity.rows[0].current_streak,1);
assert.equal(streakAfterActivity.rows[0].longest_streak,1);
assert.equal(String(streakAfterActivity.rows[0].last_activity_at),new Date().toISOString().slice(0,10));
console.log('PASS: normal-client reactions/replies/feed counters and server-maintained streak');

// The 25 XP bonus is server-only, tied to today's verified activity, and
// idempotent by a deterministic daily reference.
await db.exec(`select set_config('request.jwt.claim.sub','${uid2}',false); set role authenticated`);
await expectDenied('client arbitrary daily streak bonus', `select public.award_daily_streak_bonus('${uid2}')`);
await db.exec('reset role; set role service_role');
const firstBonus = await db.query('select private.award_daily_streak_bonus($1) as awarded',[uid2]);
const secondBonus = await db.query('select private.award_daily_streak_bonus($1) as awarded',[uid2]);
assert.equal(firstBonus.rows[0].awarded,true);
assert.equal(secondBonus.rows[0].awarded,true);
const bonusRows = await db.query("select amount,ref_id from public.xp_events where user_id=$1 and source='streak_bonus'",[uid2]);
assert.equal(bonusRows.rows.length,1);
assert.equal(bonusRows.rows[0].amount,25);
const expectedRef = await db.query("select md5($1 || ':' || current_date::text)::uuid as ref",[uid2]);
assert.equal(String(bonusRows.rows[0].ref_id),String(expectedRef.rows[0].ref));
console.log('PASS: daily streak25 is activity-gated, server-only, date-referenced, and idempotent');
console.log('ALL SECURITY SMOKE ASSERTIONS PASSED');
await db.close();
