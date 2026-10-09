import assert from "node:assert/strict";
import { createClient } from "@supabase/supabase-js";
import type { Database } from "../../src/lib/supabase/database.types.ts";

const PRODUCTION_PROJECT_REF = "xjhehhfhhoomblcggjpk";
const required = (name: string): string => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
};

const url = required("SUPABASE_URL");
const publishableKey = required("SUPABASE_PUBLISHABLE_KEY");
const serviceRoleKey = required("SUPABASE_SERVICE_ROLE_KEY");
const projectRef = new URL(url).hostname.split(".")[0];
const declaredTestRef = required("SUPABASE_TEST_PROJECT_REF");
if (projectRef === PRODUCTION_PROJECT_REF) {
  throw new Error(
    "Refusing to run mutating integration tests against the production project.",
  );
}
if (projectRef !== declaredTestRef) {
  throw new Error(
    "SUPABASE_TEST_PROJECT_REF must match the project reference in SUPABASE_URL.",
  );
}
if (Deno.env.get("SUPABASE_TEST_ALLOW_MUTATIONS") !== "true") {
  throw new Error(
    "Set SUPABASE_TEST_ALLOW_MUTATIONS=true only after verifying this is a disposable isolated project.",
  );
}

const admin = createClient<Database>(url, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});
const anonymous = createClient<Database>(url, publishableKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});
const nonce = crypto.randomUUID().replaceAll("-", "").slice(0, 14)
  .toLowerCase();
const password = `T3st-${crypto.randomUUID()}-Aa!`;
const accounts = [
  {
    email: `reader-a-${nonce}@example.com`,
    username: `smoke_a_${nonce}`,
    displayName: `Smoke A ${nonce}`,
  },
  {
    email: `reader-b-${nonce}@example.com`,
    username: `smoke_b_${nonce}`,
    displayName: `Smoke B ${nonce}`,
  },
];
const createdUserIds: string[] = [];
const clients: ReturnType<typeof createClient<Database>>[] = [];
const channels: ReturnType<
  ReturnType<typeof createClient<Database>>["channel"]
>[] = [];
let journalEntryId: string | undefined;
let storagePath: string | undefined;
let failure: unknown;

const waitForStatus = (
  subscribe: (callback: (status: string) => void) => unknown,
) =>
  new Promise<void>((resolve, reject) => {
    const timeout = setTimeout(
      () => reject(new Error("Realtime subscription timed out")),
      15000,
    );
    subscribe((status) => {
      if (status === "SUBSCRIBED") {
        clearTimeout(timeout);
        resolve();
      } else if (
        status === "CHANNEL_ERROR" || status === "TIMED_OUT" ||
        status === "CLOSED"
      ) {
        clearTimeout(timeout);
        reject(new Error(`Realtime subscription failed: ${status}`));
      }
    });
  });

