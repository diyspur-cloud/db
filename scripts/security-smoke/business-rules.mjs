import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { PGlite } from "@electric-sql/pglite";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const db = new PGlite();
const bootstrap = `
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;
CREATE SCHEMA auth;
CREATE SCHEMA private;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
CREATE TYPE public.xp_source AS ENUM ('join_meeting','finish_chapter','comment','quiz_answer','finish_book','streak_bonus');
CREATE TYPE public.cycle_status AS ENUM ('planned','enrolling','active','finished');
CREATE TYPE public.shelf_status AS ENUM ('want_to_read','reading','read','dnf');
CREATE TYPE public.poll_status AS ENUM ('open','closed');
CREATE TYPE public.meeting_status AS ENUM ('scheduled','live','done','cancelled');
CREATE TYPE public.meeting_kind AS ENUM ('online','in_person');
CREATE TYPE public.notification_kind AS ENUM ('new_chapter','meeting_reminder','reply','mention','badge_unlocked','poll_open');
CREATE TYPE public.payment_provider AS ENUM ('stripe','mercado_pago','pagseguro','manual');
CREATE TYPE public.subscription_status AS ENUM ('trialing','active','past_due','canceled','paused','incomplete');
CREATE TYPE public.mood_kind AS ENUM ('adventurous','emotional','dark','funny','hopeful','informative','inspiring','lighthearted','mysterious','reflective','sad','tense','challenging');
CREATE TYPE public.pace_kind AS ENUM ('slow','medium','fast');
CREATE TYPE public.journal_visibility AS ENUM ('private','friends','club','public');
CREATE TABLE public.profiles (id uuid PRIMARY KEY, role text NOT NULL DEFAULT 'reader');
CREATE TABLE public.books (id uuid PRIMARY KEY, title text NOT NULL);
CREATE TABLE public.seasons (id uuid PRIMARY KEY, number integer NOT NULL, title text NOT NULL, slug text NOT NULL, book_id uuid NOT NULL, status public.cycle_status NOT NULL, starts_at date, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.chapters (id uuid PRIMARY KEY, season_id uuid NOT NULL, number integer NOT NULL, title text NOT NULL, published_at timestamptz, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.user_progress (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL, chapter_id uuid NOT NULL, status public.shelf_status NOT NULL DEFAULT 'want_to_read', percent numeric NOT NULL DEFAULT 0, finished_at timestamptz, started_at timestamptz, updated_at timestamptz NOT NULL DEFAULT now(), UNIQUE(user_id,chapter_id));
CREATE TABLE public.xp_events (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL, source public.xp_source NOT NULL, amount integer NOT NULL, ref_id uuid, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.user_xp (user_id uuid PRIMARY KEY, total_xp integer NOT NULL DEFAULT 0, season_xp integer NOT NULL DEFAULT 0, season_id uuid, updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.user_quiz_averages (user_id uuid PRIMARY KEY, attempts_total integer NOT NULL DEFAULT 0, score_sum integer NOT NULL DEFAULT 0, total_sum integer NOT NULL DEFAULT 0, average_percent numeric(5,2) NOT NULL DEFAULT 0, best_percent numeric(5,2) NOT NULL DEFAULT 0, last_attempt_at timestamptz, updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.chapter_quiz_averages (chapter_id uuid PRIMARY KEY, attempts_total integer NOT NULL DEFAULT 0, average_percent numeric(5,2) NOT NULL DEFAULT 0, perfect_count integer NOT NULL DEFAULT 0, updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.quiz_questions (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), chapter_id uuid NOT NULL, position integer NOT NULL, question text NOT NULL, options jsonb NOT NULL, correct_idx integer NOT NULL, explanation text, UNIQUE(chapter_id,position));
CREATE TABLE public.quiz_attempts (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL, chapter_id uuid NOT NULL, score integer NOT NULL, total integer NOT NULL, duration_ms integer, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.quiz_answers (attempt_id uuid NOT NULL, question_id uuid NOT NULL, chosen_idx integer NOT NULL, is_correct boolean NOT NULL, PRIMARY KEY(attempt_id,question_id));
CREATE TABLE public.reading_goals (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL, year integer NOT NULL, target_books integer, target_pages integer, target_minutes integer, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(user_id,year));
CREATE TABLE public.reading_goal_progress (goal_id uuid PRIMARY KEY REFERENCES public.reading_goals(id) ON DELETE CASCADE, books_done integer NOT NULL DEFAULT 0, pages_done integer NOT NULL DEFAULT 0, minutes_done integer NOT NULL DEFAULT 0, updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.reading_journal_entries (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL, book_id uuid NOT NULL, chapter_id uuid, season_id uuid, entry_date date NOT NULL, page_from integer, page_to integer, percent_at numeric, minutes_read integer, mood_at_time public.mood_kind, title text, body text NOT NULL, visibility public.journal_visibility NOT NULL DEFAULT 'private', is_spoiler boolean NOT NULL DEFAULT false, min_percent numeric NOT NULL DEFAULT 0, likes_count integer NOT NULL DEFAULT 0, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.book_polls (id uuid PRIMARY KEY, season_id uuid, title text NOT NULL, status public.poll_status NOT NULL, opens_at timestamptz NOT NULL, closes_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.book_poll_options (id uuid PRIMARY KEY, poll_id uuid NOT NULL, book_id uuid NOT NULL, proposal text, votes_count integer NOT NULL DEFAULT 0);
CREATE TABLE public.book_poll_votes (poll_id uuid NOT NULL, option_id uuid NOT NULL, user_id uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(poll_id,user_id));
CREATE TABLE public.meetings (id uuid PRIMARY KEY, chapter_id uuid NOT NULL, title text NOT NULL, kind public.meeting_kind NOT NULL, status public.meeting_status NOT NULL, scheduled_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.meeting_rsvps (meeting_id uuid NOT NULL, user_id uuid NOT NULL, attending boolean NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(meeting_id,user_id));
CREATE TABLE public.notifications (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL, kind public.notification_kind NOT NULL, payload jsonb NOT NULL, read_at timestamptz, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.newsletter_issues (id uuid PRIMARY KEY, slug text NOT NULL, subject text NOT NULL, body_markdown text NOT NULL, body_html text, sent_at timestamptz, audience_filter jsonb NOT NULL DEFAULT '{}', created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.membership_plans (id uuid PRIMARY KEY, code text NOT NULL, tier text NOT NULL, name text NOT NULL, price_cents integer NOT NULL, currency text NOT NULL, interval text NOT NULL, stripe_price_id text, perks jsonb NOT NULL DEFAULT '{}', is_active boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.user_subscriptions (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL, plan_id uuid NOT NULL, status public.subscription_status NOT NULL, provider public.payment_provider NOT NULL, provider_customer_id text, provider_subscription_id text UNIQUE, current_period_start timestamptz, current_period_end timestamptz, cancel_at_period_end boolean NOT NULL DEFAULT false, metadata jsonb NOT NULL DEFAULT '{}', created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.payment_events (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), provider public.payment_provider NOT NULL, event_id text NOT NULL, event_type text NOT NULL, user_id uuid, payload jsonb NOT NULL, processed_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(provider,event_id));
CREATE TABLE public.book_mood_votes (book_id uuid NOT NULL, user_id uuid NOT NULL, moods public.mood_kind[] NOT NULL, pace public.pace_kind, plot_vs_character numeric, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(book_id,user_id));
CREATE TABLE public.user_match_cache (user_id uuid NOT NULL, matched_id uuid NOT NULL, similarity numeric NOT NULL, shared_books integer NOT NULL, shared_moods public.mood_kind[], computed_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(user_id,matched_id));
CREATE FUNCTION public.refresh_user_quiz_averages() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$ BEGIN RETURN NULL; END $$;
CREATE FUNCTION public.refresh_chapter_quiz_averages() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$ BEGIN RETURN NULL; END $$;
CREATE FUNCTION public.refresh_reading_goal_progress() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$ BEGIN RETURN NULL; END $$;
CREATE FUNCTION public.bump_journal_likes() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$ BEGIN RETURN NULL; END $$;
CREATE TRIGGER trg_refresh_user_quiz_averages AFTER INSERT ON public.quiz_attempts FOR EACH ROW EXECUTE FUNCTION public.refresh_user_quiz_averages();
CREATE TRIGGER trg_refresh_chapter_quiz_averages AFTER INSERT ON public.quiz_attempts FOR EACH ROW EXECUTE FUNCTION public.refresh_chapter_quiz_averages();
CREATE TRIGGER trg_goal_progress_refresh AFTER INSERT ON public.user_progress FOR EACH ROW EXECUTE FUNCTION public.refresh_reading_goal_progress();
CREATE TRIGGER trg_goal_progress_refresh_journal AFTER INSERT ON public.reading_journal_entries FOR EACH ROW EXECUTE FUNCTION public.refresh_reading_goal_progress();
CREATE TRIGGER trg_goal_progress_refresh_goal AFTER INSERT ON public.reading_goals FOR EACH ROW EXECUTE FUNCTION public.refresh_reading_goal_progress();
`;

