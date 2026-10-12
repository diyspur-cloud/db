# Observabilidade em Supabase Edge Functions — DIYSPUR

## 1. Visão Geral
As 11 Supabase Edge Functions em Deno foram instrumentadas com um helper unificado (`supabase/functions/_shared/observability.ts`), utilizando a versão validada `npm:@sentry/deno@11.6.0`.

## 2. Padrão de Instrumentação
O helper centraliza a captura e o isolamento de dados:
```ts
import * as Sentry from "npm:@sentry/deno@11.6.0";

export function initFunctionObservability(functionName: string): void;
export async function captureFunctionException(
  error: unknown,
  functionName: string,
  requestId: string,
): Promise<void>;
```

### Princípios de Implementação
1. **Identificador de Correlação (`request_id`)**: Cada requisição gera um UUID (`crypto.randomUUID()`) no início do handler para correlacionar logs nativos do Supabase com eventos de exceção no Sentry.
2. **Separação de Erros de Negócio x Falhas Técnicas**:
   - Respostas esperadas (400, 401, 403, 404, 409, 422, 429) retornam código HTTP correspondente e **não** geram evento no Sentry.
   - Apenas falhas inesperadas (5xx, quebras de RPC, falhas de rede de terceiros) no bloco `catch` externo acionam `captureFunctionException`.
3. **Flush com Timeout Limitado**: O método `Sentry.flush(1500)` garante o despacho do evento técnico dentro da janela de execução da Edge Function, sem bloquear excessivamente a resposta 503/500 para o cliente.
4. **Resiliência a Falhas de Telemetria**: Se `SENTRY_DSN` não estiver configurada no ambiente, o helper retorna imediatamente e a função continua operando normalmente com logs nativos do Supabase.

## 3. Inventário das 11 Funções Instrumentadas
1. `quiz-validate`: Validação atômica de quiz com idempotência e rate limit.
2. `award-xp`: Premiação de XP com validação de atividade e idempotência.
3. `scheduled-reminders`: Lembretes de reuniões com janela de 48h.
4. `stripe-webhook`: Webhooks de assinatura com verificação criptográfica.
5. `vote-next-book`: Votação de livros com validação de enquete aberta.
6. `ai-recommendations`: Recomendações personalizadas via embeddings.
7. `ai-user-embeddings`: Atualização de vetores de perfil de leitura.
8. `generate-book-embeddings`: Batch admin para geração de embeddings de obras.
9. `match-readers`: Afinidade entre leitores com cálculo de overlap.
10. `newsletter-dispatch`: Envio idempotente de boletins para inscritos.
11. `social-render-card`: Renderização de cards SVG de leitura.

## 4. Configuração de Secrets no Supabase
Para habilitar o envio em produção, configurar via Supabase CLI ou Dashboard:
```bash
supabase secrets set SENTRY_DSN="https://..." SENTRY_ENVIRONMENT="production"
```
Nunca incluir chaves nos arquivos de migração SQL, seeds ou commits do repositório.
