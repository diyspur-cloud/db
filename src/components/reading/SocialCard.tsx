import { useEffect, useState } from "react";
import {
  getMySocialCardJob,
  renderSocialCard,
  type SocialRenderJob,
  type SocialTemplateKind,
} from "../../lib/supabase/activities";

export type SocialCardProps = {
  kind: SocialTemplateKind;
  payload: Record<string, unknown>;
  jobId?: string;
  onJobChange?: (job: SocialRenderJob) => void;
};

export function SocialCard({
  kind,
  payload,
  jobId,
  onJobChange,
}: SocialCardProps) {
  const [job, setJob] = useState<SocialRenderJob | null>(null);
  const [loading, setLoading] = useState(Boolean(jobId));
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!jobId) {
      setLoading(false);
      return;
    }
    let mounted = true;
    setLoading(true);
    void getMySocialCardJob(jobId)
      .then((nextJob) => {
        if (!mounted) return;
        setJob(nextJob);
        if (nextJob) onJobChange?.(nextJob);
      })
      .catch((reason: unknown) => {
        if (mounted) setError(reason instanceof Error ? reason.message : "load_failed");
      })
      .finally(() => {
        if (mounted) setLoading(false);
      });
    return () => {
      mounted = false;
    };
  }, [jobId, onJobChange]);

  async function createCard() {
    setError(null);
    setLoading(true);
    try {
      const result = await renderSocialCard(kind, payload);
      setJob(result.job);
      onJobChange?.(result.job);
    } catch (reason: unknown) {
      setError(reason instanceof Error ? reason.message : "render_failed");
    } finally {
      setLoading(false);
    }
  }

  if (loading) return <p role="status">Gerando cartão…</p>;
  if (error) return <p role="alert">Não foi possível gerar o cartão: {error}</p>;
  if (job?.image_url && job.status === "rendered") {
    return <img src={job.image_url} alt="Cartão de leitura" />;
  }
  if (job?.status === "failed") {
    return <p role="alert">A renderização falhou: {job.error ?? "erro desconhecido"}</p>;
  }
  if (job?.status === "queued") {
    return <p role="status">Cartão enfileirado para renderização.</p>;
  }
  return (
    <button type="button" onClick={() => void createCard()}>
      Criar cartão social
    </button>
  );
}
