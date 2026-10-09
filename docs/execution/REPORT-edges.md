# Relatório SDD — backend Edge/Seeds/Cron (`edges`)

**Data:** 2026-10-09 (ambiente sandbox)
**Escopo:** §§6–10 e 13–15 do SDD, limitado a `supabase/functions`, `supabase/config.toml`, seeds e scripts de deploy/cron. Não houve commit, push, deploy, migration remota, reset remoto, envio de mensagem ou pagamento.

## Implementado

- `supabase/functions/quiz-validate/index.ts`
  - Mantida a autenticação por identidade validada, completude das respostas, limite de 50, filtro de temporada, `consume_quiz_rate_limit`, `record_quiz_attempt` e XP idempotente.
  - Quando não há `Idempotency-Key` nem `request_id`, gera `crypto.randomUUID()` no servidor para compatibilidade com o payload antigo.
  - UUID fornecido continua sendo validado; retries idempotentes continuam exigindo o mesmo UUID fornecido.
- `supabase/functions/award-xp/index.ts`
  - O mapa contém `streak_bonus: 25`.
  - `source=streak_bonus` não confia em `ref_id` enviado pelo cliente: chama `award_daily_streak_bonus(p_user)` via cliente service-role. A RPC server-only verifica atividade do dia, usa `current_date`/UTC conforme o streak existente, deriva referência diária determinística e mantém a idempotência do ledger. A resposta aceita o booleano retornado pela RPC; não há concessão local arbitrária.
  - As outras cinco fontes e suas verificações de atividade permanecem sem alteração material.
- `supabase/functions/scheduled-reminders/index.ts`
  - Paginação completa de reuniões e RSVPs, com ordenação estável (`scheduled_at,id` e `user_id`).
  - Preservada a decisão explícita de público: somente reuniões `status=scheduled` na janela de 48 horas e RSVPs `attending=true`. O SDD não define promoção de reuniões canceladas/em andamento ou RSVP negativo, portanto esses casos não foram ampliados silenciosamente.
  - Entrega continua passando pela RPC idempotente existente, preservando payload com reunião, título e horário e evitando duplicação.
- `supabase/functions/newsletter-dispatch/index.ts`
  - `tags`, `tags_any`, `tags_all` e `frequency` do seed/contrato são aceitos e validados para compatibilidade.
  - Decisão de audiência agora é literal e explícita no código: `todos_confirmados`. Tags e demais filtros são ignorados na seleção; entram somente na chave do claim/ledger. A seleção permanece limitada a `status=confirmed` e `unsubscribed_at is null`, e entregas já `sent` continuam sendo ignoradas.
  - Não foi escolhido um modo de audiência silencioso nem criada configuração externa não definida.
- `supabase/functions/match-readers/index.ts`
  - Sem embedding, retorna literalmente `{ ok: false, reason: "no_embedding" }`, sem fabricar matches.
- `supabase/functions/social-render-card/index.ts`
  - Persiste o objeto `payload` original, em vez de reduzir os dados a `title/quote`.
  - Retorna o job persistido após atualização de estado, além dos campos compatíveis `job_id` e `image_url`.
- `supabase/functions/stripe-webhook/index.ts`
  - `Stripe` deixou de ser instanciado no topo do módulo. A chave é conferida somente após método/assinatura e dentro da requisição; ausência de `STRIPE_SECRET_KEY` responde `503 webhook not configured`, sem exibir valor nem derrubar o boot do módulo.
- `supabase/config.toml`
  - Reset local passa a carregar, em ordem, `./seed.sql` e `./seed_complement.sql`.
  - Providers OAuth não foram ativados: Google/GitHub continuam dependendo de credenciais reais ausentes.
- `supabase/seed.sql` e `supabase/seed_complement.sql`
  - Selects por número de capítulo foram restringidos à temporada Dom Casmurro UUID `33333333-3333-3333-3333-333333333333`.
  - Guardas `ON CONFLICT`/`NOT EXISTS` existentes foram preservadas para repetição sem duplicação; milestones continuam sendo gerados pela função idempotente existente.
  - O filtro editorial `{"tags":["welcome"]}` foi preservado; o handler aceita esse campo e aplica a decisão explícita de todos confirmados.
- `scripts/deploy-edge-functions.sh`
  - Loop inclui os dez handlers exigidos, inclusive `ai-user-embeddings`. Stripe continua com `--no-verify-jwt`; os demais mantêm a verificação JWT padrão.
- `scripts/schedule-reminders.sql`
  - Novo script operacional fora de migrations para `reminders-every-hour` em `0 * * * *`.
  - Usa Vault pelo nome `scheduled_reminders_secret`, nunca grava o segredo, verifica a existência do job antes de criar outro e chama o endpoint com `x-scheduled-reminders-secret`.
  - Não foi executado remotamente.

## Testes realmente executados

- **Passou:** `/home/ubuntu/bin/deno task --config supabase/functions/deno.json check` — 11 fontes de funções verificadas.
- **Passou:** `/home/ubuntu/bin/deno task --config supabase/functions/deno.json lint` — 13 arquivos verificados.
- **Passou:** `/home/ubuntu/bin/deno task --config supabase/functions/deno.json fmt:check` — 13 arquivos verificados.
- **Passou:** `npm test` em `scripts/security-smoke/` — smoke local PGlite; asserções de segurança e regras de negócio passaram, incluindo idempotência de XP, rate/attempt de quiz, reminders, newsletter, Stripe e matching. Esse teste não é um teste HTTP hospedado nem valida o novo handler com JWT real.
- **Passou:** `bash -n scripts/deploy-edge-functions.sh`.
- **Passou:** parse TOML via Python `tomllib`, confirmando `['./seed.sql', './seed_complement.sql']`.
- **Passou:** inventário estático dos dez `index.ts` e presença de `ai-user-embeddings` no script de deploy.
- **Passou:** `git diff --check`.
- **Consultado sem mutação:** `/home/ubuntu/bin/supabase --version` retornou `2.120.0`; a ajuda de `functions deploy` foi consultada antes de qualquer operação.

## Bloqueios e limites reais

- **Deploy remoto não executado por autorização:** o pai fará a publicação pelo MCP. Não há afirmação de que os endpoints hospedados deixaram de retornar `NOT_FOUND`.
- **Secrets externos ausentes no runtime:** a inspeção autenticada informou “No custom secrets created”. Não existem, neste momento, `OPENAI_API_KEY`, `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` ou `SCHEDULED_REMINDERS_SECRET`. Portanto recomendações/embeddings, Resend, Stripe e cron não tiveram execução externa nem foram simulados com credenciais inventadas.
- **OAuth bloqueado:** Google e GitHub não foram habilitados sem client IDs/secrets reais, site URL e allowlist da aplicação.
- **Reset local completo de migrations + dois seeds não executado:** `supabase status` falhou porque o projeto não está vinculado e o sandbox não tem Docker/Podman (`docker: command not found`). A validação disponível foi estática; não foi declarado sucesso de seed/reset.
- **Cron não criado:** o arquivo SQL está pronto para revisão/administração, mas não houve execução, `cron.job_run_details`, resposta `pg_net` ou confirmação de não duplicação em projeto hospedado.
- **Integrações não exercidas:** não houve Auth JWT real, chamada Edge hospedada, envio de e-mail, chamada OpenAI, assinatura Stripe, pagamento, Realtime ou teste de provider. Os testes PGlite existentes não substituem essas evidências.

A migration compartilhada `supabase/migrations/20261009025524_award_daily_streak_bonus.sql` fornece a RPC service-only usada pelo branch diário; sua aplicação/publicação remota não foi realizada por este agente.