await db.exec(bootstrap);
const migration = await readFile(
  resolve(repoRoot, "supabase/migrations/20261009020600_20261009014533_implement_audit_followups.sql"),
  "utf8",
);
await db.exec(migration);
console.log("PASS: follow-up migration applies to PostgreSQL WASM");

const publicRpcNames = [
  "award_xp", "cast_book_poll_vote", "consume_quiz_rate_limit",
  "record_quiz_attempt", "deliver_meeting_reminder", "claim_newsletter_dispatch",
  "finish_newsletter_dispatch", "link_stripe_customer",
  "apply_stripe_subscription_event", "get_reader_overlaps",
];
const publicDefiners = await db.query(
  `SELECT proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname = ANY($1) AND p.prosecdef`,
  [publicRpcNames],
);
assert.deepEqual(publicDefiners.rows, [], "public RPC endpoints must be SECURITY INVOKER");
const hiddenTriggers = await db.query(
  `SELECT count(*)::int AS total FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
   JOIN pg_namespace n ON n.oid=p.pronamespace WHERE NOT t.tgisinternal
   AND n.nspname='private'`,
);
assert.ok(hiddenTriggers.rows[0].total >= 6, "business trigger handlers live in private schema");
assert.equal(
  (await db.query("SELECT has_function_privilege('anon','public.award_xp(uuid,public.xp_source,integer,uuid)','EXECUTE') AS allowed")).rows[0].allowed,
  false,
);
console.log("PASS: privileged RPCs are invoker-only and not executable by anon");

