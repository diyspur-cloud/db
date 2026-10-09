import { supabase } from "./client";
import type { Database } from "./database.types";

export type PublicProfile =
  Database["public"]["Views"]["v_profiles_public"]["Row"];

export async function getPublicProfile(
  userId: string,
): Promise<PublicProfile | null> {
  const { data, error } = await supabase
    .from("v_profiles_public")
    .select("id,username,display_name,avatar_url,bio,level,created_at")
    .eq("id", userId)
    .maybeSingle();
  if (error) throw error;
  return data;
}

export async function getMyProfile() {
  const { data: auth, error: authError } = await supabase.auth.getUser();
  if (authError || !auth.user) throw authError ?? new Error("unauthenticated");
  const { data, error } = await supabase
    .from("profiles")
    .select("id,username,display_name,avatar_url,bio,onboarding_done")
    .eq("id", auth.user.id)
    .maybeSingle();
  if (error) throw error;
  return data;
}
