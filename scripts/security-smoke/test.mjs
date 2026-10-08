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
create type public.journal_visibility as enum ('private','friends','club','public');
create type public.feed_post_kind as enum ('quote','note');
create type public.feed_visibility as enum ('public','followers','club','private');
create table public.profiles(id uuid primary key,username text,display_name text,avatar_url text,bio text,level integer,created_at timestamptz default now(),role text,whatsapp text,lgpd_consent boolean,lgpd_consent_at timestamptz,onboarding_done boolean,updated_at timestamptz default now());
create table public.comments(id uuid primary key,chapter_id uuid not null,user_id uuid not null,parent_id uuid,content text not null,is_spoiler boolean not null default false,min_percent numeric default 0,likes_count integer not null default 0,replies_count integer not null default 0,edited_at timestamptz,deleted_at timestamptz,created_at timestamptz not null default now());
create table public.user_progress(user_id uuid,chapter_id uuid,percent numeric default 0,primary key(user_id,chapter_id));
create table public.feed_posts(id uuid primary key,author_id uuid not null,kind public.feed_post_kind,visibility public.feed_visibility not null,club_id uuid,book_id uuid,chapter_id uuid,season_id uuid,body text,quote_text text,link_url text,cover_url text,metadata jsonb not null default '{}',is_spoiler boolean not null default false,min_percent numeric not null default 0,likes_count integer not null default 0,comments_count integer not null default 0,shares_count integer not null default 0,deleted_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.follows(follower_id uuid,followed_id uuid,status text);
create table public.user_clubs(id uuid primary key,owner_id uuid not null,is_private boolean not null default false,current_book_id uuid,current_season_id uuid);
create table public.user_club_members(club_id uuid,user_id uuid,role text not null default 'member',primary key(club_id,user_id));
create table public.reading_lists(id uuid primary key,owner_id uuid not null,is_collaborative boolean not null default false,visibility text not null default 'private');
create table public.reading_list_collaborators(list_id uuid,user_id uuid,can_edit boolean not null default true);
create table public.reading_list_items(id uuid primary key,list_id uuid not null,added_by uuid,kind text,position integer default 0);
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
create table public.chapter_extra_content(storage_path text,is_public boolean,created_by uuid);
create table storage.buckets(id text primary key,public boolean not null);
create table storage.objects(bucket_id text,name text);
create function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select p.role='admin' from public.profiles p where p.id=(select auth.uid())),false) $$;

grant all on public.profiles,public.comments,public.feed_posts,public.user_progress,public.quiz_questions,public.quiz_attempts,public.quiz_answers,public.reading_lists,public.reading_list_items,public.reading_list_collaborators,public.user_clubs,public.user_club_members,public.feed_post_media,public.feed_post_comments,public.feed_post_likes,public.book_mood_votes,public.reading_journal_entries,public.chapter_prompt_responses,public.chapter_prompts,public.chapters,public.seasons,public.chapter_extra_content,storage.objects,storage.buckets to anon,authenticated;
insert into storage.buckets values ('feed-media',true),('chapter-extras',false),('manuscripts',false);
`;

await db.exec(bootstrap);
for (const table of ['profiles','comments','feed_posts','quiz_questions','quiz_attempts','quiz_answers','reading_list_items','reading_list_collaborators','user_club_members','feed_post_media','feed_post_comments','feed_post_likes','book_mood_votes','reading_journal_entries','chapter_prompt_responses']) {
  await db.exec(`alter table public.${table} enable row level security;`);
}
for (const filename of [
  '20261008225152_harden_core_authorization.sql',
  '20261008225535_prevent_client_privilege_escalation.sql',
  '20261008225856_encapsulate_profile_consent_privilege.sql',
]) {
  await db.exec(await readFile(resolve(repoRoot, 'supabase/migrations', filename), 'utf8'));
}
console.log('MIGRATIONS APPLY OK (PostgreSQL WASM)');
const publicProfileDefiners=await db.query(`select count(*)::int as total from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('get_my_profile_private','set_my_lgpd_consent') and p.prosecdef`);
assert.equal(publicProfileDefiners.rows[0]?.total,0,'profile RPCs exposed in public must be SECURITY INVOKER');

const uid1='11111111-1111-4111-8111-111111111111';
const uid2='22222222-2222-4222-8222-222222222222';
const chapter='33333333-3333-4333-8333-333333333333';
const publicPost='44444444-4444-4444-8444-444444444444';
const list='55555555-5555-4555-8555-555555555555';
const privateClub='66666666-6666-4666-8666-666666666666';
const publicClub='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const privatePost='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
await db.query(`insert into public.profiles(id,username,display_name,role,whatsapp,lgpd_consent,level) values ($1,'owner','Owner','admin','secret',true,1),($2,'other','Other','reader','private',false,1)`,[uid1,uid2]);
await db.query(`insert into public.comments(id,chapter_id,user_id,content,is_spoiler,min_percent) values ('77777777-7777-4777-8777-777777777777',$1,$2,'secret spoiler',true,50)`,[chapter,uid1]);
await db.query(`insert into public.feed_posts(id,author_id,kind,visibility,chapter_id,body,quote_text,metadata,is_spoiler,min_percent) values ($1,$2,'quote','public',$3,'secret post','secret quote','{"secret":true}',true,50),($4,$5,'note','private',$3,'private post',null,'{"private":true}',false,0)`,[publicPost,uid1,chapter,privatePost,uid2]);
await db.query(`insert into public.quiz_questions values ('88888888-8888-4888-8888-888888888888',$1,1,'Q','["a","b"]',1,'answer')`,[chapter]);
await db.query(`insert into public.reading_lists values ($1,$2,false,'private')`,[list,uid2]);
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
await expectDenied('client-edited profile level',`update public.profiles set level=99 where id='${uid1}'`);
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
console.log('ALL SECURITY SMOKE ASSERTIONS PASSED');
await db.close();