const ids = {
  user1: "11111111-1111-4111-8111-111111111111",
  user2: "22222222-2222-4222-8222-222222222222",
  book1: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  book2: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
  season1: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
  season2: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
  season3: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
  chapter1: "10000000-0000-4000-8000-000000000001",
  chapter2: "10000000-0000-4000-8000-000000000002",
  chapter3: "10000000-0000-4000-8000-000000000003",
  poll: "20000000-0000-4000-8000-000000000001",
  option1: "20000000-0000-4000-8000-000000000002",
  option2: "20000000-0000-4000-8000-000000000003",
  question: "30000000-0000-4000-8000-000000000001",
  meeting: "40000000-0000-4000-8000-000000000001",
  issue: "50000000-0000-4000-8000-000000000001",
  plan: "60000000-0000-4000-8000-000000000001",
  request: "70000000-0000-4000-8000-000000000001",
};
await db.query("INSERT INTO public.profiles(id) VALUES ($1),($2)", [ids.user1, ids.user2]);
await db.query("INSERT INTO public.books(id,title) VALUES ($1,'Across seasons'),($2,'Second book')", [ids.book1, ids.book2]);
await db.query(
  `INSERT INTO public.seasons(id,number,title,slug,book_id,status,starts_at)
   VALUES ($1,1,'First','first',$4,'active',CURRENT_DATE-10),
          ($2,2,'Second','second',$4,'planned',CURRENT_DATE),
          ($3,1,'Third','third',$5,'planned',CURRENT_DATE)`,
  [ids.season1, ids.season2, ids.season3, ids.book1, ids.book2],
);
await db.query(
  `INSERT INTO public.chapters(id,season_id,number,title,published_at)
   VALUES ($1,$4,1,'One',now()),($2,$5,1,'Two',now()),($3,$6,1,'Other',now())`,
  [ids.chapter1, ids.chapter2, ids.chapter3, ids.season1, ids.season2, ids.season3],
);

