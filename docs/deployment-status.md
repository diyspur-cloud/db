# Estado de deployment e auditoria Supabase

**Snapshot:** 2026-10-09, UTC−03:00 (catálogo consultado após a migration).
**Projeto:** `xjhehhfhhoomblcggjpk` — [Dashboard](https://supabase.com/dashboard/project/xjhehhfhhoomblcggjpk)
**Repositório:** [`diyspur-cloud/db`](https://github.com/diyspur-cloud/db), clone local na branch `main`, commit auditado `ce0355e19e9c45e915cb8d376efa3e0ced1da773`.
**Estado remoto:** histórico consultado contém 51 migrations e a versão mais recente é `20261009162640_close_sdd_backend_contract_gaps`; o inventário de Edge Functions contém 11 funções `ACTIVE`.
**Alterações desta execução:** cinco migrations incrementais geradas pela CLI, handlers corrigidos, adapters frontend e documentação. Tudo permanece local; não houve `db push`, deploy de functions, reset remoto ou DML remoto.
**Escopo:** UUID canônica, snapshot comunitário, overview/metas/snapshot de leitura, quiz parcial, paginação de reminders, consumidores Storage/Realtime/RPCs e reconciliação documental.
**Não feito:** aplicação remota das cinco migrations novas, providers OAuth, mapping de preços Stripe, secrets/URLs de conteúdo, criação de branch, backup/restore point nesta rodada.

> **Estado:** as migrations novas não constam no histórico remoto desta execução. O catálogo remoto confirma 11 handlers `ACTIVE`, mas as versões hospedadas não são automaticamente iguais ao working tree local. Não declarar integração end-to-end, sincronização de fonte nem aplicação remota das migrations sem o gate de reconciliação.

## 1. Catálogo remoto depois da aplicação

| Item | Valor pós-migration | Evidência/observação |
|---|---:|---|
| Tabelas públicas | 77 | Inclui `reading_journal_likes`. |
| Tabelas públicas com RLS | 77/77 | RLS conferida no catálogo. |
| Policies públicas | 158 | 3 novas policies de likes do diário adicionadas ao estado anterior. |
| FKs públicas | 132 | Duas novas FKs na tabela de likes. |
| Índices | 225 `public` + 8 `private` | Inclui novos índices de idempotência/lookup. |
| Views comuns públicas | 12 | As 12 estão configuradas `security_invoker=true`. |
| Materialized views | 1 | `private.mv_book_community_stats`. |
| ENUMs públicos | 30 | Sem alteração desta migration. |
| Triggers de aplicação públicos | 17 | Contadores/estatísticas e timestamps calculados no banco. |
| Tabelas em `supabase_realtime` | 15 | Publicação preexistente preservada. |
| Buckets Storage | 10 | Inclui `feed-media` privado e outras policies existentes. |
| Histórico remoto | 51 migrations | 24 entradas históricas `sdd_*`, 26 incrementais e `20261009162640_close_sdd_backend_contract_gaps`. |
| `SECURITY DEFINER` em schema `private` | 16 | Helpers internos; o schema `private` não está exposto na Data API. |
| Edge Functions remotas | 11 `ACTIVE` | `list_edge_functions` confirmou `award-xp`, `quiz-validate`, `vote-next-book`, `scheduled-reminders`, recomendações/embeddings, matching, newsletter, Stripe, social card e embeddings de livros. |

O remote usa PostgreSQL 17 (`server_version_num` consultado; `supabase/config.toml` local adota `major_version = 17`). A documentação do CLI recomenda alinhar `major_version` à versão principal real: [Supabase CLI config](https://supabase.com/docs/guides/local-development/cli/config).

## 2. Estado SQL remoto e alterações locais

O catálogo remoto confirma a migration histórica `20261009020600` e as correções posteriores, incluindo `20261009162640_close_sdd_backend_contract_gaps`. Esses objetos são evidência do estado hospedado, não aplicação das cinco migrations novas desta execução. O working tree local contém as migrations incrementais geradas pela CLI e os adapters/handlers revisados; a fonte remota e o source local ainda precisam ser comparados antes de qualquer push.

### Regras e objetos adicionados/alterados

1. **XP:** índice único parcial sobre evento `(user_id, source, ref_id)` não nulo e `award_xp` idempotente; XP aceita somente valor positivo, atualiza saldo/temporada sem creditar duas vezes. `EXECUTE` de clientes foi revogado, concedido apenas a `service_role`.
2. **Médias de quiz:** triggers AFTER `INSERT/UPDATE/DELETE` recalculam médias por usuário/capítulo e lidam com mudança de owner/capítulo ou remoção da última tentativa. Helpers privilegidados residem em `private` com grants revogados.
3. **Metas/progresso:** recomputação para capítulos/livros e diário; livro completo exige todos os capítulos cadastrados. `finished_at` passa a acompanhar a transição para status `read`. Progresso percentual/status permanece informação autodeclarada, não fronteira de segurança.
4. **`v_user_reading_overview`:** agrega progresso por livro e diário em CTEs separadas para evitar multiplicação de contagens/minutos; view `security_invoker`.
5. **`reading_journal_likes`:** tabela nova (PK `entry_id,user_id`), RLS e grants mínimos; trigger em função `private` mantém `reading_journal_entries.likes_count`, sem escrita direta do contador pelo cliente.
6. **Enquetes:** valida opção e janela aberta; triggers mantêm contagens em inserção/troca/remoção. A migration sincroniza `book_poll_options.votes_count` com votos existentes.
7. **Quiz:** `private.quiz_rate_limits` e RPC transacional para limite por user/chapter; `record_quiz_attempt` usa `p_request_id` para idempotência e grava tentativa. Chamador Edge Function deve autenticar e verificar capítulo publicado.
8. **Reminders:** ledger privado e RPC `deliver_meeting_reminder` deduplicam por pessoa/reunião/janela sob concorrência.
9. **Newsletter:** leases por edição/audiência e RPCs de claim/finalização; retries parciais não reenviam recipients já registrados como enviados.
10. **Stripe:** mapeamento de customers e RPC transacional de aplicação do evento com ID único para replay seguro e sincronização de assinatura.
11. **Overlaps:** RPC retorna interseções reais de livros/moods sem projetar snapshot privado/embeddings.

### DML e conservação de dados

Nenhuma tabela, coluna ou linha foi apagada pela migration nova. O DML de reconciliação desta migration recalcula contadores de votos das opções com base nas linhas de voto. Nenhuma conta Auth, perfil de usuário ou dado demonstrativo foi criado. A alteração anterior de `comments.min_percent` para linhas legadas nulas (spoilers = 100; não-spoilers = 0) permanece documentada no histórico; não foi repetida nesta migration.

Não foi criado backup/restore point manual antes da rodada. Para mudanças estruturais futuras, criar um ponto de restauração verificável e preferir ambiente isolado.

## 3. Advisors finais

### Segurança

O estado pós-migration manteve **5 findings `extension_in_public`**: `vector`, `pg_trgm`, `citext`, `unaccent`, `btree_gin`. O catalog result e a auditoria anterior não apontavam SECURITY DEFINER exposto na API pública. Helpers que precisam de privilégio estão em `private`, têm `search_path` explícito e grants de chamada restringidos. Não foi movida nenhuma extensão nesta rodada.

### Performance

- **113** findings `unused_index`: uso zero no período medido não demonstra que o índice é dispensável; conservar constraints/FKs e medir com tráfego representativo antes de remover.
- **165** findings `multiple_permissive_policies`: achados por combinação role/comando do modelo de policies amplo, não 165 tabelas; as policies de likes inseridas nesta migration são separadas por comando.
- Nenhum finding `duplicate_index` foi apresentado no resultado pós-migration previamente conferido.

## 4. Edge Functions e entrega

Fonte local presente para 11 nomes: `award-xp`, `vote-next-book`, `scheduled-reminders`, `ai-recommendations`, `ai-user-embeddings`, `match-readers`, `newsletter-dispatch`, `stripe-webhook`, `social-render-card`, `quiz-validate` e `generate-book-embeddings`. O código usa identidade derivada de JWT, papel Admin consultado no banco ou autenticação de serviço/assinatura Stripe conforme o endpoint. Veja [`edge-functions-authorization.md`](./edge-functions-authorization.md).

**O remoto já possui 11 funções `ACTIVE`**, confirmadas por `list_edge_functions`, com versões hospedadas independentes do working tree local. Nesta execução nenhuma foi redeployada. Não foram fornecidos secrets de provedores para registro. Não inferimos, imprimimos nem sobrescrevemos secrets de runtime Supabase. O workflow manual [`deploy-edge-functions.yml`](../.github/workflows/deploy-edge-functions.yml) exige:

- `SUPABASE_ACCESS_TOKEN` como GitHub secret e `SUPABASE_PROJECT_REF` como repository variable;
- project ref explicitamente digitado igual à variável;
- names existentes no Supabase para `OPENAI_API_KEY`, `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `SCHEDULED_REMINDERS_SECRET`;
- ambiente GitHub `production` configurado com reviewers obrigatórios (a configuração de reviewers não foi alterada pela execução).

O workflow executa de novo SQL parser, PGlite e validação Deno; o job só publica código no branch `main`, por `workflow_dispatch` manual, sem deploy automático por push/merge. Não aplica migrations.

## 5. Testes executados e não executados

### Executados, com resultado aprovado

| Verificação | Resultado |
|---|---|
| `pglast` em SQL de `supabase/` | 75/75 arquivos parseados; zero erros. |
| PGlite RLS e smoke anterior | Passou. |
| PGlite `business-rules.mjs` | Passou para regras XP, quiz, metas, likes, polls, reminders, newsletter, Stripe e matching. |
| Deno `check` das 11 funções + teste shared | Passou com Deno 2.9.7. |
| Deno `lint` das funções + teste shared | Passou. |
| Deno `fmt:check` das funções + teste shared | Passou. |
| Deno `test _shared/auth.test.ts` | 2/2 passaram: seed UUID aceita; formatos inválidos rejeitados. |
| `deno check` do `database.types.ts` remoto | Passou. |
| Check/lint/format do harness Auth/Storage/Realtime | Passou. |
| Replay reduzido `scripts/replay-local.sh --reduced` | Passou: overlay histórico, stats/snapshot alinhados e `sdd_contract.test.sql`; não é full reset. |
| TypeScript temporário dos adapters/React | Passou com `typescript`, React, Next e clientes Supabase instalados em `/tmp`; nenhuma dependência foi gravada no repositório. |
| OpenAPI YAML + assertions de contrato | Passou: UUID canônica, quiz parcial e status de card. |
| `git diff --check` | Passou sem whitespace errors. |
| Supabase MCP | Consultas read-only de migrations, Edge Functions e advisors confirmadas; nenhuma migration/deploy foi aplicada nesta execução. |

Os testes PGlite são testes reproduzíveis do SQL em Postgres WASM; não executam JWT Auth real, Data API hospedada, Storage service ou WebSocket Realtime.

### Não executados — não tratar como sucesso

1. Integração mutante Auth/Storage/Realtime real: deliberadamente não executada em produção.
2. Testes com contas reais de titular/admin, admin newsletter, provider Stripe/Resend/OpenAI ou resposta de webhooks: exigem staging e secrets.
3. Replay full com Docker/Supabase local: Docker não está disponível no sandbox; o runner full não foi declarado como aprovado.
4. Redeploy das versões locais, monitoramento de logs e cron HTTP de reminders: o remoto tem funções ativas, mas esta execução não publicou o working tree nem validou efeitos de negócio.
5. `supabase db push`/reconciliação do baseline: não executado devido ao histórico remoto `sdd_*`, aos increments renumerados e a `20261009162640_close_sdd_backend_contract_gaps` não presente no clone.

`scripts/integration-smoke/test.ts` recusa o ref de produção, exige `SUPABASE_TEST_ALLOW_MUTATIONS=true` e apaga dados temporários em `finally`. A branch Supabase proposta foi recusada por custo recorrente de US$ 0,01344/h. O procedimento documentado está em [`scripts/integration-smoke/README.md`](../scripts/integration-smoke/README.md).

## 6. Estado de GitHub / CI

- Fonte modificada localmente na branch `main`; alterações aguardam commit/revisão e CI antes de publicação.
- [`ci.yml`](../.github/workflows/ci.yml) valida SQL, PGlite, types, Deno e checks estáticos do harness sem acessar Supabase secrets.
- Não existem actions que façam `db push`, gravem secrets, executem testes mutantes automaticamente ou deployem functions em todo push.
- Os arquivos públicos foram varridos para padrões típicos de chave publishable/secret, token Stripe live e webhook secret; nenhum literal desses formatos foi encontrado.

## 7. Migrations CLI e operação futura

O histórico remoto tem 24 versões históricas agregadas `sdd_*`, 26 versões complementares numeradas e `20261009162640_close_sdd_backend_contract_gaps`. O conjunto local baseline é granular `20260101…` e não corresponde diretamente aos nomes já aplicados; um `supabase migration list` que compare essas fontes mostra drift real. As cinco migrations novas desta execução ainda não foram registradas remotamente e não devem ser empurradas até comparar a versão `close_sdd_backend_contract_gaps`.

Até produzir e revisar um plano de baseline/repair isolado:

- não execute `supabase db push`, `supabase migration up` ou `supabase db reset` contra o projeto;
- não reaplique `supabase/deploy-bundles/`;
- não edite linhas históricas à mão na tabela interna `supabase_migrations.schema_migrations`;
- gere restore point antes de novas mudanças estruturais.

## 8. Referências e arquivos relacionados

- [README raiz](../README.md) — guia consolidado, comandos, riscos e passos de release.
- [SDD](../SDDBD2.md) — contrato de domínio atualizado e distinção entre progresso informativo e autorização.
- [Plano de implementação](./implementation-plan.md).
- [Contrato de autorização](./edge-functions-authorization.md).
- [Bloqueios e decisões](./implementation-blockers.md).
- [Auditoria SQL read-only](../supabase/security-audit.sql).
- [Documentação oficial de configuração CLI](https://supabase.com/docs/guides/local-development/cli/config).
