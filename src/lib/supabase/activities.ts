import type { Database } from "./database.types";
import { supabase } from "./client";

export type SocialTemplateKind =
  Database["public"]["Enums"]["social_template_kind"];
export type SocialRenderJob =
  Database["public"]["Tables"]["social_render_jobs"]["Row"];

export async function renderSocialCard(
  kind: SocialTemplateKind,
  payload: Record<string, unknown>,
) {
  const { data, error } = await supabase.functions.invoke("social-render-card", {
    body: { kind, payload },
  });
  if (error) throw error;
  return data as {
    ok: true;
    job_id: string;
    image_url: string;
    job: SocialRenderJob;
  };
}

export async function getMySocialCardJob(
  jobId: string,
): Promise<SocialRenderJob | null> {
  const { data, error } = await supabase
    .from("social_render_jobs")
    .select("id,user_id,kind,payload,status,image_url,error,created_at,rendered_at")
    .eq("id", jobId)
    .maybeSingle();
  if (error) throw error;
  return data;
}