// Idempotent XP, seasonal bucket rollover, and unique source/reference key.
await db.query("SELECT public.award_xp($1,'finish_chapter'::public.xp_source,10,$2)", [ids.user1, ids.chapter1]);
await db.query("SELECT public.award_xp($1,'finish_chapter'::public.xp_source,10,$2)", [ids.user1, ids.chapter1]);
let xp = await db.query("SELECT total_xp,season_xp,season_id FROM public.user_xp WHERE user_id=$1", [ids.user1]);
assert.equal(xp.rows[0].total_xp, 10);
assert.equal(xp.rows[0].season_xp, 10);
assert.equal((await db.query("SELECT count(*)::int AS n FROM public.xp_events WHERE user_id=$1", [ids.user1])).rows[0].n, 1);
await db.query("UPDATE public.seasons SET status='finished' WHERE id=$1", [ids.season1]);
await db.query("UPDATE public.seasons SET status='active' WHERE id=$1", [ids.season2]);
await db.query("SELECT public.award_xp($1,'comment'::public.xp_source,5,$2)", [ids.user1, ids.book1]);
xp = await db.query("SELECT total_xp,season_xp,season_id FROM public.user_xp WHERE user_id=$1", [ids.user1]);
assert.equal(xp.rows[0].total_xp, 15);
assert.equal(xp.rows[0].season_xp, 5, "new active season resets only the seasonal subtotal");
assert.equal(xp.rows[0].season_id, ids.season2);
console.log("PASS: XP is idempotent and rolls into the active season");

// Complete books are distinct catalog titles across seasons, not chapter rows.
const year = new Date().getUTCFullYear();
await db.query("INSERT INTO public.reading_goals(id,user_id,year) VALUES (gen_random_uuid(),$1,$2)", [ids.user1, year]);
await db.query(
  `INSERT INTO public.user_progress(user_id,chapter_id,status,percent)
   VALUES ($1,$2,'read',100),($1,$3,'read',100),($1,$4,'reading',30),($5,$2,'read',100),($5,$3,'read',100)`,
  [ids.user1, ids.chapter1, ids.chapter2, ids.chapter3, ids.user2],
);
let goal = await db.query("SELECT books_done,pages_done,minutes_done FROM public.reading_goal_progress rgp JOIN public.reading_goals rg ON rg.id=rgp.goal_id WHERE rg.user_id=$1 AND rg.year=$2", [ids.user1, year]);
assert.equal(goal.rows[0].books_done, 1, "two completed chapters across two seasons count as one book");
const overview = await db.query("SELECT books_read,books_reading FROM public.v_user_reading_overview WHERE user_id=$1", [ids.user1]);
assert.equal(overview.rows[0].books_read, 1);
assert.equal(overview.rows[0].books_reading, 1);
const finishedAt = await db.query("SELECT finished_at FROM public.user_progress WHERE user_id=$1 AND chapter_id=$2", [ids.user1, ids.chapter1]);
assert.ok(finishedAt.rows[0].finished_at, "new read status receives server timestamp");
await db.query("UPDATE public.user_progress SET status='read',percent=100 WHERE user_id=$1 AND chapter_id=$2", [ids.user1, ids.chapter3]);
goal = await db.query("SELECT books_done FROM public.reading_goal_progress rgp JOIN public.reading_goals rg ON rg.id=rgp.goal_id WHERE rg.user_id=$1 AND rg.year=$2", [ids.user1, year]);
assert.equal(goal.rows[0].books_done, 2);
await db.query("UPDATE public.user_progress SET status='reading',percent=40 WHERE user_id=$1 AND chapter_id=$2", [ids.user1, ids.chapter3]);
const reopened = await db.query("SELECT finished_at FROM public.user_progress WHERE user_id=$1 AND chapter_id=$2", [ids.user1, ids.chapter3]);
assert.equal(reopened.rows[0].finished_at, null, "reopening a chapter clears its completion timestamp");
console.log("PASS: annual goals and overview count completed books, not chapters");

