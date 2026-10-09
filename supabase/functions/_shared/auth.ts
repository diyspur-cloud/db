import { createClient, type User } from "@supabase/supabase-js";
import { cors } from "./cors.ts";

function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`missing_required_env:${name}`);
  return value;
}

export function serviceClient() {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export async function requestUser(req: Request): Promise<User | null> {
  const match = (req.headers.get("Authorization") ?? "").match(
    /^Bearer\s+(\S+)$/i,
  );
  if (!match) return null;
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
    Deno.env.get("SB_PUBLISHABLE_KEY");
  if (!publicKey) {
    throw new Error("missing_required_env:SUPABASE_PUBLISHABLE_KEY");
  }
  const client = createClient(env("SUPABASE_URL"), publicKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.getUser(match[1]);
  if (error || !data.user) return null;
  return data.user;
}

export async function isAdmin(
  userId: string,
  service = serviceClient(),
): Promise<boolean> {
  const { data, error } = await service.from("profiles").select("role").eq(
    "id",
    userId,
  ).maybeSingle();
  return !error && data?.role === "admin";
}

export const json = (body: unknown, status = 200) =>
  cors(Response.json(body, { status }));

export function constantTimeEqual(actual: string, expected: string): boolean {
  const a = new TextEncoder().encode(actual);
  const b = new TextEncoder().encode(expected);
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) mismatch |= a[i] ^ b[i];
  return mismatch === 0;
}

export const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
