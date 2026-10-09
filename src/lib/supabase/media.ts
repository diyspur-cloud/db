import { supabase } from "./client";

export type MediaBucket =
  | "feed-media"
  | "journal-media"
  | "chapter-extras"
  | "ebooks";

export async function signedMedia(
  bucket: MediaBucket,
  path: string,
  expiresIn = 300,
): Promise<string> {
  if (!path.trim()) throw new Error("storage_path_required");
  const { data, error } = await supabase.storage.from(bucket).createSignedUrl(
    path,
    expiresIn,
  );
  if (error) throw error;
  return data.signedUrl;
}

export async function uploadMyMedia(
  bucket: "journal-media" | "feed-media",
  file: File,
): Promise<{ path: string; mime_type: string; size_bytes: number }> {
  const { data: auth, error: authError } = await supabase.auth.getUser();
  if (authError || !auth.user) {
    throw authError ?? new Error("unauthenticated");
  }
  const mimeType = file.type || "application/octet-stream";
  const path = `${auth.user.id}/${crypto.randomUUID()}`;
  const { error } = await supabase.storage.from(bucket).upload(path, file, {
    contentType: mimeType,
    upsert: false,
  });
  if (error) throw error;
  return { path, mime_type: mimeType, size_bytes: file.size };
}

export async function signedChapterExtra(storagePath: string): Promise<string> {
  const { data: extra, error: extraError } = await supabase
    .from("chapter_extra_content")
    .select("id,is_public,external_url,storage_path")
    .eq("storage_path", storagePath)
    .maybeSingle();
  if (extraError) throw extraError;
  if (!extra) throw new Error("extra_not_found_or_not_visible");
  if (extra.external_url) return extra.external_url;
  if (!extra.is_public) {
    // A private extra can still be signed when the row is visible to the
    // current session; Storage RLS remains the final authorization boundary.
    const { data: auth } = await supabase.auth.getUser();
    if (!auth.user) throw new Error("unauthenticated");
  }
  return signedMedia("chapter-extras", storagePath);
}
