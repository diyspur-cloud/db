import { readFile } from "node:fs/promises";
import { PGlite } from "@electric-sql/pglite";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../../", import.meta.url)).replace(/\/$/, "");
const db = new PGlite("memory://diyspur-final-fixes");
await db.waitReady;

const q = async (sql, params = []) => (await db.query(sql, params)).rows;
const assert = (condition, message) => {
  if (!condition) throw new Error(`ASSERTION FAILED: ${message}`);
};

await db.exec(`
  create role anon;
  create role authenticated;
  create role service_role;
  create schema auth;
  create schema private;
  create function public.test_uuid() returns uuid language sql volatile as $$
    select md5(random()::text || clock_timestamp()::text)::uuid
  $$;
  create type public.shelf_status as enum ('want_to_read','reading','read','dnf');
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  $$;
  create table public.profiles (id uuid primary key);
  create table public.books (id uuid primary key, title text not null);
  create table public.seasons (id uuid primary key, title text not null, book_id uuid not null);
  create table public.chapters (id uuid primary key, season_id uuid not null);
  create table public.user_clubs (
    id uuid primary key, owner_id uuid not null, name text not null,
    is_private boolean not null default false, current_book_id uuid,
    current_season_id uuid, current_started_at timestamptz,
    current_ends_at timestamptz
  );
  create table public.user_club_members (club_id uuid not null, user_id uuid not null,
    primary key (club_id, user_id));
  create table public.user_progress (
    id uuid primary key, user_id uuid not null, chapter_id uuid,
    status public.shelf_status not null, percent numeric not null default 0
  );
  create table public.newsletter_issues (
    id uuid primary key, sent_at timestamptz
  );
  create table private.newsletter_dispatch_runs (
    issue_id uuid not null references public.newsletter_issues(id) on delete cascade,
    audience_key text not null,
    started_at timestamptz not null default statement_timestamp(),
    completed_at timestamptz,
    primary key (issue_id, audience_key)
  );
  grant usage on schema public, private to service_role;
  grant select, insert, update, delete on all tables in schema public, private to service_role;
`);

for (const file of [
  "supabase/migrations/20261009034508_fix_atomic_rate_limits_and_club_season.sql",
  "supabase/migrations/20261009034511_fix_newsletter_claim_ownership.sql",
]) {
  const sql = (await readFile(`${root}/${file}`, "utf8"))
    .replaceAll("gen_random_uuid()", "public.test_uuid()");
  await db.exec(sql);
}

const user = "10000000-0000-0000-0000-000000000001";
const book = "20000000-0000-0000-0000-000000000001";
const seasonCurrent = "30000000-0000-0000-0000-000000000001";
const seasonOld = "30000000-0000-0000-0000-000000000002";
const chapterCurrent = "40000000-0000-0000-0000-000000000001";
const chapterOld = "40000000-0000-0000-0000-000000000002";
const club = "50000000-0000-0000-0000-000000000001";
const issue1 = "60000000-0000-0000-0000-000000000001";
const issue2 = "60000000-0000-0000-0000-000000000002";
const issue3 = "60000000-0000-0000-0000-000000000003";

await db.exec(`
  insert into public.profiles values ('${user}');
  insert into public.books values ('${book}', 'Book');
  insert into public.seasons values
    ('${seasonCurrent}', 'Current', '${book}'),
    ('${seasonOld}', 'Old', '${book}');
  insert into public.chapters values
    ('${chapterCurrent}', '${seasonCurrent}'),
    ('${chapterOld}', '${seasonOld}');
  insert into public.user_clubs (id, owner_id, name, current_book_id, current_season_id)
    values ('${club}', '${user}', 'Club', '${book}', '${seasonCurrent}');
  insert into public.user_club_members values ('${club}', '${user}');
  insert into public.user_progress (id, user_id, chapter_id, status, percent) values
    ('70000000-0000-0000-0000-000000000001', '${user}', '${chapterCurrent}', 'read', 100),
    ('70000000-0000-0000-0000-000000000002', '${user}', '${chapterOld}', 'reading', 25);
  insert into public.newsletter_issues (id) values
    ('${issue1}'), ('${issue2}'), ('${issue3}');
  set role service_role;
`);

