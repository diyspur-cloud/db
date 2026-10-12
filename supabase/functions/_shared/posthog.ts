const host = Deno.env.get("POSTHOG_HOST") ?? "https://us.i.posthog.com";
const token = Deno.env.get("POSTHOG_PROJECT_TOKEN") ?? Deno.env.get("NEXT_PUBLIC_POSTHOG_KEY");

/**
 * Captura analítica server-side mínima para eventos de negócio confirmados.
 * Não bloqueia a resposta nem registra dados pessoais sensíveis.
 */
export async function captureServerEvent(
  distinctId: string,
  event: string,
  properties: Record<string, unknown> = {},
): Promise<void> {
  if (!token) return;
  try {
    await fetch(`${host.replace(/\/$/, "")}/capture/`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        api_key: token,
        event,
        distinct_id: distinctId,
        properties: {
          ...properties,
          $lib: "supabase-edge-function",
        },
      }),
    });
  } catch {
    // Telemetria nunca interrompe a execução de negócio
  }
}
