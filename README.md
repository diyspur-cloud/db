# Clube de Leitura — banco Supabase

Repositório do backend de dados do **Clube de Leitura**, baseado no desenho [`SDDBD2.md`](./SDDBD2.md). Contém migrations SQL, seeds de desenvolvimento, auditorias, funções Deno, contratos TypeScript, testes locais e workflows GitHub Actions.

> **Estado em 9 de outubro de 2026:** a migration complementar `20261009020600` foi aplicada ao projeto Supabase indicado e confirmada no histórico/catálogo remoto. O schema contém **77 tabelas públicas, todas com RLS**, 158 policies, 132 FKs, 12 views públicas `security_invoker`, 30 ENUMs e 38 migrations registradas. A aplicação de schema e os testes locais terminaram; as Edge Functions **não** foram implantadas. Testes mutantes com Auth/Storage/Realtime reais **não** foram executados: o único projeto conectado é produção e a criação de um branch Supabase foi recusada após a cotação recorrente de US$ 0,01344/h.
>
> **Não confunda código versionado com código em produção.** As alterações de fonte estão no branch `fix/audit-followups` e precisam passar por CI/revisão/merge. A migration do banco foi aplicada separadamente pelo fluxo MCP autorizado; `supabase db push` continua proibido até a reconciliação do baseline histórico.

## 1. Identificação e recursos