// Journal aggregation and idempotent like counters.
const entry = "80000000-0000-4000-8000-000000000001";
await db.query(
  `INSERT INTO public.reading_journal_entries(id,user_id,book_id,entry_date,page_from,page_to,minutes_read,body)
   VALUES ($1,$2,$3,CURRENT_DATE,10,30,45,'read')`,
  [entry, ids.user1, ids.book1],
);
const liked = "80000000-0000-4000-8000-000000000002";
await db.query("INSERT INTO public.reading_journal_likes(entry_id,user_id) VALUES ($1,$2)", [entry, ids.user2]);
assert.equal((await db.query("SELECT likes_count FROM public.reading_journal_entries WHERE id=$1", [entry])).rows[0].likes_count, 1);
await db.query("DELETE FROM public.reading_journal_likes WHERE entry_id=$1 AND user_id=$2", [entry, ids.user2]);
await db.query("UPDATE public.reading_journal_entries SET likes_count=0 WHERE id=$1", [entry]);
await db.query("DELETE FROM public.reading_journal_likes WHERE entry_id=$1 AND user_id=$2", [entry, ids.user2]);
assert.equal((await db.query("SELECT likes_count FROM public.reading_journal_entries WHERE id=$1", [entry])).rows[0].likes_count, 0);
assert.equal((await db.query("SELECT pages_done,minutes_done FROM public.reading_goal_progress rgp JOIN public.reading_goals rg ON rg.id=rgp.goal_id WHERE rg.user_id=$1 AND rg.year=$2", [ids.user1, year])).rows[0].pages_done, 20);
console.log("PASS: journal likes stay synchronized and goal sums use journal data");

// Quiz averages react to inserts, updates, deletes, and idempotency keys.
await db.query("INSERT INTO public.quiz_questions(id,chapter_id,position,question,options,correct_idx) VALUES ($1,$2,1,'Q','[\"a\",\"b\"]'::jsonb,1)", [ids.question, ids.chapter1]);
const attempt1 = "90000000-0000-4000-8000-000000000001";
const attempt2 = "90000000-0000-4000-8000-000000000002";
await db.query("INSERT INTO public.quiz_attempts(id,user_id,chapter_id,score,total) VALUES ($1,$2,$3,2,2),($4,$2,$3,1,2)", [attempt1, ids.user1, ids.chapter1, attempt2]);
let average = await db.query("SELECT attempts_total,score_sum,total_sum,average_percent,best_percent FROM public.user_quiz_averages WHERE user_id=$1", [ids.user1]);
assert.equal(average.rows[0].attempts_total, 2);
assert.equal(Number(average.rows[0].average_percent), 75);
assert.equal(Number(average.rows[0].best_percent), 100);
await db.query("UPDATE public.quiz_attempts SET user_id=$1,chapter_id=$2 WHERE id=$3", [ids.user2, ids.chapter2, attempt2]);
assert.equal((await db.query("SELECT attempts_total FROM public.user_quiz_averages WHERE user_id=$1", [ids.user1])).rows[0].attempts_total, 1);
assert.equal((await db.query("SELECT attempts_total FROM public.chapter_quiz_averages WHERE chapter_id=$1", [ids.chapter2])).rows[0].attempts_total, 1);
await db.query("DELETE FROM public.quiz_attempts WHERE id=$1", [attempt1]);
assert.equal((await db.query("SELECT count(*)::int AS n FROM public.user_quiz_averages WHERE user_id=$1", [ids.user1])).rows[0].n, 0);
let rateAllowed = true;
for (let i=0; i<11; i++) {
  rateAllowed = (await db.query("SELECT public.consume_quiz_rate_limit($1,$2) AS allowed", [ids.user1, ids.chapter1])).rows[0].allowed;
  assert.equal(rateAllowed, i < 10, `attempt ${i+1} rate limit`);
}
const answerPayload = [{question_id:ids.question,chosen_idx:1,is_correct:true}];
let recorded = await db.query("SELECT * FROM public.record_quiz_attempt($1,$2,$3,1,1,$4::jsonb)", [ids.user1, ids.chapter1, ids.request, JSON.stringify(answerPayload)]);
const recordedId = recorded.rows[0].attempt_id;
assert.equal(recorded.rows[0].duplicate, false);
recorded = await db.query("SELECT * FROM public.record_quiz_attempt($1,$2,$3,0,1,$4::jsonb)", [ids.user1, ids.chapter1, ids.request, JSON.stringify(answerPayload)]);
assert.equal(recorded.rows[0].duplicate, true);
assert.equal(recorded.rows[0].attempt_id, recordedId);
assert.equal((await db.query("SELECT count(*)::int AS n FROM public.quiz_answers WHERE attempt_id=$1", [recordedId])).rows[0].n, 1);
console.log("PASS: quiz averages, atomic rate limit and attempt idempotency");