const firstLimit = await q(
  `select public.take_rate_limit($1, 'test', 1, 3600) as allowed`,
  [user],
);
const secondLimit = await q(
  `select public.take_rate_limit($1, 'test', 1, 3600) as allowed`,
  [user],
);
assert(firstLimit[0].allowed === true, "first atomic limit attempt is allowed");
assert(secondLimit[0].allowed === false, "second atomic limit attempt is rejected");

const panel = await q(`select chapters_read, chapters_in_progress, finished_count,
  reading_count, not_started_count, current_season_id, current_season_title
  from public.v_club_progress_panel where club_id = $1`, [club]);
assert(panel.length === 1, "club panel returns one row");
assert(panel[0].chapters_read === 1, "panel counts current-season read only");
assert(panel[0].chapters_in_progress === 0, "panel excludes old-season reading");
assert(panel[0].finished_count === 1 && panel[0].reading_count === 0,
  "aggregate aliases match legacy season population");
assert(panel[0].current_season_id === seasonCurrent && panel[0].current_season_title === "Current",
  "current season aliases are coherent");
assert((await q(`select to_regclass('public.clubs') as clubs`))[0].clubs === null,
  "migration does not create public.clubs");

const token1 = (await q(
  `select public.claim_newsletter_dispatch_token($1, 'audience') as token`,
  [issue1],
))[0].token;
assert(typeof token1 === "string", "first newsletter claim returns token");
const blocked = (await q(
  `select public.claim_newsletter_dispatch_token($1, 'audience') as token`,
  [issue1],
))[0].token;
assert(blocked === null, "second active newsletter claim is blocked");
await q(`select public.finish_newsletter_dispatch_owned($1, 'audience', true, $2)`, [issue1, token1]);
const completed = (await q(
  `select completed_at is not null as done from private.newsletter_dispatch_runs where issue_id = $1`,
  [issue1],
))[0];
assert(completed.done === true, "owner can finish newsletter successfully");
await q(`select public.finish_newsletter_dispatch($1, 'audience', false)`, [issue1]);
const stillCompleted = (await q(
  `select completed_at is not null as done from private.newsletter_dispatch_runs where issue_id = $1`,
  [issue1],
))[0];
assert(stillCompleted.done === true, "legacy false cannot overwrite completed claim");

const oldToken = (await q(
  `select public.claim_newsletter_dispatch_token($1, 'audience') as token`,
  [issue2],
))[0].token;
await q(`update private.newsletter_dispatch_runs
  set started_at = statement_timestamp() - interval '25 hours' where issue_id = $1`, [issue2]);
const recoveredToken = (await q(
  `select public.claim_newsletter_dispatch_token($1, 'audience') as token`,
  [issue2],
))[0].token;
assert(recoveredToken && recoveredToken !== oldToken, "expired claim is recovered with a new token");
await q(`select public.finish_newsletter_dispatch_owned($1, 'audience', false, $2)`, [issue2, oldToken]);
const protectedRecovery = (await q(
  `select claim_token = $2 as owns, completed_at is null as open from private.newsletter_dispatch_runs where issue_id = $1`,
  [issue2, recoveredToken],
))[0];
assert(protectedRecovery.owns && protectedRecovery.open, "stale false cannot delete recovered claim");
await q(`select public.finish_newsletter_dispatch_owned($1, 'audience', true, $2)`, [issue2, recoveredToken]);

const token3 = (await q(
  `select public.claim_newsletter_dispatch_token($1, 'audience') as token`,
  [issue3],
))[0].token;
await q(`select public.finish_newsletter_dispatch_owned($1, 'audience', false, $2)`, [issue3, token3]);
assert((await q(`select count(*)::int as n from private.newsletter_dispatch_runs where issue_id = $1`, [issue3]))[0].n === 0,
  "owner failure releases only its own claim");

console.log("PASS: final-fixes PGlite migration and concurrency assertions");
await db.close();
