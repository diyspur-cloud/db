# DIYSPUR — backend Supabase do clube de leitura

Repositório do backend do DIYSPUR: schema PostgreSQL, migrations, RLS, Supabase Edge Functions, contratos de API, adapters de acesso a dados e harnesses de teste. A especificação original do produto está em [`SDDBD2.md`](./SDDBD2.md). O SDD de execução vinculante foi compartilhado no workspace do projeto (não faz parte deste clone); seus resultados e limites estão sintetizados no relatório versionado [`docs/execution/SDD-EXECUTION-20261009.md`](./docs/execution/SDD-EXECUTION-20261009.md).

> **Status em 09/10/2026:** os itens de implementação local cobertos nesta rodada foram codificados e passaram pelos testes indicados abaixo. **O SDD não está integralmente aceito.** Permanecem gates que dependem de Docker, staging com usuários reais, providers e dados externos, validação de efeitos de negócio, reconciliação do histórico e capacidades operacionais. O código local desta rodada não foi aplicado ao Supabase nem redeployado.

## Índice

1. [Escopo e estado de conclusão](#1-escopo-e-estado-de-conclusão)
2. [Arquitetura e segurança](#2-arquitetura-e-segurança)
3. [O que foi implementado nesta rodada](#3-o-que-foi-implementado-nesta-rodada)
4. [Matriz de validação do SDD](#4-matriz-de-validação-do-sdd)
5. [Migrations e relação com o Supabase remoto](#5-migrations-e-relação-com-o-supabase-remoto)
6. [Edge Functions](#6-edge-functions)
7. [Adapters e contratos de aplicação](#7-adapters-e-contratos-de-aplicação)
8. [Seeds e replay local](#8-seeds-e-replay-local)
9. [Como testar](#9-como-testar)
10. [Deploy e configuração externa](#10-deploy-e-configuração-externa)
11. [Pendências, limites e decisões preservadas](#11-pendências-limites-e-decisões-preservadas)
12. [Mapa de documentação](#12-mapa-de-documentação)

## 1. Escopo e estado de conclusão

| Recurso | Referência |
|---|---|
| Repositório | [github.com/diyspur-cloud/db](https://github.com/diyspur-cloud/db) |
| Projeto Supabase consultado | `xjhehhfhhoomblcggjpk` |
| Endpoint Supabase | `https://xjhehhfhhoomblcggjpk.supabase.co` |
| Schema original | [`SDDBD2.md`](./SDDBD2.md) |
| Relatório do SDD | [`docs/execution/SDD-EXECUTION-20261009.md`](./docs/execution/SDD-EXECUTION-20261009.md) |
| OpenAPI | [`docs/openapi.yaml`](./docs/openapi.yaml) |
| Status de execução | [`docs/execution/SDD-EXECUTION-20261009.md`](./docs/execution/SDD-EXECUTION-20261009.md) |

A execução atual fez mudanças no repositório e consultas remotas **read-only** para reconciliação. No momento da consulta, o catálogo remoto continha 51 versões de migration e 11 Edge Functions `ACTIVE`. Isso não demonstra que o source local seja igual às versões hospedadas.

### Estados usados neste README

- **Implementado em arquivos:** o código, migration ou documento está no working tree.
- **Testado localmente:** um teste reproduzível desta rodada cobre o comportamento, com o limite do harness declarado.
- **Aplicado no remoto:** migration ou função foi enviada ao projeto Supabase e há evidência de catálogo/execução.
- **Aceito end-to-end:** o fluxo foi executado no ambiente correspondente com identidade, dados e efeitos verificados.

Esses estados são diferentes. Em particular, uma função `ACTIVE`, o parse de SQL ou um teste PGlite não equivalem a aceite end-to-end.

## 2. Arquitetura e segurança

```text
Aplicação consumidora (não há aplicação Next completa neste repositório)
  ├─ Supabase Auth → sessão/JWT
  ├─ Data API → grants mínimos + RLS + views security_invoker
  ├─ Storage → policy de ownership/visibilidade + URL assinada
  └─ Edge Functions → JWT, segredo interno ou assinatura de webhook
                       └─ RPCs transacionais/privadas
PostgreSQL
  ├─ public: tabelas e API/views autorizadas
  ├─ private: projeções, helpers e mecanismos internos
  ├─ triggers: XP, contadores, metas e manutenção de estado
  └─ pg_cron/Vault/pg_net: tarefas agendadas existentes
```

Princípios que devem ser mantidos:

- Nunca usar a chave publishable como credencial administrativa; nunca colocar `service_role` ou secrets de provider no cliente ou no Git.
- Derivar a identidade do JWT validado, não de `user_id` informado pelo browser.
- Não calcular score de quiz, XP, papel de admin ou contadores no cliente.
- Manter RLS, grants de coluna e policies de ownership. Views de leitura pública devem usar `security_invoker` quando o contrato exigir.
- Preservar Storage privado e assinar URLs temporárias após autorização; não converter path privado em URL pública.
- Não editar migrations já aplicadas para aparentar que o remoto mudou. Criar correção incremental e reconciliar antes de qualquer push ao banco.
- Proteger payloads de spoiler, conteúdo de comentário, PII, resposta correta de quiz e estado administrativo.

## 3. O que foi implementado nesta rodada

### Banco e migrations locais

Foram criadas cinco migrations incrementais locais:

| Migration | Intenção |
|---|---|
| `20261009170633_align_community_stats_snapshot.sql` | Recriar snapshot de estatísticas e aliases públicos protegidos. |
| `20261009170637_align_user_reading_overview_contract.sql` | Alinhar o overview à contagem literal por capítulos, separando agregação do diário. |
| `20261009170642_align_reading_goal_calculation.sql` | Ajustar o cálculo anual no helper privado de metas. |
| `20261009170647_align_reading_snapshot_keys.sql` | Emitir as chaves `title`, `moods`, `pace`, `rating`, `review`. |
| `20261009170651_allow_partial_quiz_answers.sql` | Permitir `chosen_idx = -1` e manter validação transacional/server-side. |

Elas passaram pelo parser SQL; contratos de stats/snapshot também passam pelo replay reduzido; a migração de quiz parcial foi aplicada no smoke PGlite e testada com resposta ausente, retry e conflito. Isso **não substitui replay full** nem significa que essas migrations estejam aplicadas ao Supabase.

### Edge Functions e backend compartilhado

- `_shared/auth.ts`: UUID canônica 8-4-4-4-12 aceita o ID do seed sem validar versão/variante RFC; teste unitário cobre positivo e entradas malformadas.
- `quiz-validate`: aceita respostas parciais, normaliza ausentes para `-1`, calcula score no servidor e mantém chave de idempotência.
- `scheduled-reminders`: tamanho de página reduzido a 500 para ficar abaixo do `max_rows=1000` configurado.
- `stripe-webhook`: valida UUID local também no contrato de seed.
- `_shared/supabaseAdmin.ts` e `_shared/types.ts`: compatibilidade estrutural por reexport/tipo; não criam um segundo cliente privilegiado.

### Adapters e consumidor parcial

Foram adicionados adapters em `src/lib/supabase/` para atividades, clubes, gamificação/votos, mídia, perfil, quiz, leitura, Realtime, social/matches e stats. Também existe `src/components/reading/SocialCard.tsx` para exibir o estado do job e imagem retornada.

Esses arquivos são **camada de integração**, não uma aplicação web completa: o repositório não tem manifest de aplicação Next, rotas, telas de Auth, páginas para os fluxos do roadmap ou processo de build da UI. O helper Realtime provê assinatura genérica e conveniências para comentários/notificações; assinaturas e reconciliação em todas as telas ainda exigem consumidores e teste WebSocket real.

### Contratos e documentação

`docs/openapi.yaml` foi atualizado para UUID, quiz parcial, newsletter e retorno de card conforme handler. Documentos de autorização, deployment, blockers, plano e reconciliação foram atualizados para distinguir estado local, remoto e histórico.

## 4. Matriz de validação do SDD

| Requisito/tema do SDD | Estado nesta entrega | O que falta para aceite |
|---|---|---|
| UUID canônica do seed (§6.1) | **Implementado e testado** no handler compartilhado. | POST autenticado em ambiente controlado com atividade real de `finish_book`. |
| Stats comunitárias (§3.2) | **Migration local + teste de sintaxe/replay reduzido.** | Replay full, refresh antes/depois e validação remota da consistência temporal/snapshot. API pública continua view; MV permanece privada. |
| Overview por capítulo (§3.3) | **Migration local implementada.** | Replay full e teste completo dos casos de dois capítulos, diário, DNF e temporadas em PostgreSQL real. |
| Cálculo anual de metas (§3.4) | **Migration local implementada.** | Replay full e casos de ano anterior, timestamps nulos e edição/exclusão; aceite de negócio do significado de `books_done`. |
| Snapshot do leitor (§3.6) | **Migration local implementada.** | Replay full, comparações de payload e efeito em embeddings/consumidores reais. |
| Filtro de temporada de clube (§3.5) | **Decisão: manter filtro da temporada corrente**, em vez de removê-lo. Smoke PGlite já diferencia duas temporadas. | Aceite de produto para a semântica; teste multiusuário de clube privado em ambiente real. |
| Quiz parcial (§6.2) | **Implementado e coberto** em PGlite: `-1`, idempotência e conflito. | Integração HTTP autenticada, teste de pergunta estrangeira e aceite dos limites adicionais de 50 perguntas/10 por minuto. Quiz vazio segue limitado por `total > 0`. |
| Paginação reminders (§6.4) | **Correção local implementada** e lint/typecheck da função aprovados. | Volume >1 página e reunião/RSVP reais em staging; validar deduplicação e resultado da notificação. |
| OAuth e sessão (§2.1) | **Pendente.** | Habilitar Google/GitHub no Supabase com credenciais do responsável e URL real; implementar fluxo de app e testar password/Magic Link/OAuth/refresh/logout. |
| RLS/matriz A/B (§4, §9.2) | Adapters/leitura segura presentes; smoke PGlite cobre parte das policies. | Duas ou mais sessões reais, leitor/admin/anon e ownership cruzado em staging. |
| Storage (§5) | Adapter para upload próprio e URL assinada; verificação de extra no código. | Testar upload/read/update, caminhos alheios, extra privado/público e buckets com sessão real. |
| Realtime (§5.3) | Helper genérico com filtro, status e cleanup; tipos incluem tabelas do SDD. | Integrar em telas, exercitar INSERT/UPDATE/DELETE, reconnect e duas sessões; provar ausência de conteúdo proibido. |
| Consumers e OpenAPI (§8) | Adapters TypeScript e contratos ajustados; typecheck temporário dos adapters passou. | Implementação da aplicação/telas, compatibilidade de produto e teste por contrato HTTP real. |
| IA e matching (§6.5–6.7) | Handlers e adapter existem; compilações estáticas passaram. | Secret autorizado, embeddings reais dos livros, inferência controlada e comportamento/cache com sessão. |
| Newsletter (§6.8) | Handler/contrato existentes; testes PGlite de lease/idempotência. | Remetente verificado, provider autorizado e envio controlado explicitamente aprovado; não houve envio nesta rodada. |
| Stripe (§6.9) | Handler/RPCs cobertos por smoke SQL; chave/assinatura e mapeamento mantidos fora de código. | IDs reais `stripe_price_id`, eventos sandbox com identidade/assinatura e aceite de status/períodos. Nenhum preço foi inventado. |
| Social card (§6.10) | Adapter e componente de estado implementados; OpenAPI descreve retorno renderizado. | UI completa, consulta/reabertura de job, validação de imagem/ownership e integração hospedada. |
| Shared files/documentação (§6.11) | Reexports criados; afirmações obsoletas revisadas. | Deploy da fonte local e POST autenticado em ambiente seguro. |
| Dados de conteúdo (§7.1–7.3) | Nenhuma URL ou conteúdo inventado. | URLs reais de vídeos/materiais; objetivos/prompts editoriais; resolver inconsistência do crossword com decisão de produto. |
| Replay full e seeds (§1.1, §7.4) | Runner implementado para cópia descartável e duas cargas explícitas; seed-check criado. Replay reduzido passou. | **Pendente:** full bloqueado pela ausência de Docker. O replay temporário ainda aplica correção conhecida numa cópia do baseline; não satisfaz o critério de reset full sem overlay implícito. |
| Reconciliação de histórico (§1.2, §9.1) | Correspondências e hashes documentados; remoto não foi alterado. | Reconciliar bundles `sdd_*`, timestamps renumerados e `20261009162640_close_sdd_backend_contract_gaps`; não executar `db push` até concluir. |
| EXPLAIN/carga (§9.2) | Nenhuma conclusão de escala foi declarada. | Testar com volume representativo, `EXPLAIN ANALYZE`/BUFFERS. |
| Backup/restore/monitoramento (§9.2) | Não demonstrado nesta rodada. | Verificar backup disponível, ponto restaurável, exercício de restore e alertas. |

**Conclusão da validação:** há implementação substancial em arquivos e testes locais para itens de código definidos no SDD, mas **nem todos os itens foram implementados/aceitos**. Alguns dependem de escolha/dados/credenciais externas; outros, como aplicação/telas completas e replay full, continuam pendentes. O relatório de execução separa resultado de teste e bloqueio.

## 5. Migrations e relação com o Supabase remoto

As cinco migrations desta rodada estão no working tree local e **não foram aplicadas remotamente**. A consulta read-only mais recente reportada encontrou 51 migrations: 24 históricas `sdd_*`, 26 incrementais e `20261009162640_close_sdd_backend_contract_gaps`. A árvore clonada não contém essa última versão e os timestamps/nome lógico de várias aplicações diferem entre remoto e arquivo local.

Antes de qualquer operação de banco remoto:

1. comparar migrations por SQL/manifesto/hash;
2. identificar mudanças que já foram aplicadas sob outro timestamp;
3. validar o replay em staging ou ambiente descartável;
4. revisar backups e impacto;
5. só então preparar uma operação explícita de migration.

**Não rode** `supabase db push`, `migration repair`, `db reset --linked` ou bundles contra o projeto conectado para “sincronizar” timestamps.

A reconciliação detalhada está em [`docs/execution/reconciliation.md`](./docs/execution/reconciliation.md); o estado/limitações em [`docs/deployment-status.md`](./docs/deployment-status.md) e [`docs/implementation-blockers.md`](./docs/implementation-blockers.md).

## 6. Edge Functions

As fontes Deno estão em `supabase/functions/` e incluem:

| Função | Autorização esperada | Uso |
|---|---|---|
| `quiz-validate` | JWT validado | Validar respostas e registrar tentativa/XP no servidor. |
| `award-xp` | JWT + prova de atividade | Pontos por atividade e bônus diário elegível. |
| `vote-next-book` | JWT validado | Voto transacional em enquete aberta. |
| `scheduled-reminders` | Segredo interno | Processar RSVP/reuniões dentro da janela. |
| `ai-recommendations` | JWT validado | Recomendação pessoal; depende de provedor/embedding. |
| `ai-user-embeddings` | JWT + ownership | Gerar embedding pessoal, sujeito a limite. |
| `match-readers` | JWT + ownership | Busca de leitores e cache pessoal. |
| `newsletter-dispatch` | JWT + perfil admin | Envio administrativo; depende de configuração real do remetente. |
| `stripe-webhook` | Assinatura Stripe | Aplicar eventos de assinatura/idempotência. |
| `social-render-card` | JWT + ownership | Criar/renderizar job conforme contrato existente. |
| `generate-book-embeddings` | Administrativa | Fonte adicional; não confundir com endpoint consumidor. |

O inventário remoto confirmou funções `ACTIVE`, mas **não houve redeploy do working tree desta execução**. `ACTIVE` não garante que a versão hospedada inclua as mudanças locais nem que o provider esteja funcional. Consulte [`docs/edge-functions-authorization.md`](./docs/edge-functions-authorization.md) antes de operar.

## 7. Adapters e contratos de aplicação

Os adapters consultam superfícies autorizadas e devem continuar sujeitos a RLS. Não selecionam diretamente gabaritos/PII nem devem calcular campos privilegiados. Arquivos adicionados:

- `src/lib/supabase/profile.ts`
- `src/lib/supabase/reading.ts`
- `src/lib/supabase/quiz.ts`
- `src/lib/supabase/media.ts`
- `src/lib/supabase/realtime.ts`
- `src/lib/supabase/clubs.ts`
- `src/lib/supabase/stats.ts`
- `src/lib/supabase/gamification.ts`
- `src/lib/supabase/social.ts`
- `src/lib/supabase/activities.ts`
- `src/components/reading/SocialCard.tsx`

A validação TypeScript dos adapters foi feita num diretório temporário com React, Next e dependências Supabase; não há `package.json` de aplicação no repositório. A existência desses módulos **não representa um website executável**.

## 8. Seeds e replay local

`supabase/config.toml` define seeds locais. `scripts/replay-local.seed-check.sql` verifica os registros de seed esperados após duas cargas explícitas. O runner possui modos distintos:

- `bash scripts/replay-local.sh --reduced`: PGlite/fixture simplificado; útil para contrato local, mas **não** valida todas as migrations, extensões, Auth, Storage ou serviços Supabase.
- `bash scripts/replay-local.sh --full`: tenta executar uma stack Supabase local descartável, com migrations e dupla carga de seeds. Requer CLI Supabase, Docker acessível e recursos locais suficientes.

Na execução desta rodada, o reduzido passou. O full foi invocado, mas parou porque não há daemon Docker acessível. Portanto o critério de replay total permanece aberto.

## 9. Como testar

Requisitos aproximados: Node 22+, Deno 2, Python 3.11+; Supabase CLI e Docker apenas para replay full. Execute a partir da raiz do clone.

```bash
# PGlite: policies, regras e migração de quiz parcial
npm ci --prefix scripts/security-smoke
npm test --prefix scripts/security-smoke

# Sintaxe SQL de migrations, testes e seeds
python3 -m pip install pglast PyYAML
python3 - <<'PY'
from pathlib import Path
from pglast import parse_sql
files = sorted(Path('supabase').rglob('*.sql'))
for path in files:
    parse_sql(path.read_text())
print(f'{len(files)} arquivos SQL parseados')
PY

# Edge Functions + teste unitário de UUID
deno task --config supabase/functions/deno.json check
deno task --config supabase/functions/deno.json lint
deno task --config supabase/functions/deno.json fmt:check
deno task --config supabase/functions/deno.json test

# Harness de integração (somente estático até configurar staging)
deno task --config scripts/integration-smoke/deno.json check
deno task --config scripts/integration-smoke/deno.json lint
deno task --config scripts/integration-smoke/deno.json fmt:check

# Replay reduzido / full descartável
bash scripts/replay-local.sh --reduced
bash scripts/replay-local.sh --full

git diff --check
```

**Não aponte o harness mutante para produção.** O smoke de integração exige configuração explícita e protege contra o project ref de produção; mantenha esse guard.

### Resultados reportados para esta rodada

- `scripts/security-smoke`: passou, incluindo migração de quiz parcial, resposta `-1`, retry idempotente e conflito.
- Replay reduzido: passou.
- Parser SQL: 75/75 arquivos passaram.
- Deno check/lint/format: passaram; 2 testes unitários de UUID passaram.
- OpenAPI YAML: parse e assertions de UUID/quiz passaram.
- Harness de integração: check/lint/format estáticos passaram.
- Typecheck temporário dos adapters: passou.
- Replay full, OAuth real, matriz RLS A/B real, Storage/Realtime hospedados, inferência externa, Stripe/Resend com efeitos de negócio e backup/restore: **não aprovados**.

Consulte o relatório para comandos/resultados e limites: [`docs/execution/SDD-EXECUTION-20261009.md`](./docs/execution/SDD-EXECUTION-20261009.md).

## 10. Deploy e configuração externa

Há versões remotas `ACTIVE`, porém o código local não foi redeployado nesta rodada. Deploy de Edge Functions é separado de migrations e não reconcilia o schema automaticamente. Antes de publicar, revisar código/lockfile, nome de projeto, `verify_jwt`, secrets requeridos e proteção de ambiente.

Nomes de configuração citados pelo código/documentação incluem `SUPABASE_URL`, chaves de sistema fornecidas pelo runtime, `SCHEDULED_REMINDERS_SECRET`, `OPENAI_API_KEY`, `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, `STRIPE_SECRET_KEY` e `STRIPE_WEBHOOK_SECRET`. Não exponha valores no README, commits ou logs. O relatório não afirma inventário de secrets hospedados nesta execução.

### Providers e dados externos pendentes

- Google e GitHub OAuth precisam ser habilitados com credenciais reais e callback/redirect URL da aplicação.
- A aplicação consumidora precisa de Site URL/redirects reais; não há domínio inventado neste repo.
- Resend requer sender/domain autorizado antes de qualquer envio.
- IA depende de secret e embeddings/dados reais; `ACTIVE` não prova inferência.
- Stripe requer IDs `stripe_price_id` reais para planos; nenhum foi criado/fabricado.
- Vídeos e materiais do seed continuam exemplos até o responsável fornecer URLs reais.
- Não houve envio de newsletter, compra, cobrança ou pagamento.

## 11. Pendências, limites e decisões preservadas

1. **Replay full:** requer Docker; não passou nesta execução. Além disso, o runner full mantém correção da falha 42803 em cópia temporária; isso ainda não é aceite do critério “sem overlay implícito”.
2. **Reconciliação:** resolver o baseline remoto `sdd_*`, as versões incrementais renumeradas e `20261009162640_close_sdd_backend_contract_gaps`; não dar push ao banco antes.
3. **Auth/app:** OAuth Google/GitHub, password/Magic Link, callback, refresh, logout e sessões reais não foram implementados/testados numa aplicação, que não existe como app buildável neste clone.
4. **Integrações:** Resend, OpenAI e Stripe exigem configuração/identificadores reais e testes autorizados. Não inventar preços, sender, conteúdo ou resultado.
5. **RLS/Storage/Realtime:** os testes locais não substituem staging com dois usuários, operações de Storage e WebSocket real.
6. **Dados de produto:** metas, prompts e URLs de conteúdo precisam de valores definidos por responsáveis; crossword de exemplo tem configuração incompatível; calendário real não foi inventado.
7. **Performance e operação:** ainda faltam EXPLAIN com carga representativa, prova de backup/restauração e monitoramento.
8. **Requisitos incompletos do anexo:** badge/milestone automation, pontuação de todos os jogos, convite/capacidade buddy read, layout individual dos cards, Discord e Google Calendar não têm especificação suficiente para implementar sem inventar produto.
9. **Semântica mantida:** o filtro de temporada do painel de clube foi mantido por coerência com `current_season_id`; sua eventual remoção requer decisão de produto.
10. **Segurança:** avisos sobre extensões em `public` permanecem documentados; não foram movidas automaticamente por possível impacto em tipos, operadores e índices.

Para decidir se um item fica concluído, exigir implementação versionada, teste no ambiente correspondente, contrato/diferença explicitados e evidência do efeito. Não marcar o TODO inteiro como aceito somente pela existência de tabela, nome de function ou teste sintático.

## 12. Mapa de documentação

| Documento | Conteúdo |
|---|---|
| [`docs/execution/SDD-EXECUTION-20261009.md`](./docs/execution/SDD-EXECUTION-20261009.md) | Implementação, resultados e gates desta rodada. |
| [`docs/deployment-status.md`](./docs/deployment-status.md) | Estado remoto/local e testes reportados. |
| [`docs/implementation-blockers.md`](./docs/implementation-blockers.md) | Bloqueios, decisões e dependências externas. |
| [`docs/implementation-plan.md`](./docs/implementation-plan.md) | Histórico e plano de implementação. |
| [`docs/execution/reconciliation.md`](./docs/execution/reconciliation.md) | Correspondências de migration e limites de push. |
| [`docs/edge-functions-authorization.md`](./docs/edge-functions-authorization.md) | Autorização por handler. |
| [`docs/openapi.yaml`](./docs/openapi.yaml) | Contrato HTTP. |
| [`docs/execution/supabase-sources-20261009.md`](./docs/execution/supabase-sources-20261009.md) | Referências técnicas consultadas. |
| [`src/lib/supabase/README.md`](./src/lib/supabase/README.md) | Adapters e fronteiras de acesso de cliente. |

**Segredos são configuração, não documentação.** Nunca grave tokens, API keys, service-role keys, secrets de webhook ou conteúdo pessoal em README, código, evidências commitadas ou logs públicos.