// Poll validation/atomic option counters.
await db.query("INSERT INTO public.book_polls(id,title,status,opens_at,closes_at) VALUES ($1,'Next book','open',now()-interval '1 hour',now()+interval '1 hour')", [ids.poll]);
await db.query("INSERT INTO public.book_poll_options(id,poll_id,book_id) VALUES ($1,$3,$4),($2,$3,$5)", [ids.option1, ids.option2, ids.poll, ids.book1, ids.book2]);
await db.query("SELECT public.cast_book_poll_vote($1,$2,$3)", [ids.user1, ids.poll, ids.option1]);
await db.query("SELECT public.cast_book_poll_vote($1,$2,$3)", [ids.user1, ids.poll, ids.option1]);
assert.equal((await db.query("SELECT votes_count FROM public.book_poll_options WHERE id=$1", [ids.option1])).rows[0].votes_count, 1);
await db.query("SELECT public.cast_book_poll_vote($1,$2,$3)", [ids.user1, ids.poll, ids.option2]);
assert.equal((await db.query("SELECT votes_count FROM public.book_poll_options WHERE id=$1", [ids.option1])).rows[0].votes_count, 0);
assert.equal((await db.query("SELECT votes_count FROM public.book_poll_options WHERE id=$1", [ids.option2])).rows[0].votes_count, 1);
await assert.rejects(db.query("SELECT public.cast_book_poll_vote($1,$2,$3)", [ids.user2, ids.poll, ids.book2]), /option does not belong to poll/);
await db.query("UPDATE public.book_polls SET status='closed' WHERE id=$1", [ids.poll]);
await assert.rejects(db.query("SELECT public.cast_book_poll_vote($1,$2,$3)", [ids.user2, ids.poll, ids.option1]), /poll is not open/);
console.log("PASS: votes are time-gated, option-scoped, idempotent and atomically counted");

// Scheduled reminders use a unique claim and only attendees receive one notification.
await db.query("INSERT INTO public.meetings(id,chapter_id,title,kind,status,scheduled_at) VALUES ($1,$2,'Upcoming','online','scheduled',now()+interval '23 hours')", [ids.meeting, ids.chapter1]);
await db.query("INSERT INTO public.meeting_rsvps(meeting_id,user_id,attending) VALUES ($1,$2,true)", [ids.meeting, ids.user1]);
assert.equal((await db.query("SELECT public.deliver_meeting_reminder($1,$2,'48h') AS sent", [ids.user1, ids.meeting])).rows[0].sent, true);
assert.equal((await db.query("SELECT public.deliver_meeting_reminder($1,$2,'48h') AS sent", [ids.user1, ids.meeting])).rows[0].sent, false);
assert.equal((await db.query("SELECT count(*)::int AS n FROM public.notifications WHERE user_id=$1", [ids.user1])).rows[0].n, 1);
console.log("PASS: meeting reminders are deduplicated by reader/meeting/window");