try {
  const users = [];
  for (const account of accounts) {
    const { data, error } = await admin.auth.admin.createUser({
      email: account.email,
      password,
      email_confirm: true,
      user_metadata: {
        username: account.username,
        display_name: account.displayName,
      },
    });
    if (error || !data.user) {
      throw error ?? new Error("Admin API returned no user");
    }
    createdUserIds.push(data.user.id);
    users.push({ ...account, id: data.user.id });
  }
  const signedIn = [];
  for (const user of users) {
    const client = createClient<Database>(url, publishableKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data, error } = await client.auth.signInWithPassword({
      email: user.email,
      password,
    });
    if (error || !data.session?.access_token) {
      throw error ?? new Error("Password sign-in returned no session");
    }
    clients.push(client);
    signedIn.push({ ...user, client });
    const refreshed = await client.auth.refreshSession();
    assert.equal(
      refreshed.error,
      null,
      "refresh should preserve an authenticated session",
    );
  }
  console.log("PASS: disposable Auth users can sign in and refresh sessions");

  const [readerA, readerB] = signedIn;
  const consent = await readerA.client.rpc("set_my_lgpd_consent", {
    p_consent: true,
  });
  assert.equal(
    consent.error,
    null,
    "owner may set their own consent via the RPC",
  );
  const privateProfile = await readerA.client.rpc("get_my_profile_private");
  assert.equal(privateProfile.error, null);
  assert.equal(privateProfile.data?.[0]?.lgpd_consent, true);
  const crossUserPii = await readerB.client.from("profiles").select("whatsapp")
    .eq("id", readerA.id).maybeSingle();
  assert.ok(
    crossUserPii.error || crossUserPii.data === null,
    "another user cannot read profile PII",
  );
  console.log(
    "PASS: consent is owner-scoped and direct cross-user PII access is denied",
  );

  const book = await anonymous.from("books").select("id").limit(1)
    .maybeSingle();
  if (book.error || !book.data?.id) {
    throw book.error ??
      new Error("Isolated project needs one catalog book for the journal test");
  }
  const feedMedia = readerA.client.storage.from("feed-media");
  storagePath = `${readerA.id}/integration-smoke-${nonce}.txt`;
  const content = new Blob([`temporary integration test ${nonce}\n`], {
    type: "text/plain",
  });
  const upload = await feedMedia.upload(storagePath, content, {
    contentType: "text/plain",
    upsert: false,
  });
  if (upload.error) throw upload.error;
  const ownDownload = await feedMedia.download(storagePath);
  assert.equal(ownDownload.error, null, "uploader may read own private media");
  const otherDownload = await readerB.client.storage.from("feed-media")
    .download(storagePath);
  assert.ok(otherDownload.error, "different user cannot read private media");
  const anonymousDownload = await anonymous.storage.from("feed-media").download(
    storagePath,
  );
  assert.ok(anonymousDownload.error, "anonymous cannot read private media");
  const publicUrl = feedMedia.getPublicUrl(storagePath).data.publicUrl;
  const publicResponse = await fetch(publicUrl);
  assert.ok(
    !publicResponse.ok,
    "private media must not be readable through a public object URL",
  );
  const anonymousUpload = await anonymous.storage.from("feed-media").upload(
    `${readerA.id}/anonymous-${nonce}.txt`,
    content,
    { contentType: "text/plain" },
  );
  assert.ok(anonymousUpload.error, "anonymous upload must be rejected");
  console.log(
    "PASS: private Storage owner access works; cross-user, anon and public-URL access fail",
  );

  let readerAEvent = false;
  let readerBEvent = false;
  const channelA = readerA.client.channel(`integration-${nonce}-a`).on(
    "postgres_changes",
    {
      event: "INSERT",
      schema: "public",
      table: "reading_journal_entries",
      filter: `user_id=eq.${readerA.id}`,
    },
    () => {
      readerAEvent = true;
    },
  );
  const channelB = readerB.client.channel(`integration-${nonce}-b`).on(
    "postgres_changes",
    {
      event: "INSERT",
      schema: "public",
      table: "reading_journal_entries",
      filter: `user_id=eq.${readerA.id}`,
    },
    () => {
      readerBEvent = true;
    },
  );
  channels.push(channelA, channelB);
  await Promise.all([
    waitForStatus((callback) =>
      channelA.subscribe((status) => callback(status))
    ),
    waitForStatus((callback) =>
      channelB.subscribe((status) => callback(status))
    ),
  ]);
  const journal = await readerA.client.from("reading_journal_entries").insert({
    book_id: book.data.id,
    user_id: readerA.id,
    entry_date: new Date().toISOString().slice(0, 10),
    body: `temporary integration test ${nonce}`,
    visibility: "private",
  }).select("id").single();
  if (journal.error || !journal.data?.id) {
    throw journal.error ?? new Error("Could not create test journal entry");
  }
  journalEntryId = journal.data.id;
  const deadline = Date.now() + 12000;
  while (!readerAEvent && Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  assert.equal(
    readerAEvent,
    true,
    "owner should receive own permitted Realtime INSERT",
  );
  await new Promise((resolve) => setTimeout(resolve, 1500));
  assert.equal(
    readerBEvent,
    false,
    "another user must not receive a private journal event",
  );
  console.log(
    "PASS: Realtime delivers a private journal change only to its owner",
  );
} catch (error) {
  failure = error;
} finally {
  for (const channel of channels) {
    try {
      await channel.unsubscribe();
    } catch { /* best-effort isolated-test cleanup */ }
  }
  if (journalEntryId && clients[0]) {
    try {
      await clients[0].from("reading_journal_entries").delete().eq(
        "id",
        journalEntryId,
      );
    } catch { /* best effort */ }
  }
  if (storagePath && clients[0]) {
    try {
      await clients[0].storage.from("feed-media").remove([storagePath]);
    } catch { /* best effort */ }
  }
  for (const client of clients) {
    try {
      await client.auth.signOut();
    } catch { /* best effort */ }
  }
  for (const id of createdUserIds) {
    try {
      await admin.auth.admin.deleteUser(id);
    } catch { /* best effort; no user data is read or retained */ }
  }
}

if (failure) throw failure;
console.log("ALL AUTH/STORAGE/REALTIME INTEGRATION SMOKES PASSED");
