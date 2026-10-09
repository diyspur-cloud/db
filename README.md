# Diyspur — backend Supabase do Clube de Leitura

Backend de dados, autorização e serviços do **Clube de Leitura**, especificado em [`SDDBD2.md`](./SDDBD2.md). Este repositório reúne SQL PostgreSQL, migrations incrementais, seeds descartáveis, Edge Functions Deno, contratos TypeScript, auditorias de segurança, testes e documentação operacional.

> **Fechamento da execução de 09/10/2026:** as correções de backend foram implementadas e aplicadas incrementalmente ao projeto Supabase existente, e os **dez handlers exigidos foram publicados**. As suítes locais de segurança/regras de negócio passaram. Stripe está configurado em **teste**, com validação de assinatura/replay técnico demonstrada. Isso **não equivale a aceite integral de produção**: OAuth Supabase, remetente Resend verificável, IA, staging, backup restaurável e carga representativa continuam com limites descritos abaixo.

> **Frontend fora do escopo por decisão expressa do titular.** Nenhuma tela Next.js, fluxo visual, aplicação web ou publicação de website faz parte desta entrega. Os clientes Supabase legados foram preservados; a tipagem de banco gerada foi atualizada como contrato de backend.

## Sumário

1. [Identificação e escopo](#1-identificação-e-escopo)
2. [Arquitetura e fronteiras de segurança](#2-arquitetura-e-fronteiras-de-segurança)
3. [Todas as alterações desta execução](#3-todas-as-alterações-desta-execução)
4. [Migrations e reconciliação](#4-migrations-e-reconciliação)
5. [Edge Functions e contratos](#5-edge-functions-e-contratos)
6. [Integrações externas](#6-integrações-externas)
7. [Cron, Vault e notificações](#7-cron-vault-e-notificações)
8. [Organização de arquivos](#8-organização-de-arquivos)
9. [Testes e evidências](#9-testes-e-evidências)
10. [Operação e deploy](#10-operação-e-deploy)
11. [Pendências e decisões não inventadas](#11-pendências-e-decisões-não-inventadas)
12. [Histórico e documentação complementar](#12-histórico-e-documentação-complementar)

## 1. Identificação e escopo

| Recurso | Referência |
|---|---|
| GitHub | [diyspur-cloud/db](https://github.com/diyspur-cloud/db) |
| Supabase project ref | `xjhehhfhhoomblcggjpk` |
| API do projeto | `https://xjhehhfhhoomblcggjpk.supabase.co` |
| Dashboard | [Supabase](https://supabase.com/dashboard/project/xjhehhfhhoomblcggjpk) |
| Contrato original | [`SDDBD2.md`](./SDDBD2.md) |
| Pendências recebidas | [`docs/execution/sdd-pendencias-original.txt`](./docs/execution/sdd-pendencias-original.txt) |
| Plano ajustado | [`plan.md`](./plan.md) |
| Critérios originais e fechamento | [`TODO.md`](./TODO.md) |
| API dos handlers | [`docs/openapi.yaml`](./docs/openapi.yaml) |

O trabalho começou com inventário do repositório, catálogo remoto, grants, policies, histórico e inventário de funções. O titular posteriormente limitou a execução ao **backend/Supabase** e resolveu duas regras de produto: **bônus de streak de 25 XP uma vez por dia com atividade** e **newsletter para todos os inscritos confirmados, ignorando tags**. Essas decisões prevalecem sobre a ambiguidade dos exemplos do anexo.

Não foram criadas entidades alternativas de livro, progresso, clube ou assinatura para contornar o modelo existente. Não houve reset remoto, replay de bundles em produção, compra/upgrade, disparo em massa, dados editoriais fictícios ou fabricação de sucesso end-to-end.

## 2. Arquitetura e fronteiras de segurança

```text
Cliente do produto (externo a esta entrega)
  ├─ Supabase Auth → sessão/JWT
  ├─ Data API → grants mínimos + RLS + views invoker
  ├─ Storage → políticas de ownership/visibilidade
  └─ Edge Functions → JWT/segredo/assinatura validado
                         └─ RPCs server-only → operações transacionais
PostgreSQL
  ├─ public: entidades do produto + APIs/views protegidas
  ├─ private: helpers, leases, deduplicação e projeções sensíveis
  ├─ triggers internos: manutenção de contadores e streak
  └─ cron + Vault + pg_net: reminders e refresh de estatísticas
```

### 2.1 Segurança de cliente versus servidor

A chave publishable não é chave administrativa. O cliente não recebe `service_role`, secrets de provedores, respostas corretas de quiz, `profiles.role` ou autorização baseada em metadata editável. Os handlers validam a sessão com Supabase Auth e derivam o usuário da identidade autenticada; campos `user_id` não autorizam acesso a terceiros.

RPCs de pontuação, quiz, lembretes, newsletter e Stripe permanecem server-only: execução revogada de `PUBLIC`, `anon` e `authenticated`, concedida ao papel de serviço. Helpers privilegiados ficam em `private`, com `search_path` explícito e verificações de identidade. Contadores são alterados por triggers internos após o ingresso autorizado pela RLS, não por UPDATE direto dos clientes.

As views públicas usam `security_invoker`; a materialized view comunitária permanece privada. Aggregate coletivo não deve revelar linhas individuais de membros de clube privado. `unlisted` não foi transformado em visibilidade pública.

### 2.2 Catálogo observado

Snapshot em [`docs/execution/remote/final-snapshot.json`](./docs/execution/remote/final-snapshot.json): **77 tabelas públicas e 77 com RLS**; 48 migrations registradas na captura inicial de fechamento e **50 após as duas correções finais**, totalizando **12 migrations novas aplicadas nesta rodada**. RPCs finais consultadas: `take_rate_limit` restrita a serviço e `finish_newsletter_dispatch_owned` sem execução para cliente autenticado.

O inventário anterior incluía 12 views públicas invoker, uma MV privada, 15 tabelas na publicação Realtime e 10 buckets. Estes números históricos não são teste funcional de Auth, Storage ou Realtime. Não se criou uma nova stack de dados.

## 3. Todas as alterações desta execução

### 3.1 Buddy reads: remoção de recursão RLS

A consulta ao pai e aos membros alimentava avaliação recursiva das policies. A correção cria/reutiliza `private.can_view_buddy_read`, verifica `auth.uid()` e preserva visibilidade pública, dono e membro. As policies passam a consultar esse helper sem tornar o recurso privado público. A mesma regra continua protegendo relações dependentes. Não foram adicionados grants amplos como paliativo.

Testes PGlite verificam leitura pública/privada, identidade autorizada, owner e negação a terceiros. Probes remotos confirmam rotas sem o erro `42P17`; isso, isoladamente, não comprova autorização multiusuário real.

### 3.2 Listas: remoção de recursão e proteção de colaboração

`private.can_view_reading_list` remove a dependência circular de policies. Mantém owner, colaborador e visibilidade, sem tornar lista `unlisted` pública. Casos de edição respeitam `can_edit`; a troca de `list_id` não autoriza gravar em lista de outro titular. Fixture/grants do harness foram corrigidos para representar o schema sem enfraquecer asserções.

### 3.3 Helper administrativo

`private.current_user_is_admin` lê o papel confiável de perfil em contexto restrito. O wrapper público `is_admin()` é invoker e delega ao helper sem reabrir SELECT da coluna `role`. Anônimo/leitor devem receber false, admin true. Policies editoriais e Storage continuam usando uma fonte de papel que o cliente não pode editar.

### 3.4 Triggers internos de reações, respostas, feed e streak

Corpos de contadores foram movidos/restaurados em funções privadas privilegiadas, com nomes qualificados. Os triggers continuam sendo a interface; execução RPC direta foi revogada. INSERT/DELETE autorizados de reação, resposta e like de feed incrementam/decrementam contagens sem o erro de privilégio anterior. UPDATE/UPSERT do progresso atualiza streak sem conceder escrita direta em `user_streaks`.

O fixture de comentários ganhou o DEFAULT de UUID presente em produção; INSERT de resposta deixa o banco gerar `id`, pois o grant de cliente permite colunas de conteúdo, não identificação arbitrária. A relação `follows` recebeu no fixture o grant necessário para a policy real de feed. Datas PGlite são comparadas com cast `::text`, sem remover a exigência de atividade do dia.

### 3.5 Onboarding e perfil

Foram restaurados os grants mínimos para campos do onboarding, incluindo `level`, `onboarding_done` e o campo WhatsApp do titular quando previsto no modelo. Policies UPDATE mantêm `USING` e `WITH CHECK` da própria identidade. O cliente não pode promover `role`, alterar outro perfil ou forjar timestamp protegido de consentimento.

**Decisão registrada, não ocultada:** `level` aparece como escolha de onboarding no SDD, mas uma migration anterior o tratava como progressão derivada. A restauração segue o onboarding e não transforma esse texto autodeclarado em prova de nível/entitlement. Não foi inventado enum fechado nem motor de progressão.

### 3.6 Bônus diário de streak

RPC privada `award_daily_streak_bonus` exige atividade na data corrente, tanto em streak quanto no progresso/ledger não-streak. O usuário é derivado da sessão; o endpoint ignora referência controlada pelo cliente para essa concessão. O banco cria referência determinística por usuário/data e usa o ledger idempotente de XP.

| Regra | Comportamento |
|---|---|
| Valor | 25 XP |
| Frequência | No máximo uma concessão por dia com atividade |
| Dia | `current_date` do PostgreSQL, não fuso arbitrário do navegador |
| Referência | Derivada server-side por usuário/data |
| Retry/concorrência | Índice único evita segunda entrada/crédito |
| Sem atividade | Não concede |
| RPC direto de cliente | Bloqueado |

### 3.7 Quiz: entrada compatível, validação e conflito idempotente

O handler calcula score no servidor, valida capítulo disponível e perguntas/opções, recusa payload parcial/inválido e usa rate limit/RPCs transacionais. `request_id` é opcional para compatibilidade de chamada antiga, mas **retry idempotente exige que o consumidor persista e reenvie a mesma chave**. Sem chave reutilizada, chamadas independentes não são identificadas como retries.

A correção final vincula `(user_id, request_id)` ao capítulo **e às respostas**. `question_id/chosen_idx` são canonicalizados e ordenados; reordenar o array não muda identidade. Outro capítulo ou resposta diferente retorna **409 `idempotency_key_conflict`**, não resultado antigo. Falha de leitura de replay retorna 503. A RPC repete a comparação sob lock e após conflito de INSERT, mantendo assinatura/grants e respostas originais.

### 3.8 Estatísticas comunitárias

Aliases esperados pelo SDD foram restaurados em `v_book_community_stats` sem duplicar a MV. A API pública e a localização privada da MV são diferenças intencionais de segurança. Defaults sem avaliações/votos e origem de cada métrica constam do SQL e relatório.

Há uma fronteira temporal explícita: métricas da MV refletem último refresh; moods calculados de fonte corrente podem refletir instante posterior. Não chamar esse conjunto de snapshot atomicamente simultâneo. O refresh existente foi preservado.

### 3.9 Painel coletivo de clubes

Aliases de quantidade, leitores e médias foram restaurados sobre `user_clubs`, a entidade que realmente existe, sem inventar `public.clubs`. Helper privado permite agregado coletivo autorizado, em vez de somar somente linhas do usuário por efeito de RLS. Clube privado continua restrito. `want_to_read` é estado registrado, não inferência automática de todos os membros sem progresso.

A auditoria identificou diferença entre aliases que somavam temporadas do livro e o painel legado da temporada corrente; a correção final já aplicada filtra `current_season_id` quando definida, preservando agregação histórica por livro quando nula. Detalhes em [`REPORT-final-fixes.md`](./docs/execution/REPORT-final-fixes.md). Não se criou segundo progresso por livro.

### 3.10 Newsletter

O seed com `tags:["welcome"]` é aceito. Tags/filtros conhecidos são validados por compatibilidade, mas seleção deliberadamente aplica apenas `status=confirmed` e `unsubscribed_at IS NULL`. A chave de audiência estável `todos_confirmados` impede que mudança de tags ignoradas crie nova campanha.

Entregas anteriores são paginadas; destinatários já enviados não são reenviados. Há chave de idempotência por edição/destinatário no provedor, além de lease no banco. Após exceção, o handler tenta finalizar seu claim sem substituir o erro original. A auditoria documentou que o lease histórico de 24 horas não se libera simplesmente com `finish(false)` e que a liberação segura exige identidade/token do claim; não confundir best-effort cleanup com retry imediato garantido. **Correção final aplicada:** `claim_token` identifica a execução; `claim_newsletter_dispatch_token` cria/recupera token e `finish_newsletter_dispatch_owned` finaliza/libera somente o claim aberto correspondente. Falha com token válido libera retry imediato; token antigo não altera claim recuperado/concluído. `finish(false)` legado passa a no-op para não desfazer sucesso. O handler publicado usa as novas RPCs sem overload PostgREST.

Nenhuma newsletter foi disparada. Secret e remetente cadastrado não equivalem a remetente verificável pelo Resend.

### 3.11 Stripe

O handler verifica assinatura do corpo bruto, traduz eventos suportados, mapeia customer para usuário e price para plano existente, e chama o RPC transacional de event ID/assinatura. Replays não duplicam o ledger. Erros de processamento retornam 5xx para retry do Stripe.

A condição de configuração foi refinada: secret ausente retorna 503; assinatura ausente/inválida retorna 400. Probe técnico com assinatura válida retorna 200 e repetição retorna `duplicate`. Nenhum pagamento/assinatura comercial foi criado. Mapeamento de prices reais permanece requisito operacional, não foi preenchido com dados fictícios.

### 3.12 IA, matches e cards

Os handlers de IA têm autenticação, identidade/snapshot pessoal e falha clara de configuração quando não há secret apropriado. Match calcula usuário autorizado e devolve overlaps permitidos, não vetores/snapshot de terceiros. Cards preservam o payload/jobs existentes, ownership e limites; não foi inventado renderizador PNG, template social ou exportador externo.

A revisão apontou corridas nos limites read-before-write de embeddings/cards. Os ajustes atômicos de fechamento já foram aplicados e os handlers republicados. `take_rate_limit` usa UPSERT serializado em tabela privada: 10 tentativas por janela de 86400 segundos para cards e 1 por 3600 segundos para embeddings. A janela é fixa a partir da primeira tentativa do bucket, reiniciada ao expirar, **não uma sliding window exata de todas as últimas 24h**; falhas depois da tomada consomem tentativa. Detalhes em [`docs/execution/REPORT-final-fixes.md`](./docs/execution/REPORT-final-fixes.md). Deploy de IA não é inferência real validada.

### 3.13 Seeds, contratos e scripts

`config.toml` inclui `seed.sql` e `seed_complement.sql` na ordem. Guards `ON CONFLICT`/`NOT EXISTS` evitam duplicação; dados demonstrativos ficam vinculados à temporada correta. Seeds não foram reaplicados em produção.

A tipagem `src/lib/supabase/database.types.ts` foi regenerada do schema remoto. OpenAPI 3.1 descreve dez handlers, autenticação, parâmetros, erros e idempotência; valores YAML iniciados por crases foram corrigidos e o documento foi parseado com PyYAML.

Scripts de coleta/probe guardam evidências sanitizadas; deploy de reminders usa o gate próprio, não JWT de usuário. Replay scratch tem bootstrap/overlay separado, descrito abaixo. Não houve mudança de UI.

## 4. Migrations e reconciliação

### 4.1 Incrementais aplicadas nesta rodada

| Fonte local criada | Versão registrada no remoto | Propósito |
|---|---|---|
| `20261009025153_fix_buddy_read_policy_recursion.sql` | `20261009030146` | RLS buddy |
| `20261009025155_fix_reading_list_policy_recursion.sql` | `20261009030149` | RLS listas |
| `20261009025157_restore_admin_predicate.sql` | `20261009030152` | Admin privado |
| `20261009025159_restore_internal_counter_triggers.sql` | `20261009030204` | Triggers internos |
| `20261009025201_restore_profile_onboarding_contract.sql` | `20261009030207` | Onboarding titular |
| `20261009025203_restore_community_stats_contract.sql` | `20261009030211` | Aliases estatísticas |
| `20261009025205_restore_club_progress_panel_contract.sql` | `20261009030214` | Painel coletivo |
| `20261009025524_award_daily_streak_bonus.sql` | `20261009030217` | 25 XP/dia |
| `20261009030241_schedule_meeting_reminders.sql` | `20261009030252` | Cron/Vault/pg_net |
| `20261009032120_fix_quiz_idempotency_conflict.sql` | `20261009033340` | Conflito de replay |
| `20261009034508_fix_atomic_rate_limits_and_club_season.sql` | `20261009035042` | Limites atômicos e temporada coletiva |
| `20261009034511_fix_newsletter_claim_ownership.sql` | `20261009035049` | Token de execução e retry seguro |

O mecanismo administrativo registrou timestamps próprios. Essa tabela é o mapeamento factual; os arquivos históricos não foram renomeados indiscriminadamente. As doze aplicações foram confirmadas; nenhuma migration do baseline foi reaplicada.

### 4.2 Baseline não reconciliado para db push

As primeiras 24 migrations remotas são bundles/seeds `sdd_*`, enquanto o baseline local é granular `20260101…`. Não há correspondência 1:1 por timestamp. A rodada preservou o histórico e aplicou apenas incrementais individuais revisadas. Não executou `migration repair`, reset remoto ou bundles sobre tabelas existentes.

**Não usar `supabase db push`, `migration up`, `db reset --linked` ou reaplicar bundles no projeto existente** sem manifesto completo de reconciliação, staging e estratégia restaurável. [`reconciliation.md`](./docs/execution/reconciliation.md) registra o limite. Os scripts e arquivos de referência não são licença para reset de produção.

### 4.3 Replay scratch do defeito histórico 42803

A migration histórica `20261008214920_add_community_reading_views.sql` seleciona `s.title` e agrupa `current_season.title`, causando 42803. Foi mantida intacta. O replay descartável reproduz esse erro e aplica **overlay apenas em memória/cópia temporária**, no ponto lógico original, antes de continuar o sufixo. Isso evita editar migration aplicada ou inserir histórico duplicado.

`--reduced` usa PGlite e bootstrap mínimo para a região problemática. `--full` prepara cópia temporária e usa stack Supabase local/Docker; não foi executado por ausência de Docker. Sucesso reduzido não é sucesso de todas as migrations/seeds/serviços. Contrato SQL executável em `supabase/tests/sdd_contract.test.sql` verifica views/index/aliases.

## 5. Edge Functions e contratos

| Handler publicado | Gate | Responsabilidade |
|---|---|---|
| `quiz-validate` | JWT + identidade | Score server-side, rate limit, attempt/replay/XP |
| `award-xp` | JWT + evidência | Eventos permitidos e bônus diário idempotente |
| `vote-next-book` | JWT | Voto com janela/opção/contador transacional |
| `scheduled-reminders` | Segredo interno | Notificações deduplicadas |
| `ai-recommendations` | JWT | Recomendação pessoal, requer OpenAI |
| `ai-user-embeddings` | JWT/ownership | Embeddings próprios, limite e snapshot |
| `match-readers` | JWT/ownership | Match/cache pessoal e overlaps |
| `newsletter-dispatch` | JWT + admin confiável | Todos confirmados, lease, Resend/log |
| `stripe-webhook` | Assinatura Stripe | Eventos de assinatura idempotentes |
| `social-render-card` | JWT/ownership | Job/card conforme contrato existente |

`verify_jwt=false` é necessário para Stripe e reminders, pois usam assinatura/segredo próprio. Os demais mantêm verificação JWT e validação de usuário no handler. `GET` sem método permitido retorna 405; isso prova roteamento, não negócio completo. OPTIONS/CORS não autentica o usuário.

Existe também fonte administrativa `generate-book-embeddings`; não faz parte dos dez exigidos/publicados nesta rodada. O workflow legado pode incluir 11 fontes, então revisar o manifesto/escopo antes de acioná-lo.

## 6. Integrações externas

Estado detalhado e fontes em [`provider-setup.md`](./docs/execution/provider-setup.md).

| Integração | Concluído | Pendente/limite |
|---|---|---|
| Stripe | API de teste + webhook teste + secret; assinatura/replay técnico HTTP 200/400 | Não live; sem checkout/price comercial testado |
| Resend | API key de envio cadastrada; `RESEND_FROM_EMAIL=diyspur@gmail.com` solicitado | Gmail não é domínio próprio verificável; nenhum envio validado |
| Google Cloud | Projeto sem billing, termos/política aprovados, OAuth web Testing, callback, titular test user | Provedor Supabase não salvo; autocomplete bloqueou campos; login não executado |
| GitHub OAuth | Fonte suporta provider externo | OAuth App/credenciais/habilitação pendentes |
| OpenAI | Fontes publicadas e falhas de configuração tratadas | Secret de runtime apropriado e inferência real pendentes |

A chave Resend respondeu `restricted_api_key` ao inventário de domínios: é restrita a enviar, não a listar. Não se declarou inválida nem se inventou domínio. Google permanece **Testing**, sem publicação ampla. Opções de nonce/e-mail/MFA não foram relaxadas.

Secrets privados permanecem nos stores protegidos. Nenhum valor de secret/API key privada/token OAuth está em README, código, evidência commitada ou payload de deploy no repositório. As credenciais compartilhadas no chat merecem rotação pelo titular; não foram rotacionadas automaticamente.

## 7. Cron, Vault e notificações

| Job | Schedule | Estado |
|---|---|---|
| `refresh-mv-book-community-stats` | `0 */6 * * *` | Preexistente e preservado |
| `reminders-every-hour` | `0 * * * *` | Criado nesta execução, ativo |

`pg_net` foi habilitado; o segredo aleatório interno foi cadastrado no runtime Edge e no Vault, fora de migrations/Git. O SQL resolve o segredo no momento da execução e envia `x-scheduled-reminders-secret`, não JWT de usuário. Um job por nome impede criação duplicada na execução atual.

Chamada controlada por `pg_net` retornou HTTP 200; handler respondeu zero reuniões/zero notificações na janela. O ledger/RPC local demonstra deduplicação. **Ainda não foi observada primeira execução agendada do novo job em `cron.job_run_details`** no fechamento: o registro existente pertence ao refresh anterior. Não confundir teste manual HTTP com execução horária ou entrega real de RSVP.

Para operação, acompanhar `cron.job_run_details` e respostas HTTP de `net`, sem extrair Vault ou headers secretos. Secret errado/ausente deve rejeitar antes de DML. Não agendar um segundo monitor Manus para substituir cron nativo.

## 8. Organização de arquivos

```text
.
├── README.md                     # guia atual e detalhado
├── SDDBD2.md                     # contrato original preservado
├── plan.md / TODO.md             # escopo, critérios e fechamento
├── .github/workflows/            # CI + deploy manual protegido
├── docs/
│   ├── openapi.yaml              # contrato dos dez handlers
│   ├── deployment-status.md      # estado histórico da rodada anterior
│   └── execution/
│       ├── REPORT-*.md           # implementação, revisão, testes e replay
│       ├── provider-setup.md     # integrações sem secrets
│       ├── reconciliation.md     # baseline e diferenças de versionamento
│       └── remote/               # evidências administrativas/HTTP sanitizadas
├── scripts/
│   ├── security-smoke/           # PGlite, RLS e regras SQL reais carregadas
│   ├── integration-smoke/        # Auth/Storage/Realtime staging guardado
│   ├── replay-local.*            # scratch, bootstrap e overlay explícito
│   ├── probe-sdd-remote.py        # probes read-only de rotas
│   ├── collect-remote-evidence.py # catálogo read-only
│   └── deploy-edge-functions.sh  # deploy reproduzível, sem migrations
├── supabase/
│   ├── config.toml               # Postgres 17 e seeds ordenados
│   ├── migrations/               # histórico preservado + incrementais
│   ├── deploy-bundles/           # referências; nunca reaplicar em produção
│   ├── functions/                # Deno, helpers e lockfile
│   ├── tests/sdd_contract.test.sql
│   ├── seed.sql / seed_complement.sql
│   └── security-audit.sql
└── src/
    ├── lib/supabase/              # clientes legados + tipagem gerada
    └── types/                    # contratos de domínio existentes
```

## 9. Testes e evidências

### 9.1 Comandos reproduzíveis

Requer Node 22+, Python 3.11+, Deno 2 e Supabase CLI para full local. Dependências Deno/NPM das funções são pinadas em lockfile; Python parser deve usar versão fixa.

```bash
npm ci --prefix scripts/security-smoke
npm test --prefix scripts/security-smoke
# Executa test.mjs, business-rules.mjs e final-fixes.mjs.

python3 -m pip install pglast==7.11 PyYAML==6.0.2
python3 - <<'PY'
from pathlib import Path
from pglast import parse_sql
import yaml
files = list(Path('supabase/migrations').rglob('*.sql'))
for file in files:
    parse_sql(file.read_text())
api = yaml.safe_load(Path('docs/openapi.yaml').read_text())
assert api['openapi'] == '3.1.0' and len(api['paths']) == 10
print('SQL syntax and OpenAPI passed')
PY

deno task --config supabase/functions/deno.json check
deno task --config supabase/functions/deno.json lint
deno task --config supabase/functions/deno.json fmt:check
deno check src/lib/supabase/database.types.ts

bash scripts/replay-local.sh --reduced
# Com Docker/stack local, em ambiente descartável:
# bash scripts/replay-local.sh --full

deno task --config scripts/integration-smoke/deno.json check
deno task --config scripts/integration-smoke/deno.json lint
deno task --config scripts/integration-smoke/deno.json fmt:check

git diff --check
```

### 9.2 Resultados efetivamente obtidos

| Validação | Resultado | Alcance |
|---|---|---|
| PGlite segurança | PASS: `ALL SECURITY SMOKE ASSERTIONS PASSED` | RLS/ownership/admin/grants/contadores/streak nos fixtures |
| PGlite negócio | PASS: `ALL BUSINESS-RULE TESTS PASSED`, mais `final-fixes.mjs` PASS | XP, médias, metas, quiz, votos, reminders, newsletter, Stripe, matches |
| Deno check/lint/fmt | PASS | Fontes e dependências Deno, não inferência externa |
| Parser SQL | PASS nas fontes verificadas | Sintaxe; não substitui execução de constraints/policies |
| OpenAPI YAML | PASS, 3.1 e dez paths | Documento parseável; não teste de POST autenticado |
| Replay PGlite reduzido | PASS com erro histórico reproduzido + overlay + contrato | Região do baseline; não stack full |
| Probes Supabase | Rotas recuperadas; dez handlers publicados | Disponibilidade/método, não toda matriz A/B |
| Stripe assinado/replay | 200 `processed`/`duplicate`; sem/inválida 400 | Evento técnico, sem operação financeira |
| Cron HTTP manual | 200, sem reuniões na janela | Transporte/segredo, não entrega real agendada |

Relatórios antigos são fotografias intermediárias; alguns dizem “não publicado” ou “secrets ausentes”. **Esta seção e o relatório final prevalecem para o fechamento**, sem apagar evidência histórica de erros/bloqueios.

### 9.3 O que ainda não passou por execução real

O harness de integração Auth/Storage/Realtime recusa o project ref de produção e exige staging/ref coincidente/`SUPABASE_TEST_ALLOW_MUTATIONS=true`. Esse guard foi preservado. Não foram criadas contas reais para simular sucesso, nem removido o guard. PGlite usa fixtures/bootstrap explícitos; não é teste da stack completa. Full Docker/seeds duas vezes, login Google/GitHub/Magic Link, armazenamento assinado e Realtime multiusuário real não são reportados como aprovados.

Performance remota foi inspecionada com planos e índices existentes: feed usa `feed_posts_public_idx`, matches `umc_user_sim_idx`, quiz índice capítulo/posição. Volumes observados feed=0, quiz_questions=1, cache=0 não suportam conclusão de escala. Índices `idx_scan=0` não foram removidos por inferência.

## 10. Operação e deploy

### 10.1 Configuração protegida

| Nome | Uso | Estado nesta entrega |
|---|---|---|
| `SUPABASE_URL` / chaves de sistema | Runtime Supabase | Providas pelo serviço; não commitadas |
| `SCHEDULED_REMINDERS_SECRET` | Header interno + Vault | Configurado |
| `STRIPE_SECRET_KEY` | API Stripe | Teste configurado |
| `STRIPE_WEBHOOK_SECRET` | Corpo bruto/assinatura | Teste configurado |
| `RESEND_API_KEY` | Envio | Configurado, escopo envio |
| `RESEND_FROM_EMAIL` | Remetente | Solicitado cadastrado; domínio verificável pendente |
| `OPENAI_API_KEY` | IA | Pendente no runtime Edge |
| OAuth Client IDs/Secrets | Auth providers | Google criado, Supabase não salvo; GitHub pendente |

Para GitHub Actions, `SUPABASE_ACCESS_TOKEN`, variável `SUPABASE_PROJECT_REF` e proteção do environment `production` devem ser configurados pelo administrador. Listagem de secrets GitHub retornou 403 para a integração; não foi contornado nem interpretado como inexistência. Token Git do agente não é token administrativo Supabase.

### 10.2 Processo de publicação futura

Revisar fontes/lockfile/manifesto, executar CI, confirmar o project ref e nomes de secrets, e usar o workflow manual ou script CLI autorizado. Deploy não faz migrations, não popula seeds e não corrige baseline. A publicação desta execução utilizou o conector administrativo Supabase por handler; comprovantes ficam em `docs/execution/remote/`.

O workflow legado publica todas as fontes previstas nele, inclusive a administrativa adicional; isso não significa que 11 endpoints foram publicados nesta rodada. Não acionar deploy automático de production com secrets faltantes. O push GitHub solicitado entrega código/documentação, não uma publicação nova de frontend nem garantia de CI verde sem resultado observado.

### 10.3 Recuperação e backup

Nenhum reset ou dump de usuários foi entregue. O painel não disponibilizava backup agendado no plano observado; não houve upgrade ou compra. Antes de mudanças destrutivas/restores, obter ponto restaurável real e testar retenção/restore em staging. Não restaurar banco sobre produção com base em bundles locais.

## 11. Pendências e decisões não inventadas

| Tema | Limite/ação necessária |
|---|---|
| Google Supabase | Concluir cadastro das credenciais reais sem autocomplete; habilitar e testar login |
| GitHub Supabase | Criar/configurar OAuth App e testar sessão |
| Site URL/allowlist | Definir URLs reais da aplicação, sem inventar domínio/frontend |
| Resend | Remetente em domínio próprio verificado antes de disparo |
| OpenAI | Secret apropriado no runtime e teste controlado de IA |
| Stripe live | Não ativado; mapear prices/testar fora de produção antes de operação comercial |
| Staging | Executar Auth/Storage/Realtime e matriz A/B real com autorização apropriada |
| Baseline | Manifesto de correspondência bundles/granulares; full local e seeds sem duplicar |
| Cron | Observar primeira execução horária e notificações de reuniões reais |
| Backup | Ponto restaurável/restore testado, sem comprometer plano/cobrança |
| Nível do perfil | Campo autodeclarado de onboarding não é progressão confiável |
| Snapshot comunitário | MV e moods podem representar instantes diferentes |
| Motores de produto | Badges/desafios/games/PNG social/Discord/Calendar não especificados integralmente |
| Frontend | Adiado pelo titular; nenhuma UI executável incluída |

Não marcar TODO inteiro como concluído quando um item mistura correção SQL com teste de produto não executado. Critérios originais foram mantidos para rastreabilidade; fechamento por camada diferencia implementado, aplicado, validado localmente, integração bloqueada e UI adiada.

### 11.1 Avisos de segurança herdados

Os advisors mantêm avisos de extensões instaladas em `public`; não foram movidas automaticamente por impacto em tipos/operadores/RPCs. Referência de remediação: [Supabase — extension in public](https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public). Evidência final em `docs/execution/remote/advisors-final.json`.

## 12. Histórico e documentação complementar

A rodada anterior já implementava unicidade de XP, médias de quiz, metas a partir de capítulos/diário, timestamp de conclusão, view overview sem inflação por joins, likes do diário, voto transacional, quiz/rate limit, reminders, lease newsletter, mapeamento Stripe e overlaps de matches na migration `20261009020600_20261009014533_implement_audit_followups.sql`. A presente rodada **corrige autorização/contratos e publica serviços**, sem duplicar aquelas entidades.

| Documento | Finalidade |
|---|---|
| [`REPORT-database.md`](./docs/execution/REPORT-database.md) | RLS/helpers/triggers/aliases/XP |
| [`REPORT-edges.md`](./docs/execution/REPORT-edges.md) | Handlers e decisões de audiência |
| [`REPORT-corrections.md`](./docs/execution/REPORT-corrections.md) | Quiz vinculado ao payload e cleanup newsletter |
| [`REPORT-final-fixes.md`](./docs/execution/REPORT-final-fixes.md) | Correções técnicas finais após revisão |
| [`REPORT-tests.md`](./docs/execution/REPORT-tests.md) | Suítes PGlite e paridade dos fixtures |
| [`REPORT-replay.md`](./docs/execution/REPORT-replay.md) | Erro histórico/overlay/scratch e limitações |
| [`REPORT-review.md`](./docs/execution/REPORT-review.md) | Auditoria intermediária independente, com achados datados |
| [`reconciliation.md`](./docs/execution/reconciliation.md) | Histórico e limites administrativos |
| [`provider-setup.md`](./docs/execution/provider-setup.md) | Stripe/Resend/Google sem valores secretos |
| [`docs/deployment-status.md`](./docs/deployment-status.md) | Registro da rodada anterior, não status atual de Edge |
| [`docs/supabase-reference.md`](./docs/supabase-reference.md) | Referências oficiais |

Referências oficiais: [Supabase Auth](https://supabase.com/docs/guides/auth), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [Edge Functions](https://supabase.com/docs/guides/functions), [Cron/Functions](https://supabase.com/docs/guides/functions/schedule-functions), [Vault](https://supabase.com/docs/guides/database/vault), [Stripe Webhooks](https://docs.stripe.com/webhooks), [Resend Domains](https://resend.com/docs/dashboard/domains/introduction).

**Segredos não são documentação.** Valores privados foram excluídos da entrega GitHub; somente nomes, contratos, status e evidências sanitizadas são versionados.
