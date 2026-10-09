#!/usr/bin/env node

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { PGlite } from "./security-smoke/node_modules/@electric-sql/pglite/dist/index.js";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const migrationDir = resolve(repoRoot, "supabase/migrations");
const sourceMigration = resolve(
  migrationDir,
  "20261008214920_add_community_reading_views.sql",
);
const prerequisiteMigrations = [
  "20261008214832_add_book_reviews.sql",
  "20261008214847_add_user_club_reading_context.sql",
];
const bootstrapPath = resolve(repoRoot, "scripts/replay-local.bootstrap.sql");
const overlayPath = resolve(repoRoot, "scripts/replay-local.overlay.sql");
const contractPath = resolve(repoRoot, "supabase/tests/sdd_contract.test.sql");
const communityAlignmentPath = resolve(
  migrationDir,
  "20261009170633_align_community_stats_snapshot.sql",
);
const snapshotAlignmentPath = resolve(
  migrationDir,
  "20261009170647_align_reading_snapshot_keys.sql",
);

function usage() {
  console.log(`Usage: node scripts/replay-local.mjs [--reduced]\n\nRuns the disposable reduced community replay in PGlite. Full Docker replay is\nowned by scripts/replay-local.sh --full; this runner never connects remotely.`);
}

if (process.argv.includes("--help") || process.argv.includes("-h")) {
  usage();
  process.exit(0);
}

if (process.argv.some((arg) => arg !== "--reduced" && arg !== process.argv[0] && arg !== process.argv[1])) {
  usage();
  process.exit(2);
}

const [
  bootstrap,
  overlay,
  contract,
  source,
  communityAlignment,
  snapshotAlignment,
  ...prerequisites
] = await Promise.all([
  readFile(bootstrapPath, "utf8"),
  readFile(overlayPath, "utf8"),
  readFile(contractPath, "utf8"),
  readFile(sourceMigration, "utf8"),
  readFile(communityAlignmentPath, "utf8"),
  readFile(snapshotAlignmentPath, "utf8"),
  ...prerequisiteMigrations.map((filename) => readFile(resolve(migrationDir, filename), "utf8")),
]);

const sourceHashBefore = createHash("sha256").update(source).digest("hex");
const sourceProjection = "s.title as current_season_title";
const correctedProjection = "current_season.title as current_season_title";
assert.equal(
  source.split(sourceProjection).length - 1,
  1,
  "historical source must still contain exactly the known failing projection",
);
assert.ok(
  overlay.includes(correctedProjection),
  "replay overlay must contain the corrected current-season projection",
);

async function preparedDatabase() {
  const db = new PGlite();
  await db.exec(bootstrap);
  for (const migration of prerequisites) await db.exec(migration);
  return db;
}

async function reproduceHistoricalFailure() {
  const db = await preparedDatabase();
  try {
    let failure;
    try {
      await db.exec(source);
    } catch (error) {
      failure = error;
    }
    assert.ok(failure, "the untouched historical migration should reproduce 42803");
    assert.match(
      String(failure),
      /42803|must appear in the GROUP BY|s\\.title/i,
      `unexpected historical replay error: ${String(failure)}`,
    );
    console.log("PASS: untouched migration reproduces the known 42803 at the club view");
  } finally {
    await db.close();
  }
}

async function applyScratchOverlay(db) {
  const clubViewStart = source.indexOf(
    "create or replace view public.v_club_progress_panel",
  );
  const snapshotStart = source.indexOf("-- Snapshot sempre passa pelo RLS");
  assert.ok(clubViewStart > 0, "historical club-view block marker is missing");
  assert.ok(snapshotStart > clubViewStart, "historical snapshot marker is missing");

  // Ordering is intentional: run the historical prefix, replace only the
  // failing block with the replay overlay, then continue with the historical
  // suffix. No migration row is inserted and no historical file is edited.
  await db.exec(source.slice(0, clubViewStart));
  await db.exec(overlay);
  await db.exec(source.slice(snapshotStart));
}

async function runReducedReplay() {
  const db = await preparedDatabase();
  try {
    await applyScratchOverlay(db);
    // O fixture reduzido não contém a migration completa de mood stats nem
    // overview/quiz. Aplicar somente os alinhamentos que ele consegue provar
    // mantém o teste útil sem alegar que seja um reset integral.
    await db.exec(`alter table public.book_mood_stats add column mood_percent jsonb;`);
    await db.exec(communityAlignment);
    await db.exec(snapshotAlignment);

    await db.exec(`
      insert into public.books(id, title)
      values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Replay book');
      insert into public.seasons(id, number, title, slug, book_id, status)
      values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 1, 'Replay season', 'replay-season',
              'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'active');
      insert into public.chapters(id, season_id, number, title, published_at)
      values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc',
              'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 1, 'Replay chapter', now());
      insert into public.profiles(id) values ('11111111-1111-4111-8111-111111111111');
      insert into public.user_clubs(
        id, name, owner_id, is_private, current_book_id, current_season_id,
        current_started_at, current_ends_at
      ) values (
        'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Replay club',
        '11111111-1111-4111-8111-111111111111', false,
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', now(), now() + interval '7 days'
      );
      insert into public.user_club_members(club_id, user_id)
      values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd',
              '11111111-1111-4111-8111-111111111111');
      insert into public.user_progress(user_id, chapter_id, status, percent)
      values ('11111111-1111-4111-8111-111111111111',
              'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'reading', 42);
      insert into public.book_mood_stats(book_id, mood_counts, pace_percent, sample_size)
      values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '{}', '{"slow":100}', 1);
      refresh materialized view private.mv_book_community_stats;
    `);

    const panel = await db.query(`
      select club_name, current_season_title, distinct_readers,
             chapters_in_progress, avg_percent
        from public.v_club_progress_panel
       where club_id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
    `);
    assert.deepEqual(panel.rows, [{
      club_name: "Replay club",
      current_season_title: "Replay season",
      distinct_readers: 1,
      chapters_in_progress: 1,
      avg_percent: "42.00",
    }]);

    await db.exec(contract);
    const sourceHashAfter = createHash("sha256").update(source).digest("hex");
    assert.equal(sourceHashAfter, sourceHashBefore, "historical migration changed in memory");
    const sourceHashOnDisk = createHash("sha256")
      .update(await readFile(sourceMigration))
      .digest("hex");
    assert.equal(sourceHashOnDisk, sourceHashBefore, "historical migration changed on disk");
    console.log("PASS: replay overlay runs before the historical snapshot suffix");
    console.log("PASS: view returns the current season title and aggregated progress");
    console.log("PASS: supabase/tests/sdd_contract.test.sql");
    console.log("RESULT: REDUCED PGlite replay PASS (not a full Supabase/Docker reset)");
  } finally {
    await db.close();
  }
}

try {
  await reproduceHistoricalFailure();
  await runReducedReplay();
} catch (error) {
  console.error(`FAIL: ${error instanceof Error ? error.stack : String(error)}`);
  process.exitCode = 1;
}