// Newsletter leasing can retry failed dispatches, then locks successful dispatches.
await db.query("INSERT INTO public.newsletter_issues(id,slug,subject,body_markdown,audience_filter) VALUES ($1,'issue','Test','Body','{}')", [ids.issue]);
assert.equal((await db.query("SELECT public.claim_newsletter_dispatch($1,'all') AS claimed", [ids.issue])).rows[0].claimed, true);
assert.equal((await db.query("SELECT public.claim_newsletter_dispatch($1,'all') AS claimed", [ids.issue])).rows[0].claimed, false);
await db.query("SELECT public.finish_newsletter_dispatch($1,'all',false)", [ids.issue]);
await db.query("UPDATE private.newsletter_dispatch_runs SET started_at=now()-interval '25 hours' WHERE issue_id=$1", [ids.issue]);
assert.equal((await db.query("SELECT public.claim_newsletter_dispatch($1,'all') AS claimed", [ids.issue])).rows[0].claimed, true);
await db.query("SELECT public.finish_newsletter_dispatch($1,'all',true)", [ids.issue]);
assert.ok((await db.query("SELECT sent_at FROM public.newsletter_issues WHERE id=$1", [ids.issue])).rows[0].sent_at);
assert.equal((await db.query("SELECT public.claim_newsletter_dispatch($1,'all') AS claimed", [ids.issue])).rows[0].claimed, false);
console.log("PASS: newsletter dispatch claims recover after failure and finalize once");

// Stripe mapping, atomic subscription persistence, and event idempotency.
await db.query("INSERT INTO public.membership_plans(id,code,tier,name,price_cents,currency,interval,stripe_price_id) VALUES ($1,'basic','basic','Basic',1000,'USD','month','price_test')", [ids.plan]);
await db.query("SELECT public.link_stripe_customer('cus_test123',$1)", [ids.user1]);
const eventArgs = ["evt_test_1","customer.subscription.created","cus_test123",ids.user1,"sub_test_1",ids.plan,"active",new Date().toISOString(),new Date(Date.now()+86400000).toISOString(),false,JSON.stringify({id:"evt_test_1"})];
let eventResult = await db.query("SELECT public.apply_stripe_subscription_event($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::jsonb) AS result", eventArgs);
assert.equal(eventResult.rows[0].result, "processed");
assert.equal((await db.query("SELECT user_id,status FROM public.user_subscriptions WHERE provider_subscription_id='sub_test_1'")).rows[0].user_id, ids.user1);
eventResult = await db.query("SELECT public.apply_stripe_subscription_event($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::jsonb) AS result", eventArgs);
assert.equal(eventResult.rows[0].result, "duplicate");
assert.equal((await db.query("SELECT count(*)::int AS n FROM public.payment_events WHERE event_id='evt_test_1'")).rows[0].n, 1);
console.log("PASS: Stripe customer mapping and subscription/event persistence are transactional and idempotent");

// Real reader overlap counts distinct books and shared mood values, not IDs.
await db.query("INSERT INTO public.book_mood_votes(book_id,user_id,moods) VALUES ($1,$2,ARRAY['hopeful','funny']::public.mood_kind[]),($1,$3,ARRAY['hopeful','dark']::public.mood_kind[])", [ids.book1, ids.user1, ids.user2]);
const overlap = await db.query("SELECT matched_id,shared_books,array_to_json(shared_moods)::text AS shared_moods_json FROM public.get_reader_overlaps($1,ARRAY[$2]::uuid[])", [ids.user1, ids.user2]);
assert.equal(overlap.rows[0].matched_id, ids.user2);
assert.equal(overlap.rows[0].shared_books, 1);
assert.deepEqual(JSON.parse(overlap.rows[0].shared_moods_json), ["hopeful"]);
console.log("PASS: reader matching overlap returns shared book count and shared moods");

await db.close();
console.log("ALL BUSINESS-RULE TESTS PASSED");
