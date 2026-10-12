# Runbook Operacional de Observabilidade e Incidentes — DIYSPUR

## 1. Incidente: Spike de 5xx após Deploy
1. **Identificação**:
   - Alerta Sentry de nova release ou taxa de erro > 1%.
   - Verificar logs do Supabase: API Gateway ou Edge Functions reportando 503/500.
2. **Diagnóstico**:
   - Acessar o Sentry e filtrar por `release` e `environment: production`.
   - Inspecionar a tag `boundary` ou `edge_function` para identificar o ponto exato da falha.
   - Cruzar o `request_id` do log com o evento do Sentry.
3. **Ação Imediata**:
   - Se a falha for no frontend: acionar Rollback Instantâneo no Vercel para a versão anterior.
   - Se a falha for na Edge Function: reimplantar a versão estável anterior da função afetada via CI/Supabase CLI.

## 2. Incidente: Falha no Webhook da Stripe (`stripe-webhook`)
1. **Identificação**:
   - Alertas no Dashboard da Stripe sobre entregas com falha (status 5xx).
   - Eventos no Sentry com a tag `edge_function: stripe-webhook`.
2. **Diagnóstico**:
   - Verificar se `STRIPE_WEBHOOK_SECRET` ou `STRIPE_SECRET_KEY` estão configurados corretamente nos secrets do Supabase.
   - Conferir se o preço do item (`price_id`) possui mapeamento na tabela `membership_plans`.
3. **Mitigação**:
   - Corrigir o mapeamento ou segredo via Supabase Dashboard.
   - O Stripe fará retentativas automáticas (backoff exponencial) nas próximas 24 horas.

## 3. Incidente: Falha em `scheduled-reminders` (Cron Job)
1. **Identificação**:
   - Falha na execução agendada do cron reportada no Sentry com `edge_function: scheduled-reminders`.
2. **Diagnóstico**:
   - Verificar se o header `x-scheduled-reminders-secret` enviado pelo scheduler confere com `SCHEDULED_REMINDERS_SECRET`.
   - Checar se a paginação de reuniões ou RSVPs excedeu o tempo limite do runtime.
3. **Mitigação**:
   - Reexecutar o disparo manualmente após ajuste de secrets ou janelas de envio.

## 4. Incidente: Falha na Geração do Sitemap
1. **Identificação**:
   - Eventos no Sentry com tag `service: sitemap`.
2. **Diagnóstico**:
   - O sitemap possui fallback gracioso: falhas na consulta ao banco retornam as rotas públicas fixas sem quebrar o crawler.
   - Investigar latência ou permissões de leitura no Supabase.
