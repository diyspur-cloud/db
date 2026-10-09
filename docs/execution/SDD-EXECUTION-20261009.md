# Execução do SDD — 2026-10-09

## Escopo e segurança operacional

- Repositório: `diyspur-cloud/db`, branch local `main`, commit auditado `ce0355e19e9c45e915cb8d376efa3e0ced1da773`.
- Projeto remoto consultado read-only: `xjhehhfhhoomblcggjpk`.
- O catálogo remoto confirmou **51 migrations** e **11 Edge Functions `ACTIVE`**.
- Esta execução não fez `db push`, `migration repair`, reset remoto, DML remoto, redeploy de functions, criação de usuários, envio de newsletter, integração Stripe ou alteração de secrets.

## Implementação entregue em arquivos

| Área do SDD | Implementação | Evidência |
|---|---|---|
| UUID do seed | Regex canônica 8-4-4-4-12, sem exigir versão/variante RFC; teste aceita `22222222-2222-2222-2222-222222222222`. | `supabase/functions/_shared/auth.ts`, `_shared/auth.test.ts`, `deno.json` |
| Community stats | Snapshot privado alinhado às oito colunas públicas, alias `v_book_community_stats`, médias numéricas e grants explícitos. | `20261009170633_align_community_stats_snapshot.sql` |
| Reading overview | Contagem literal de linhas de progresso/capítulos, diário separado, `security_invoker=true`. | `20261009170637_align_user_reading_overview_contract.sql` |
| Reading goals | Cálculo anual de `books_done`, páginas e minutos no helper privado com `search_path` vazio. | `20261009170642_align_reading_goal_calculation.sql` |
| Reading snapshot | Serialização das chaves `title`, `moods`, `pace`, `rating`, `review`, mantendo ownership e filtro de review apagada. | `20261009170647_align_reading_snapshot_keys.sql` |
| Quiz parcial | Handler normaliza ausentes para `chosen_idx=-1`; foreign question, índice e configuração continuam server-side; retry compara vetor normalizado. | `supabase/functions/quiz-validate/index.ts`, `20261009170651_allow_partial_quiz_answers.sql` |
| Reminders | Paginação reduzida para `500`, abaixo do `max_rows=1000`, sem mudar a janela de 48 horas. | `supabase/functions/scheduled-reminders/index.ts` |
| Storage | Upload no diretório do usuário, URLs assinadas temporárias e consulta de `chapter_extra_content` antes de assinar. | `src/lib/supabase/media.ts` |
| Realtime | Helper com canais nomeados, filtros, reload autorizado, status e cleanup. | `src/lib/supabase/realtime.ts` |
| Consumidores | Adapters para perfil, leitura, stats, clubes, quiz, gamificação, social, cards e atividades. | `src/lib/supabase/*.ts` |
| Social card | Componente para `queued`, `rendered`, `failed` e retorno de imagem. | `src/components/reading/SocialCard.tsx` |
| Shared functions | Reexport de `serviceClient` e tipos de erro sem segundo cliente privilegiado. | `supabase/functions/_shared/supabaseAdmin.ts`, `types.ts` |
| Replay | Runner full preparado para CLI global ou npx, cópia descartável, correção somente na cópia e dupla carga explícita de `seed.sql`/`seed_complement.sql`. | `scripts/replay-local.sh`, `replay-local.mjs`, `replay-local.seed-check.sql` |
| Contratos/documentação | OpenAPI para UUID/quiz/status de cards; autorização, deployment, reconciliação, plano e bloqueios atualizados. | `docs/openapi.yaml`, `docs/execution/*.md` |

### Decisões preservadas

- O filtro de temporada do helper de clube foi **mantido**: o painel deve refletir a temporada atual quando definida. O smoke PGlite existente testa duas temporadas e confirma que a temporada antiga não entra na contagem.
- `stripe_price_id` não foi preenchido: os IDs reais não foram fornecidos e nenhum placeholder foi inventado.
- URLs de vídeo/material continuam exemplos: o SDD não fornece URLs reais.
- Não foram criadas tabelas `clubs`, Fellowship, Calendar, Discord ou renderer visual adicional não especificado.

## Testes executados com sucesso

1. `npm test --prefix scripts/security-smoke` — security-smoke, regras de negócio, migration parcial de quiz, `chosen_idx=-1`, retry idempotente/conflito, votação, reminders, newsletter, Stripe e matching: **passou**.
2. `bash scripts/replay-local.sh --reduced` — replay PGlite descartável, overlay histórico, stats/snapshot alinhados e `sdd_contract.test.sql`: **passou**.
3. `pglast` em `supabase/**/*.sql` — **75/75 arquivos parseados**.
4. `deno task --config supabase/functions/deno.json check` — Edge Functions + teste shared: **passou**.
5. `deno task --config supabase/functions/deno.json lint` — **14 arquivos verificados**.
6. `deno task --config supabase/functions/deno.json fmt:check` — **14 arquivos verificados**.
7. `deno task --config supabase/functions/deno.json test` — UUID canônica aceita e formatos inválidos rejeitados: **2/2 passaram**.
8. Harness `scripts/integration-smoke`: check/lint/format: **passou**.
9. Typecheck temporário de `src/lib/supabase`, `src/components` e `src/types` com TypeScript/React/Next/Supabase instalados em `/tmp`: **passou**.
10. OpenAPI com PyYAML e assertions de UUID, quiz parcial e status de card: **passou**.
11. `git diff --check`: **passou**.

## Gates que permanecem honestamente pendentes

- O replay full não foi executado porque o sandbox não tem daemon Docker; o runner informa esse bloqueio depois de selecionar a CLI via npx.
- Não houve sessão Auth real, A/B RLS, upload/assinatura Storage real, WebSocket Realtime, `functions serve` com JWT, provider OpenAI/Resend/Stripe, EXPLAIN com volume representativo, backup/restore ou monitoramento.
- As cinco migrations locais novas ainda não foram aplicadas ao remoto porque a versão remota `20261009162640_close_sdd_backend_contract_gaps` não existe no clone e o baseline possui versões agregadas/renumeradas. Comparar SQL/manifestos antes de qualquer push é obrigatório.
- As versões remotas `ACTIVE` de Edge Functions foram apenas inventariadas; o working tree local não foi redeployado.

Esses gates são limitações de ambiente/dados/autorização, não falhas silenciosas tratadas como aceite. A reconciliação e os comandos de staging estão documentados em `docs/execution/reconciliation.md`, `deployment-status.md` e `implementation-blockers.md`.