| Item | Referência |
|---|---|
| Projeto | Clube de Leitura |
| Repositório GitHub | [`diyspur-cloud/db`](https://github.com/diyspur-cloud/db) |
| Project ref Supabase | `xjhehhfhhoomblcggjpk` |
| Dashboard | [Projeto Supabase](https://supabase.com/dashboard/project/xjhehhfhhoomblcggjpk) |
| Branch de trabalho | `fix/audit-followups` |
| Migration aplicada nesta rodada | versão `20261009020600`, nome remoto `20261009014533_implement_audit_followups` |
| Relatório factual de deployment | [`docs/deployment-status.md`](./docs/deployment-status.md) |
| Plano/aceite e sequência | [`docs/implementation-plan.md`](./docs/implementation-plan.md) |
| Contrato e pré-requisitos de Edge Functions | [`docs/edge-functions-authorization.md`](./docs/edge-functions-authorization.md) |
| Bloqueios e decisões | [`docs/implementation-blockers.md`](./docs/implementation-blockers.md) |
| Referências oficiais Supabase | [`docs/supabase-reference.md`](./docs/supabase-reference.md) |

Este repositório é público. **Não grave credenciais, service-role keys, tokens, segredos de provedores, dados pessoais nem dumps de usuários** em Git, README, issues ou logs. `SUPABASE_PUBLISHABLE_KEY` não é chave administrativa. O material anexado incluía um publishable key; ele não foi copiado para o repositório ou documentação e não deve ser tratado como segredo de deploy.

## 2. Estado do projeto remoto (consultado após a migration)

| Métrica de catálogo | Estado confirmado |
|---|---:|
| Tabelas em `public` | 77 |
| Tabelas públicas com RLS | 77/77 |
| Policies em `public` | 158 |
| Foreign keys em `public` | 132 |
| Índices em `public` / `private` | 225 / 8 (233 no total) |
| Views comuns em `public` | 12; as 12 têm `security_invoker=true` |
| Materialized view | 1, em `private` |
| ENUMs em `public` | 30 |
| Triggers de aplicação em `public` | 17 |
| Tabelas na publicação `supabase_realtime` | 15 |
| Buckets de Storage | 10 |
| Migrations registradas | 38 (24 históricas `sdd_*` + 14 versões complementares) |
| Helpers `SECURITY DEFINER` em `private` | 16; não expostos na Data API |
| Edge Functions implantadas | 0, confirmado pelo inventário remoto |

Os advisors pós-migration continuam reportando **5 avisos de extensão no schema `public`** (`vector`, `pg_trgm`, `citext`, `unaccent`, `btree_gin`), **113 índices sem uso observado** e **165 findings de múltiplas policies permissivas**. O contador de `idx_scan=0` não prova inutilidade; os findings RLS são herdados do modelo amplo de políticas por role/ação. Nenhum desses resultados justifica remoção/refatoração automática. A auditoria final está em [`docs/deployment-status.md`](./docs/deployment-status.md).

## 3. O que foi alterado nesta rodada

### 3.1 Banco e regras de domínio

Migration local: [`supabase/migrations/20261009020600_20261009014533_implement_audit_followups.sql`](./supabase/migrations/20261009020600_20261009014533_implement_audit_followups.sql). Ela foi aplicada pelo fluxo Supabase MCP e a versão `20261009020600` foi consultada no histórico remoto.

- **XP:** unicidade parcial de `(user_id, source, ref_id)` quando `ref_id` não é nulo; `award_xp` valida valores positivos e só credita uma referência uma vez. A distribuição de XP de temporada não é incrementada quando não há temporada ativa; a chamada fica restrita a `service_role`.
- **Médias de quizzes:** recálculo idempotente das médias pessoal e por capítulo após `INSERT`, `UPDATE` ou `DELETE`, cobrindo mudança de usuário/capítulo e remoção da última tentativa.
- **Metas anuais:** recomputação a partir de progresso e diário; livro completo requer todos os capítulos cadastrados, e páginas/minutos/data de conclusão não são contados como livros concluídos. `finished_at` é carimbado pelo banco quando o status muda para `read`.
- **Overview de leitura:** `v_user_reading_overview` agrega progresso por livro antes de juntá-lo ao diário, evitando inflação por múltiplos capítulos/joins. O acesso segue a identidade/RLS da view invoker.
- **Likes do diário:** criada `public.reading_journal_likes` com chave `(entry_id, user_id)`, RLS e policies de titular. Trigger privado ajusta `likes_count`; o cliente não altera o contador diretamente.
- **Enquetes:** valida janela da enquete e opção; o contador é ajustado transacionalmente em inserção/troca/exclusão. As contagens legadas foram reconciliadas com os votos existentes.
- **Quiz:** RPC `record_quiz_attempt` grava uma tentativa idempotente por `request_id`; `private.quiz_rate_limits` aplica limite atômico por usuário/capítulo, e a validação server-side usa capítulos publicados e XP deduplicado.
- **Lembretes:** RPC transacional deduplica por usuário/reunião/janela (`private.sent_reminders`) para impedir duplicação sob concorrência.
- **Newsletter:** lease idempotente por edição/audiência em `private.newsletter_dispatch_runs`; a função pode retomar lotes parciais sem reenviar destinatários já registrados como enviados. O handler exige Admin e usa Resend somente quando secrets estão configurados.
- **Stripe:** `private.stripe_customers` mapeia o customer ao leitor; o RPC idempotente grava o event ID e sincroniza assinatura em transação. Assinatura do webhook é validada sobre o corpo bruto.
- **Matches:** nova RPC de overlaps retorna contagens/interseções reais de livros e moods, sem expor embeddings/snapshot pessoal.

A migration é aditiva; não remove tabelas/colunas ou registros de usuário. Seu DML de reconciliação atualiza contadores de votos de enquete para corresponder às linhas de voto. Nenhum perfil/administrador foi criado e nenhum seed demonstrativo foi aplicado ao projeto remoto.

### 3.2 Edge Functions versionadas (ainda não implantadas)

A fonte foi auditada e validada estaticamente para **11 funções**. Autorização vem do JWT validado pelo Supabase, do papel confiável no banco ou do segredo de serviço conforme a função; dados de entrada não substituem identidade. O acesso privilegiado usa cliente server-side.

| Função | Controles implementados no repositório |
|---|---|
| `award-xp` | Rejeita autoatribuição sem evento comprovado; RPC de XP protegida e idempotente. |
| `vote-next-book` | Deriva usuário do JWT; RPC valida enquete/opção e efetiva o voto atomicamente. |
| `scheduled-reminders` | Exige `SCHEDULED_REMINDERS_SECRET`; RPC idempotente registra a janela de envio. |
| `ai-recommendations` | Snapshot limitado ao usuário autenticado; embedding e erros do provedor verificados. |
| `ai-user-embeddings` | Ownership por JWT e hash SHA-256 do snapshot, sem hash de tamanho. |
| `match-readers` | Usuário calculado a partir do JWT; aplica limit e retorna overlaps permitidos. |
| `newsletter-dispatch` | Admin obrigatório, filtros permitidos, recipient consentido/confirmado, lease e retry idempotentes. |
| `stripe-webhook` | Valida `stripe-signature` do corpo bruto e usa RPC transacional/idempotente. |
| `social-render-card` | Ownership, conteúdo sanitizado, limite e gravação em Storage. |
| `quiz-validate` | JWT, capítulo publicado, rate-limit transacional, chave idempotente e gravação server-side. |
| `generate-book-embeddings` | Função administrativa protegida para preencher vetores do catálogo. |

A presença de arquivos não significa deploy. A lista remota estava vazia. Não foi feito deploy nesta execução, pois secrets de provedores não foram fornecidos para configuração, não se confirmou o runtime remoto, e faltou ambiente isolado para smoke autenticado. Veja [`docs/edge-functions-authorization.md`](./docs/edge-functions-authorization.md).

### 3.3 Código, contratos e pipeline

- Configuração Supabase local aponta ao ref correto e à versão PostgreSQL 17; migration foi renomeada para refletir o versionamento remoto.
- `src/lib/supabase/database.types.ts` (5.262 linhas) foi gerado a partir do schema remoto pós-migration; o arquivo inclui a nova tabela, view e RPCs.
- `supabase/functions/deno.json`/`deno.lock` pinam Deno/NPM dependencies em versões exatas: Supabase JS `2.117.2`, OpenAI `7.30.0`, Resend `6.32.1`, Stripe `23.0.0`.
- `scripts/security-smoke/business-rules.mjs` amplia o conjunto PGlite para regras de negócio da migration.
- `scripts/integration-smoke/` contém harness Auth/Storage/Realtime protegido contra mutações no ref de produção; seu check estático passou, mas execução remota exige staging.
- `.github/workflows/ci.yml` valida SQL, PGlite, tipos, funções Deno e harness de integração estático sem secrets.
- `.github/workflows/deploy-edge-functions.yml` só roda por `workflow_dispatch` e só publica a partir do `main`; repete validações, confere o project ref digitado e a existência dos nomes dos secrets no Supabase antes de deployar as 11 funções. Não faz migrations nem configura valores de secrets.

## 4. Arquivos e organização

```text
.
├── README.md
├── SDDBD2.md
├── .github/workflows/
│   ├── ci.yml
│   └── deploy-edge-functions.yml
├── docs/
│   ├── deployment-status.md
│   ├── implementation-plan.md
│   ├── implementation-blockers.md
│   ├── edge-functions-authorization.md
│   └── supabase-reference.md
├── scripts/
│   ├── build-remote-bundles.py
│   ├── security-smoke/       # PGlite: RLS e regras de negócio
│   └── integration-smoke/    # Auth, Storage, Realtime (somente staging isolado)
├── supabase/
│   ├── config.toml
│   ├── migrations/           # SQL-fonte; blocked/ é arquivo histórico, não executar
│   ├── deploy-bundles/       # bundles de referência/bootstrap, não reaplicar ao remoto
│   ├── functions/            # 11 fontes, helpers e lockfile Deno
│   ├── dev-seeds/            # dados demonstrativos para ambiente descartável
│   └── security-audit.sql    # consultas de auditoria read-only
└── src/
    ├── lib/supabase/database.types.ts
    └── types/                # contratos de domínio TypeScript
```

`supabase/deploy-bundles/` é gerado por `python3 scripts/build-remote-bundles.py` para revisão/bootstrapping. Os bundles concatenam várias migrations antigas e **não** são uma instrução para reaplicar no projeto existente.

## 5. Testes e verificações

### 5.1 Comandos locais sem acesso ao Supabase

Requer Python 3.11+, Node 22+ e Deno 2:

```bash
python3 -m pip install pglast
python3 - <<'PY'
from pathlib import Path
from pglast import parse_sql
files = sorted(Path("supabase").rglob("*.sql"))
for path in files:
    parse_sql(path.read_text())
print(f"Parsed {len(files)} SQL files")
PY

npm ci --prefix scripts/security-smoke
npm test --prefix scripts/security-smoke

deno check src/lib/supabase/database.types.ts
deno task --config supabase/functions/deno.json check
deno task --config supabase/functions/deno.json lint
deno task --config supabase/functions/deno.json fmt:check

deno task --config scripts/integration-smoke/deno.json check
deno task --config scripts/integration-smoke/deno.json lint
deno task --config scripts/integration-smoke/deno.json fmt:check

git diff --check
```

**Resultado desta tarefa:** 57/57 arquivos SQL parseados com `pglast`; suíte `npm test` PGlite passou; typecheck, lint e `fmt:check` de todas as Edge Functions passaram; tipos gerados passaram no `deno check`; o harness Auth/Storage/Realtime passou nos três checks estáticos; `git diff --check` passou antes de empacotar o branch. O workflow CI reproduz esses passos. Nenhum teste `npm`/Deno consulta produção.

### 5.2 O que os testes PGlite exercitam

`npm test --prefix scripts/security-smoke` inclui a suíte de segurança existente e `business-rules.mjs`, que executa fixtures em Postgres WASM: duplicação de XP, médias após mutações, conclusão de livro/metas, timestamp `finished_at`, view agregada, owner-only do like, contadores de enquete e validação de período, limite/idempotência do quiz, lembretes e exclusão concorrente, lease/retry da newsletter, idempotência do evento Stripe e overlaps de livros/moods. Isso cobre SQL/RLS reproduzido localmente; não substitui o runtime Supabase Auth/Realtime/Storage.

### 5.3 Integração real (não executada)

O harness em `scripts/integration-smoke/test.ts` cria duas contas temporárias e um objeto/entrada de diário, testa sessão/refresh, consentimento, PII cruzada, regras de owner do bucket `feed-media` e evento Realtime privado; tenta limpar todas as contas/linhas/objetos em `finally`.

Ele **recusa** o project ref de produção `xjhehhfhhoomblcggjpk`, exige `SUPABASE_TEST_PROJECT_REF` igual ao ref do URL e exige `SUPABASE_TEST_ALLOW_MUTATIONS=true`. Para execução, forneça somente no ambiente protegido as credenciais de um branch ou projeto descartável. Não execute na produção. A criação de branch foi recusada nesta tarefa por seu custo recorrente; por isso teste ao vivo não é reportado como aprovado.

## 6. Deploy seguro de Edge Functions

O workflow manual espera que o administrador configure:

1. GitHub repository secret `SUPABASE_ACCESS_TOKEN` (token pessoal/CI da Supabase, nunca commitado).
2. GitHub repository variable `SUPABASE_PROJECT_REF`, conferida contra `confirm_project_ref` digitado na execução.
3. No projeto Supabase, estes nomes de secrets de runtime (os valores nunca são impressos pelo workflow): `OPENAI_API_KEY`, `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` e `SCHEDULED_REMINDERS_SECRET`. Chaves de sistema como URL/service-role são providas pelo runtime Supabase; confirme também `SUPABASE_ANON_KEY` ou publishable key para validação do JWT.
4. Ambiente GitHub `production` com reviewers obrigatórios antes de permitir o job deploy; isso deve ser configurado no repositório. A workflow exige acionamento manual, mas a proteção de reviewers é uma configuração do GitHub e não foi alterada nesta tarefa.

O job de deploy para quando faltar variável/secreto exigido ou o ref não casar. Ele não registra, rotaciona nem inventa valores de segredo. Configuração do ambiente GitHub e dos secrets Supabase não foi feita porque não foram fornecidos valores de credenciais de provedor nesta execução. Não foi executado deploy.

## 7. Migrations e histórico: restrições importantes

- As 24 migrations baseline remotas têm nomes agregados `sdd_*`; os arquivos granulares históricos locais usam prefixo `20260101…`. Essa divergência pré-existente ainda impede declarar reconciliado o histórico CLI.
- Migrations complementares aplicadas são 14, versão `20261009020600` incluída. O histórico remoto está com 38 versões, confirmadas em `supabase_migrations.schema_migrations`.
- A migration mais recente foi aplicada pelo fluxo Supabase MCP após testes locais; use o arquivo versionado como fonte de auditoria, não execute SQL manualmente em duplicidade.
- **Não executar `supabase db push`, `supabase migration up`, `supabase db reset` ou reaplicar os seis bundles no projeto remoto** até criar baseline/repair plan revisável e testar em ambiente isolado. Não foi feita branch, restore point ou reescrita do histórico nesta rodada.
- O Supabase MCP permaneceu como mecanismo de aplicação da migration isolada; CLI local está configurada para PostgreSQL 17 para desenvolvimento futuro.

## 8. Limitações, risco residual e próximos passos

1. **Merge do GitHub:** revisar/mergear `fix/audit-followups` após CI; schema remoto já recebeu a versão correspondente.
2. **Staging e teste autenticado:** obter aprovação/custo para projeto não produtivo, executar Auth/Storage/Realtime e testes cruzados de titular/terceiro/admin; não testar isso na produção.
3. **Secrets e deploy:** configurar secrets nos stores apropriados, proteger environment `production` com reviewers e só então acionar a workflow manual após validação/revisão.
4. **Consumidores do XP:** procurar consumidores externos que chamem `award_xp` diretamente; eles agora precisam passar por backend validado, sem restaurar `EXECUTE` para clientes.
5. **Baseline CLI:** escrever/revisar um plano para as 24 migrations `sdd_*` e as fontes granulares antes de permitir `db push`.
6. **Extensions:** os cinco avisos de extensão em `public` persistem. Mover extensões requer ambiente isolado, checagem de operadores/types/RPCs e rollback testado.
7. **Policies e índices:** revisar os 165 findings de múltiplas policies e 113 índices sem uso com carga observada; não remover ou simplificar automaticamente.
8. **Produto/frontend:** este repositório não contém aplicação Next.js executável. Integrar contratos de perfil, consentimento, quiz, newsletter, diário e views seguras no cliente do produto.
9. **Spoilers:** `percent`/`status` de leitura é autodeclarado e informativo. Não usar o estado auto-reportado como mecanismo de autorização para conteúdo realmente restrito.
10. **Restore point:** não houve backup/restore point criado nesta rodada. Criar ponto restaurável e confirmar retenção antes de futuras mudanças de produção.

## 9. Referências operacionais

- [Configuração Supabase CLI](https://supabase.com/docs/guides/local-development/cli/config) — `major_version=17` acompanha o servidor remoto.
- [Deno Deploy/Edge Functions](https://supabase.com/docs/guides/functions) — implantação, secrets e execução.
- [Tipos TypeScript Supabase](https://supabase.com/docs/guides/api/rest/generating-types) — o tipo do repositório foi gerado do schema remoto pós-migration.
- [`docs/implementation-blockers.md`](./docs/implementation-blockers.md) — decisões de `user_clubs` versus `clubs`, histórico e pendências.

Nenhum valor de credential, token, secret de provedor ou dado de usuário está documentado aqui.
