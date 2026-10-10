# DIYSPUR — backend Supabase

Repositório do backend do DIYSPUR: schema PostgreSQL, migrations, RLS, views, RPCs, seeds, Edge Functions e contratos consumidos pelo frontend.

- **Repositório:** <https://github.com/diyspur-cloud/db>
- **Frontend:** <https://github.com/diyspur-cloud/app>
- **Produção:** <https://diyspur.vercel.app/>
- **Projeto Supabase configurado:** `xjhehhfhhoomblcggjpk`
- **Schema funcional:** `public`, com helpers e projeções privadas quando necessário.

> Este repositório é a fonte de verdade do banco e das funções backend. Não coloque secrets no SQL, nas migrations, nos seeds ou no frontend. O frontend usa somente a chave publishable; credenciais administrativas permanecem no Supabase/ambiente de deploy.

## Índice

- [Estado atual](#estado-atual)
- [Arquitetura](#arquitetura)
- [Estrutura do repositório](#estrutura-do-repositório)
- [Domínios e contratos](#domínios-e-contratos)
- [RLS e segurança](#rls-e-segurança)
- [Migrations e seeds](#migrations-e-seeds)
- [Edge Functions](#edge-functions)
- [Configuração local](#configuração-local)
- [Testes e validação](#testes-e-validação)
- [Aplicação controlada no Supabase](#aplicação-controlada-no-supabase)
- [Deploy de Edge Functions](#deploy-de-edge-functions)
- [Relação com o frontend](#relação-com-o-frontend)
- [Operação e troubleshooting](#operação-e-troubleshooting)
- [Limites e pendências externas](#limites-e-pendências-externas)

## Estado atual

O schema contém as tabelas e contratos usados pelo ciclo de leitura atual, incluindo catálogo, capítulos, quizzes, progresso, comentários, encontros, enquetes, host prompts, listas, desafios, clubes, XP, achievements, notificações, preferências, conteúdo sensível e integrações de provider.

A árvore versionada possui **77 migrations SQL** e seeds editoriais em `supabase/seed.sql` e `supabase/seed_complement.sql`. As migrations incrementais mais recentes cobrem:

- proteção de conteúdo futuro e correção de recursão RLS;
- gate de capítulo e RPCs de acesso mínimo;
- conteúdo MVP de Verity, quiz e prompt do anfitrião;
- semântica correta de conclusão parcial de livro;
- votação encerrada e resultados agregados;
- fonte de XP para achievements e evaluator idempotente;
- avisos de conteúdo de Verity;
- desafio anual de 12 livros em 12 meses.

O projeto remoto utilizado pela aplicação já recebeu as migrations funcionais desta rodada. Ainda assim, qualquer ambiente novo deve ser criado por replay ordenado das migrations e seeds; não copie estado manualmente.

## Arquitetura

```text
Frontend Next.js / outros consumidores
  ├─ Supabase Auth → JWT e sessão
  ├─ Data API → grants mínimos + RLS + views autorizadas
  ├─ Storage → ownership, visibilidade e URLs assinadas
  └─ Edge Functions → JWT, segredo interno ou assinatura de webhook
                              │
                              ▼
PostgreSQL Supabase
  ├─ public: tabelas, views e RPCs expostos pelo contrato
  ├─ private: helpers, projeções e funções internas
  ├─ triggers: progresso, XP, contadores e manutenção
  ├─ pg_cron/pg_net/Vault: tarefas e secrets quando habilitados
  └─ extensões: UUID, arrays, full text/vector conforme ambiente
```

Princípios obrigatórios:

1. A identidade vem de `auth.uid()`/claims validadas, nunca de `user_id` confiado pelo browser.
2. RLS continua habilitado em toda tabela que contém dados de usuário, conteúdo protegido ou escopo de clube.
3. Score de quiz, gabarito, XP, achievement, papel administrativo e conclusão são calculados no servidor.
4. Views públicas devem selecionar somente campos públicos e respeitar a política de visibilidade.
5. Helpers privados devem evitar recursão de policy; não crie policy que consulte a mesma tabela de maneira recursiva.
6. Migrations aplicadas são imutáveis: toda correção posterior recebe novo timestamp/arquivo.
7. Secrets de provider ficam no Supabase Vault/Edge Function settings, nunca em `seed.sql`, logs ou commits.

## Estrutura do repositório

```text
supabase/
├── config.toml             # projeto local, Auth, API, DB, Storage e seed
├── migrations/             # DDL, policies, funções, views e dados incrementais
├── functions/              # Edge Functions Deno
├── seed.sql                # seed principal ordenado
├── seed_complement.sql     # conteúdo complementar/editorial
└── security-audit.sql      # consultas auxiliares de auditoria

docs/
├── openapi.yaml
├── supabase-reference.md
├── edge-functions-authorization.md
├── deployment-status.md
├── implementation-blockers.md
├── verity-edition-sources.md
└── execution/              # reconciliação e evidências de execução

scripts/
├── deploy-edge-functions.sh
├── replay-local.sh
├── replay-local.mjs
├── replay-local.bootstrap.sql
├── replay-local.overlay.sql
├── replay-local.seed-check.sql
├── build-remote-bundles.py
└── probe-sdd-remote.py

SDDBD2.md                   # especificação original do produto
TODO.md                     # pendências técnicas e de produto
plan.md                     # plano de implementação
```

## Domínios e contratos

### Catálogo e editorial

- `books`, `authors`, `seasons`, `chapters`;
- metadados de edição e classificação;
- `content_warnings` e associações editoriais;
- visibilidade de temporada/capítulo e gate de quiz;
- RPCs de acesso mínimo para listar metadados sem expor conteúdo protegido.

### Leitura e continuidade

- `user_progress` para estado/percentual/conclusão por capítulo;
- `quiz_questions`, `quiz_attempts` e `user_quiz_averages`;
- diário, metas e overview de leitura;
- milestones de temporada;
- views de histórico e leitura atual.

### Comunidade

- comentários de capítulo e comentários temporizados;
- views de comentários visíveis e estatísticas agregadas por trecho;
- flags de spoiler e moderação;
- host prompts com voto único/trocável;
- enquetes abertas e resultados encerrados.

### Clube e eventos

- `meetings`, RSVP e lembretes;
- `user_clubs`, `user_club_members`, buddy reads e checkpoints;
- `reading_lists`, itens e fila do leitor;
- `challenges` e `user_challenges`;
- policies de pertencimento e acesso privado.

### Gamificação

- `xp_events`, `user_xp`, `user_streaks`;
- achievements e `user_achievements`;
- funções de recompensa idempotentes;
- ranking por temporada sem expor PII.

### Integrações

- `affiliate_clicks` para registro mínimo de links afiliados;
- preferências e recomendações;
- embeddings/matching;
- newsletter;
- Stripe webhook;
- renderização de social cards;
- Storage privado e URLs assinadas quando habilitado.

Os contratos TypeScript consumidos pelo frontend ficam sincronizados em `app/src/types/database.ts`; alterações no backend devem ser refletidas nesse snapshot e testadas no frontend.

## RLS e segurança

Antes de criar ou alterar uma tabela:

1. defina primary key, foreign keys, índices e constraints;
2. habilite RLS;
3. escreva policies de `select`, `insert`, `update` e `delete` separadamente;
4. derive o usuário de `auth.uid()`;
5. valide ownership, publicação, temporada e vínculo de clube;
6. avalie se uma view `security_invoker` ou helper privado evita vazamento/recursão;
7. teste anon, usuário comum, outro usuário e admin.

Regras importantes já aplicadas no contrato atual:

- capítulos futuros/não publicados não ficam disponíveis só porque o UUID é conhecido;
- respostas corretas de quiz não são expostas ao cliente;
- comentários com spoiler seguem visibilidade editorial;
- listas, progresso, tentativas, metas e RSVP são escopados ao usuário;
- resultados de prompt/enquete expõem agregados, não respostas privadas de terceiros;
- papel `admin` não é aceito a partir de `user_metadata` editável;
- roles de membros de clube obedecem constraints e policies de autorização;
- função de XP e evaluator de achievements são idempotentes.

Use `supabase/security-audit.sql` e as consultas documentadas em `docs/supabase-reference.md` para auditorias. Não registre JWT, senha, gabarito, payload privado ou secret em logs.

## Migrations e seeds

### Convenções

- nome: `YYYYMMDDHHMMSS_descricao_em_snake_case.sql`;
- migration nova corrige a anterior sem editar o arquivo já aplicado;
- operações editoriais devem ser idempotentes (`WHERE NOT EXISTS`, `ON CONFLICT`, ou atualização por chave estável);
- DDL e policy devem ser revisados contra o estado remoto antes de deploy;
- fixtures de teste precisam ser claramente nomeadas e não podem abrir conteúdo futuro acidentalmente.

### Replay local

O projeto usa `supabase/config.toml` com:

- PostgreSQL major version 17;
- API local na porta 54321;
- banco local na porta 54322;
- Studio na porta 54323;
- SMTP local na porta 54324;
- seed habilitado com `seed.sql` e `seed_complement.sql`;
- limite de resposta da API configurado em 1000 linhas.

Com Docker e Supabase CLI instalados:

```bash
supabase start
supabase db reset
# ou, para o harness versionado:
./scripts/replay-local.sh
```

O replay local é descartável. Nunca rode `db reset --linked` contra produção.

### Inspeção de migration

```bash
find supabase/migrations -maxdepth 1 -name '*.sql' -print | sort
supabase migration list --project-ref "$SUPABASE_PROJECT_REF"
supabase db diff --local
```

Compare SQL, timestamps e histórico remoto antes de aplicar. Um mesmo SQL pode ter sido aplicado sob outro nome/timestamp; não use `migration repair` para esconder divergência sem reconciliação documentada.

## Edge Functions

| Função | Autorização esperada | Responsabilidade |
|---|---|---|
| `quiz-validate` | JWT | Valida respostas, score, tentativa e idempotência. |
| `award-xp` | JWT + prova de atividade | Registra XP e recompensas elegíveis. |
| `vote-next-book` | JWT | Voto transacional em enquete aberta. |
| `scheduled-reminders` | Secret interno; `--no-verify-jwt` | Processa lembretes de encontros. |
| `ai-recommendations` | JWT + provider | Recomendações personalizadas. |
| `ai-user-embeddings` | JWT + ownership + provider | Embedding de preferências do leitor. |
| `match-readers` | JWT + ownership | Matching e cache de leitores. |
| `generate-book-embeddings` | Operacional/admin | Embeddings editoriais. |
| `newsletter-dispatch` | JWT/admin + Resend | Disparo de newsletter quando provider está configurado. |
| `stripe-webhook` | Assinatura Stripe; `--no-verify-jwt` | Recebe eventos de cobrança idempotentes. |
| `social-render-card` | JWT + ownership | Cria/renderiza card social. |

Secrets esperados por função devem ser configurados no ambiente da Edge Function, por exemplo `OPENAI_API_KEY`, `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, `STRIPE_WEBHOOK_SECRET` e `SCHEDULED_REMINDERS_SECRET`, conforme o provider. Nunca use valores reais em arquivos versionados.

## Configuração local

### Requisitos

- Supabase CLI compatível com o projeto;
- Docker Desktop/Engine para `supabase start`;
- Node.js para scripts auxiliares;
- Deno ou runtime suportado pela Supabase CLI para Edge Functions;
- acesso ao projeto Supabase somente para operações autorizadas.

### Login e link

```bash
supabase login
supabase link --project-ref "$SUPABASE_PROJECT_REF"
```

Defina `SUPABASE_PROJECT_REF` apenas no shell/CI seguro:

```bash
export SUPABASE_PROJECT_REF=xjhehhfhhoomblcggjpk
```

Não salve access tokens no repositório.

## Testes e validação

A validação deve separar quatro estados:

- **implementado em arquivos:** existe no working tree;
- **testado localmente:** há teste/replay reproduzível;
- **aplicado remotamente:** migration/função foi enviada e há evidência;
- **aceito end-to-end:** fluxo foi exercitado com identidade, dados e efeitos reais.

Comandos úteis:

```bash
# replay/seed local
./scripts/replay-local.sh

# verificar migrations
supabase migration list --project-ref "$SUPABASE_PROJECT_REF"

# testes SQL/segurança do projeto
psql "$DATABASE_URL" -f supabase/security-audit.sql

# validação de Edge Functions antes do deploy
for f in supabase/functions/*/index.ts; do
  echo "checking $f"
done
```

Para mudanças de autorização, valide ao menos:

- anon sem sessão;
- usuário A em seus próprios dados;
- usuário B tentando acessar dados de A;
- admin no caminho administrativo;
- capítulo publicado versus futuro;
- conteúdo realmente vazio versus erro de policy/serviço;
- retry/idempotência de quiz, XP, RSVP e achievements.

Testes no banco compartilhado podem alterar produção. Prefira projeto staging ou banco descartável e use fixtures com identificadores estáveis.

## Aplicação controlada no Supabase

Não aplique migrations diretamente após um simples `git push`. O procedimento recomendado é:

1. revisar o diff SQL e executar `git diff --check`;
2. identificar dependências entre migrations e funções;
3. comparar o histórico remoto com `supabase migration list`;
4. fazer replay em staging/ambiente descartável;
5. revisar policies, grants, índices, triggers e views;
6. aplicar em uma janela controlada;
7. verificar a migration no remoto e testar Data API/RPC/Edge Function;
8. registrar evidência em `docs/execution/`.

Com Supabase CLI, o comando de aplicação deve ser executado somente após essa reconciliação:

```bash
supabase db push --project-ref "$SUPABASE_PROJECT_REF"
```

Não use `supabase db reset --linked`, `migration repair` ou edição de migrations aplicadas para forçar o histórico. Se o remoto e o clone divergirem, documente a reconciliação e crie uma migration corretiva.

## Deploy de Edge Functions

O script versionado separa funções JWT de webhooks/cron:

```bash
export SUPABASE_PROJECT_REF=xjhehhfhhoomblcggjpk
supabase login
./scripts/deploy-edge-functions.sh
```

Antes do deploy:

- configure secrets no projeto correto;
- valide assinatura/segredo de webhook;
- confirme `verify_jwt` de cada função;
- confira limites/rate limits;
- teste payloads inválidos e retries;
- não divulgue logs com dados privados.

`ACTIVE` no painel não prova que a versão local foi publicada nem que o provider externo está funcionando; registre versão, data e smoke test.

## Relação com o frontend

O frontend [`diyspur-cloud/app`](https://github.com/diyspur-cloud/app) consome este backend por Supabase SSR/browser. Ao mudar o backend:

1. atualize migrations e, se necessário, seeds;
2. aplique no ambiente correto;
3. sincronize `src/types/database.ts` no frontend;
4. atualize queries/actions/components;
5. execute frontend lint, typecheck, unitários, build e E2E;
6. publique o frontend no Vercel somente depois da confirmação do contrato remoto.

O deploy do Vercel não aplica migrations nem Edge Functions.

## Operação e troubleshooting

### `42P17 infinite recursion detected in policy`

Não relaxe RLS. Localize a policy que consulta a própria tabela e mova a verificação para helper privado/RPC ou reescreva a condição sem recursão. Adicione migration corretiva e teste anon/usuário/admin.

### API retorna 0 linhas

Separe três casos: consulta vazia, conteúdo não publicado e erro de autorização/serviço. Verifique status HTTP, logs, policy, grants, temporada e claims antes de alterar seed.

### Edge Function responde 401/403

Confirme se a função exige JWT, se o token foi enviado, se a assinatura é válida e se a policy/RPC aceita o usuário. Não troque `verify_jwt` por `--no-verify-jwt` como atalho; isso é reservado a webhook/cron com autenticação própria.

### Migration já aplicada com outro timestamp

Pare. Compare o SQL efetivo, o histórico remoto e o clone. Registre a correspondência; não renomeie/edite o arquivo aplicado apenas para satisfazer a CLI.

## Limites e pendências externas

- OAuth social depende de credenciais e configuração administrativa do Supabase Auth.
- Newsletter, IA, matching, Stripe e geração de social card dependem de providers, secrets, webhooks e aceite operacional.
- Replay full, backup/restore, carga com volume representativo e testes multiusuário exigem ambiente dedicado; não são inferidos de parse SQL ou de uma função `ACTIVE`.
- Conteúdo editorial deve ser revisado antes de ampliar temporadas, perguntas, avisos, enquetes ou fixtures.
- Pagamentos, planos ou benefícios não devem ser tratados como ativos sem testar cobrança, cancelamento, entitlement e recuperação de ponta a ponta.

## Documentação relacionada

- [`SDDBD2.md`](./SDDBD2.md) — especificação original;
- [`docs/openapi.yaml`](./docs/openapi.yaml) — contratos documentados;
- [`docs/supabase-reference.md`](./docs/supabase-reference.md) — referência de tabelas/RPCs/views;
- [`docs/edge-functions-authorization.md`](./docs/edge-functions-authorization.md) — autorização das funções;
- [`docs/deployment-status.md`](./docs/deployment-status.md) — estado de publicação;
- [`docs/implementation-blockers.md`](./docs/implementation-blockers.md) — bloqueios e dependências;
- [`docs/verity-edition-sources.md`](./docs/verity-edition-sources.md) — fontes editoriais;
- [`TODO.md`](./TODO.md) — pendências priorizadas.

## Contribuição

Use branches e commits pequenos. Toda alteração de schema deve incluir migration incremental, revisão de RLS e atualização do contrato consumidor. Toda alteração de Edge Function deve incluir autorização esperada, secrets necessários, comportamento de retry/idempotência e procedimento de deploy. Nunca commite secrets, dumps com PII ou credenciais de usuários.

## Release editorial full-stack — 2026-10-10

A migration `20261010120000_editorial_product_lifecycle.sql` foi aplicada com sucesso no projeto Supabase `xjhehhfhhoomblcggjpk`. O registro remoto usa a versão `20261010030848` e o nome `editorial_product_lifecycle`; essa diferença de timestamp ocorre porque o gateway remoto registra o momento do apply, enquanto o arquivo versionado preserva o timestamp de autoria.

### O que foi aplicado

| Domínio | Alterações remotas |
|---|---|
| Clubes | `user_clubs.version`, `user_clubs.archived_at`, convites, constraints de nome/descrição/role, RPCs de criação/edição/entrada/saída e policies de leitura autorizada |
| Diário | `reading_journal_entries.version`, `shared_club_id`, constraints de páginas/minutos e policy que impede exposição de club entries sem vínculo |
| Listas | `reading_lists.version`, constraint de posição não negativa e RPC transacional `reorder_reading_list` |

Todas as funções públicas novas são wrappers `SECURITY INVOKER`; a autorização sensível fica em funções `private` `SECURITY DEFINER` com `search_path` vazio e grants explícitos. A identidade sempre vem de `auth.uid()`. A tabela de convites aceita leitura somente pelo convidado ou pelo emissor; a emissão/aceite de convite ainda requer uma jornada dedicada antes de ser exposta no frontend.

### Operação segura da migration

A migration é aditiva e idempotente em colunas, constraints, policies e funções. Não edita migrations históricas, não cria usuários, não insere conteúdo editorial e não contém secrets. Em um ambiente novo, o replay deve respeitar a ordem dos arquivos do diretório `supabase/migrations` e os seeds versionados. Em produção, nunca use `supabase db reset --linked` para corrigir drift.

Procedimento recomendado para a próxima alteração:

```bash
# no clone do backend
git checkout main
git pull --ff-only origin main
supabase migration list --project-ref "$SUPABASE_PROJECT_REF"
supabase db push --project-ref "$SUPABASE_PROJECT_REF"

# depois do apply, no clone do frontend
supabase gen types typescript --project-id "$SUPABASE_PROJECT_REF" > ../app/src/types/database.ts
npm ci
npm run lint
npm run typecheck
npm test
npm run build
```

O comando `db push` deve ser executado somente depois da comparação do histórico remoto e de um replay em staging. O apply desta release foi feito pelo gateway autorizado e confirmado em `list_migrations`.

### Auditoria pós-release

A auditoria Supabase pós-apply encontrou advisories. Os avisos de segurança incluem seis extensions instaladas em `public`, as funções legadas `public.get_chapter_access` e `public.get_season_chapter_access` executáveis por anon/authenticated como `SECURITY DEFINER`, e a proteção de senha vazada do Supabase Auth desabilitada. Os avisos de performance incluem FKs novas sem índices cobridores (`shared_club_id`, `invited_by`, `invited_user_id`), recomendações de init plan para duas policies novas e uma lista de índices historicamente não utilizados.

Esses advisories foram registrados, não ocultados e não foram tratados com uma migration improvisada após o deploy. O próximo hardening deve avaliar cada função/policy contra consumidores existentes, habilitar leaked password protection no Auth e adicionar índices cobridores em migration separada, medindo antes e depois.

### Testes de autorização obrigatórios

Para cada mudança de policy/RPC, execute a matriz anon, usuário titular, usuário de outro registro, membro de clube privado, convidado, moderator e admin. Verifique especialmente: um usuário não consegue ler memberships de clube privado; um owner não consegue sair sem arquivar; uma entrada de diário privada não aparece no feed; um `shared_club_id` inexistente não abre conteúdo; e uma ordem de lista incompleta ou com item de outra lista falha de forma atômica.

### Relação com o Vercel

O backend não é aplicado pelo Vercel. O repositório `diyspur-cloud/app` consome o projeto Supabase por SSR/browser e o projeto Vercel `diyspur` é acionado pelo push em `main`. A ordem de release é: migration e confirmação remota; geração do contrato TypeScript; testes do frontend; push de `main`; build/deploy automático Vercel; smoke test das rotas públicas e dos fluxos autenticados.

## Release de hardening da auditoria — 2026-10-10

A release foi integrada à `main` pelo PR #5 e contém as correções de banco e Edge Function dos achados A01, A02, A03, A39, A40, A41 e A42.

### Migrations desta release

- `20261011000100_harden_chapter_writes_and_comments.sql`: policies de disponibilidade, RPCs de edição/remoção própria, trigger monotônico de progresso, spoiler temporizado, metadata pública de temporada e revogação de DML direto em clubes.
- `20261011000200_fix_reading_list_item_counts.sql`: backfill de `reading_lists.items_count` e trigger atômico para insert/update/delete/movimentação.

### Regras de autorização

`private.can_view_chapter` centraliza publicação e gate de quiz. Progresso, comentários e comentários temporizados só aceitam escritas em capítulos disponíveis. `auth.uid()` é a única fonte de identidade. RPCs de comentário próprio só retornam dados do autor. `get_visible_video_timed_comments` retorna `NULL` para spoilers abaixo do limiar. DML direto em clubes é revogado para `anon`/`authenticated`; as RPCs de ciclo de vida permanecem disponíveis.

### Aplicação controlada

```bash
export SUPABASE_PROJECT_REF=xjhehhfhhoomblcggjpk
supabase link --project-ref "$SUPABASE_PROJECT_REF"
supabase migration list --project-ref "$SUPABASE_PROJECT_REF"
supabase db push --project-ref "$SUPABASE_PROJECT_REF"
```

Antes do apply: revisar SQL, fazer replay em staging, reconciliar histórico remoto, revisar policies/grants/triggers, garantir ponto de restauração aprovado e executar smoke test. Não use `db reset --linked`, `migration repair` ou edição retroativa de migrations.

### Edge Function `quiz-validate`

A função diferencia `invalid_payload`, `incomplete_answers`, `unexpected_answers` e `invalid_quiz_configuration_or_answer`. Payload vazio/incompleto é rejeitado antes da persistência; score, gabarito, rate limit e idempotência continuam server-side.

### Verificação pós-apply

Confirme no histórico remoto as duas migrations, a existência das RPCs novas e teste com visitante, autor, outra conta e admin. Não registre JWT, senha, conteúdo privado ou payload completo nos logs. Se houver erro após o apply, interrompa o rollout do frontend e crie migration corretiva explícita, sem apagar o histórico.

### Estado da release

As migrations foram aplicadas no projeto `xjhehhfhhoomblcggjpk` nas versões remotas `20261010165108` e `20261010165112`. A Edge Function `quiz-validate` está ativa na versão 9 com JWT obrigatório. O frontend correspondente está em produção no Vercel no commit `7d0f824c9118d35e1cd154987447929079258915`. Typecheck, lint, 13 testes unitários, build e smoke público de navegador foram aprovados; os fluxos autenticados exigem uma conta QA autorizada para o aceite final.
