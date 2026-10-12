import * as Sentry from "npm:@sentry/deno@11.6.0";

const dsn = Deno.env.get("SENTRY_DSN");
const environment = Deno.env.get("SENTRY_ENVIRONMENT") ?? "production";
let initialized = false;

export function initFunctionObservability(functionName: string): void {
  if (!dsn || initialized) return;

  Sentry.init({
    dsn,
    environment,
    sendDefaultPii: false,
    tracesSampleRate: 0,
  });
  Sentry.setTag("service", "supabase-edge");
  Sentry.setTag("edge_function", functionName);
  initialized = true;
}

export async function captureFunctionException(
  error: unknown,
  functionName: string,
  requestId: string,
): Promise<void> {
  if (!dsn) return; // logs nativos Supabase continuam disponíveis.
  initFunctionObservability(functionName);
  Sentry.withScope((scope) => {
    scope.setTag("service", "supabase-edge");
    scope.setTag("edge_function", functionName);
    scope.setTag("request_id", requestId);
    Sentry.captureException(error);
  });
  try {
    await Sentry.flush(1500);
  } catch {
    // Flush timeout ou erro de rede não deve impedir o envio da resposta.
  }
}
