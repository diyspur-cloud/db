# Banco de dados Supabase — Clube de Leitura

Repositório de banco de dados do **Clube de Leitura**, organizado a partir do documento de desenho [`SDDBD2.md`](./SDDBD2.md). Reúne migrations SQL revisáveis, seeds do MVP e de expansão, consultas de auditoria, bundles de execução, contratos TypeScript de domínio e fontes de Edge Functions.

> **Leia antes de usar:** o baseline do SDD e as migrations complementares deste plano foram aplicados ao projeto Supabase listado abaixo. As views públicas agora usam `security_invoker`, as três tabelas sem policies receberam regras explícitas e as funções de aplicação foram endurecidas. Ainda há trabalho antes de um lançamento: reconciliar o SDD e o histórico do CLI, validar consumidores autenticados de RPC e revisar/deployar Edge Functions com autorização e secrets corretos. Nenhuma Edge Function foi implantada.

## 1. Identificação e links

| Item | Valor |
|---|---|
| Produto | Clube de Leitura |
| Documento de desenho | [`SDDBD2.md`](./SDDBD2.md) |
| Supabase project ref | `xjhehhfhhoomblcggjpk` |
| Dashboard Supabase | [Abrir o projeto](https://supabase.com/dashboard/project/xjhehhfhhoomblcggjpk) |
| Repositório GitHub | [`diyspur-cloud/db`](https://github.com/diyspur-cloud/db) |
| Branch de trabalho | `main` |
| Visibilidade do GitHub | Pública |
| Relatório do deploy e auditoria | [`docs/deployment-status.md`](./docs/deployment-status.md) |
| Plano detalhado e etapas | [`docs/implementation-plan.md`](./docs/implementation-plan.md) |
| Contrato de autorização de Edge Functions | [`docs/edge-functions-authorization.md`](./docs/edge-functions-authorization.md) |
| Dependências não definidas no SDD | [`docs/implementation-blockers.md`](./docs/implementation-blockers.md) |
| Referências de documentação Supabase | [`docs/supabase-reference.md`](./docs/supabase-reference.md) |

O repositório GitHub é público. **Não inclua nele** `.env`, credenciais, chaves de API, tokens, service-role keys, dados de usuários nem dumps do banco. Nenhum valor de credencial está documentado neste README.

## 2. Resumo executivo do estado atual

O baseline executável do SDD continua correspondendo a **75 tabelas** e **30 ENUMs**. Esta implementação acrescentou **uma tabela deliberada** (`book_reviews`), quatro campos opcionais em `user_clubs`, policies, views agregadas e hardening. A auditoria remota final de 8 de outubro de 2026 confirmou:

| Categoria | Quantidade encontrada |
|---|---:|
| Tabelas em `public` / com RLS | 76 / 76 |
| Policies RLS em `public` | 135 |
| Chaves estrangeiras / FKs sem índice de cobertura | 130 / 0 |
| Índices em `public` e `private` | 221 |
| Views comuns públicas (`security_invoker=true`) | 9 |
| Materialized views | 1, em `private` |
| Tipos ENUM | 30 |
| Funções de aplicação com `search_path` fixo | 18 |
| Policies com `auth.uid()` direto sem initplan | 0 |
| Triggers de usuário no schema `public` | 12 |
| Tabelas na publicação `supabase_realtime` | 15 |
| Buckets do SDD em Storage | 10 |
| Migrations remotas | 34 (24 históricas + 10 novas) |
| Jobs `pg_cron` ativos | 1 (refresh da MV a cada 6h) |
| Arquivos SQL em `supabase/` validados com parser PostgreSQL | 53, sem erro de sintaxe |

Os números foram consultados no projeto remoto e não são garantia de comportamento de todo consumidor externo. O [relatório de implantação](./docs/deployment-status.md) guarda testes, ressalvas e findings dos advisors; o [plano de implementação](./docs/implementation-plan.md) descreve o passo a passo e os critérios de aceite.

### Pendências relevantes — não ignorar

1. **Extensão deliberada do contrato:** `book_reviews` e os campos de leitura atual foram adicionados como migrations novas. O SDD ainda deve ser reconciliado para documentar a decisão e os contratos.
2. **Policies corrigidas:** `meeting_rsvps`, `host_prompt_votes` e `user_challenges` já têm regras explícitas de titular/admin; acesso anônimo direto a essas tabelas continua negado.
3. **Views endurecidas:** as nove views comuns usam `security_invoker=true`; o materialized view de livros foi retirado de `public` e fica em `private`.
4. **Extensões no schema `public`:** cinco alertas (`vector`, `pg_trgm`, `citext`, `unaccent`, `btree_gin`) continuam. Movê-las sem testes pode alterar resolução de tipos, operadores e RPCs.
5. **Edge Functions não implantadas:** `award_xp` agora é somente service-role; consumidores externos que chamem essa RPC diretamente precisam migrar para um endpoint de servidor validado. Revisar authorization, ownership, consentimento e secrets antes de deploy.
6. **Histórico CLI ainda exige reconciliação:** as dez migrations complementares correspondem exatamente às versões remotas `20261008…`, mas o baseline granular local `20260101…` não é igual às 24 entradas remotas `sdd_*`. Não execute `supabase db push` contra o projeto atual.
7. **Este repositório não é um aplicativo Next.js executável isoladamente:** não contém `package.json`, `supabase/config.toml` nem o arquivo gerado `src/lib/supabase/database.types.ts`.
8. **Avisos de performance remanescentes:** o advisor lista 108 índices sem uso medido e 215 achados de múltiplas policies permissivas no modelo RLS histórico. Os números são findings do linter, não contagens de tabelas distintas; não apagar índices/policies em massa sem tráfego e análise por tabela.

As mudanças foram registradas em migrations aditivas, sem alterar linhas existentes. As alterações de autorização e visibilidade estão intencionais e explicitadas neste README: especialmente o acesso a RPCs privilegiadas e a avaliação das views como o chamador.

## 3. Arquitetura proposta

O desenho conecta um frontend Next.js/TypeScript aos serviços Supabase. Autenticação gera identidade/JWT; requests de dados passam pelo PostgreSQL e suas policies RLS. Storage guarda mídia/documentos; Realtime publica alterações de um conjunto limitado de tabelas; Edge Functions executam rotinas de servidor em Deno. Integrações externas previstas incluem Resend, Stripe e OpenAI, além de referências de produto para Discord, YouTube, Google Calendar e Amazon Afiliados.

```text
Navegador / Next.js (supabase-js + @supabase/ssr)
           │ HTTPS / WSS + sessão/JWT
           ├── Supabase Auth
           ├── Postgres / Data API / RLS / funções / views
           ├── Storage (objetos e policies storage.objects)
           ├── Realtime (publicação supabase_realtime)
           └── Edge Functions (Deno; fonte no repositório, não implantada)
                       ├── OpenAI (embeddings/recomendações)
                       ├── Resend (newsletter)
                       └── Stripe (webhook/assinaturas)
```

**Separação de responsabilidades:** o schema relacional é a fonte de integridade e autorização por linha; o frontend consome clientes tipados e uma sessão de usuário; funções privilegiadas do servidor devem usar secrets somente no ambiente de execução do servidor. Uma chave `service_role` não deve ser incorporada a bundle de navegador, variável `NEXT_PUBLIC_*`, código cliente ou README. A chave publishable/anon é diferente de uma credencial administrativa e não serve para elevar permissões nem implantar migrations.

O diagrama é o desenho do SDD, não uma declaração de que todos os componentes externos ou clientes já foram configurados. Há um job pg_cron ativo para atualizar estatísticas comunitárias; o job HTTP de lembretes permanece suspenso até a Edge Function e sua autenticação serem configuradas.

## 4. Organização do repositório

```text
.
├── README.md                              # este guia
├── SDDBD2.md                              # SDD integral de referência
├── docs/
│   ├── deployment-status.md               # estado remoto, testes, advisors e riscos
│   ├── implementation-plan.md             # plano detalhado, passo a passo e aceite
│   ├── edge-functions-authorization.md      # contrato documental; sem deploy
│   ├── implementation-blockers.md         # decisões, resoluções e pendências do SDD
│   └── supabase-reference.md              # referências consultadas
├── scripts/
│   ├── build-remote-bundles.py            # concatena migrations em bundles ordenados
│   └── deploy-edge-functions.sh           # exemplo/script CLI; exige análise e secrets
├── supabase/
│   ├── migrations/                        # SQL-fonte, granular e revisável
│   │   └── blocked/                       # referências históricas; não executar
│   ├── deploy-bundles/                    # 6 bundles e manifests para revisão/bootstrap
│   ├── functions/                         # 10 fontes Edge Function e CORS compartilhado
│   ├── dev-seeds/                         # amostras opcionais; somente ambiente de dev
│   ├── seed.sql                           # seed núcleo Dom Casmurro
│   ├── seed_complement.sql                # dados complementares de exemplo
│   └── security-audit.sql                 # consultas read-only para checagem manual
└── src/
    ├── lib/supabase/
    │   ├── README.md                      # geração futura de database.types.ts
    │   ├── client.ts                      # browser client Next.js
    │   ├── server.ts                      # server client com cookies
    │   └── middleware.ts                   # atualização/validação da sessão
    └── types/
        ├── domain.ts                      # contratos de domínio base em TypeScript
        └── domain.complement.ts           # contratos complementares
```

### Função de cada grupo de arquivos

- **`SDDBD2.md`:** documento de origem para escopo e intenção. Se houver divergência entre um exemplo derivado e o banco remoto, confira primeiro esse SDD e o relatório de implantação.
- **`supabase/migrations/*.sql`:** DDL organizado por domínio e ordem lógica: extensões/tipos, tabelas do núcleo, políticas, funções/triggers, Realtime/Storage e módulos de expansão.
- **`supabase/migrations/blocked/`:** guarda trechos históricos que dependiam de relações/colunas agora implementadas por migrations numeradas. Não executar esses arquivos nem incluí-los em bundles.
- **`supabase/deploy-bundles/`:** concatena grupos de migrations-fonte para chamadas de implantação MCP com carga maior. Cada `.manifest.txt` informa a ordem/fontes incluídas no bundle.
- **`scripts/build-remote-bundles.py`:** recria os bundles com base nos arquivos SQL. Não altera o banco remoto.
- **`supabase/seed*.sql`:** conteúdo inicial do MVP e dados demonstrativos complementares; seeds não substituem as migrations de schema.
- **`supabase/functions/`:** código Deno destinado a Edge Functions. A presença do arquivo não significa que a função exista/deployou no projeto remoto.
- **`src/types/domain*.ts`:** interfaces/enums de domínio para código TypeScript; não são tipos gerados do schema PostgreSQL.
- **`src/lib/supabase/`:** exemplos de integração Next.js/SSR. Eles importam `database.types.ts`, arquivo gerado que ainda não está presente.
- **`supabase/security-audit.sql`:** SELECTs read-only para conferir RLS, policies, buckets, views, funções, extensões e cobertura de FKs.

## 5. Modelo de dados — inventário

O modelo contém **30 tabelas do núcleo** e **45 tabelas complementares**. Os nomes abaixo correspondem às migrations-fonte ativas.

### 5.1 Núcleo editorial e comunidade (30 tabelas)

| Domínio | Tabelas | Finalidade |
|---|---|---|
| Identidade | `profiles` | Perfil da aplicação ligado à identidade Supabase Auth; username, nome público, papel e onboarding. |
| Catálogo | `authors`, `books` | Autores e livros, metadados editoriais e campos usados para busca/recomendação. |
| Ciclos de leitura | `seasons`, `chapters` | Temporadas vinculadas a livros e blocos/capítulos de leitura. |
| Encontros | `meetings`, `meeting_rsvps` | Agenda de reuniões e inscrições de leitores. Lacuna histórica do SDD resolvida com leitura própria/admin e escrita pelo titular. |
| Progresso | `user_progress` | Estado e percentual de leitura por usuário/capítulo. |
| Discussão | `comments`, `reactions`, `host_prompts`, `host_prompt_votes` | Comentários hierárquicos, reações e perguntas/votações conduzidas pelo anfitrião. Votos individuais são acessíveis somente ao titular; agregados são expostos em view. |
| Quiz | `quiz_questions`, `quiz_attempts`, `quiz_answers` | Questões, tentativas e respostas associadas a capítulos e usuários. |
| XP/streak | `user_xp`, `xp_events`, `user_streaks` | Pontos por atividade, eventos de XP e sequência de dias/atividade. |
| Enquetes | `book_polls`, `book_poll_options`, `book_poll_votes` | Enquetes de escolha de livro, opções e voto individual. |
| Conquistas | `achievements`, `user_achievements` | Catálogo de conquistas e conquistas concedidas a usuários. |
| Notificações | `notifications`, `push_subscriptions` | Notificações dentro do app e subscriptions de push. |
| Desafios | `challenges`, `user_challenges` | Desafios e participação individual. Foi adicionada leitura própria/admin e escrita do titular em `user_challenges`. |
| Clubes criados por usuários | `user_clubs`, `user_club_members` | Grupos UGC, visibilidade e membros. **Não equivale** à tabela `public.clubs` referenciada em um objeto bloqueado. |
| Comentário em vídeo | `video_timed_comments` | Comentários associados ao segundo/trecho de um vídeo. |

### 5.2 Metadados de livros e leituras colaborativas (10 tabelas)

`content_warnings`, `book_content_warnings`, `book_content_warning_votes`, `mood_labels`, `book_mood_votes`, `book_mood_stats`, `editorial_picks`, `buddy_reads`, `buddy_read_members` e `buddy_read_checkpoints`.

Esse grupo suporta aviso de conteúdo, votos comunitários, humor/ritmo do livro, seleção editorial e leitura acompanhada entre pessoas. `book_mood_stats` é consolidada por funções/triggers a partir de votos.

### 5.3 Diário e listas pessoais (6 tabelas)

`reading_journal_entries`, `reading_journal_attachments`, `reading_lists`, `reading_list_items`, `reading_list_collaborators` e `user_up_next`.

O diário registra entradas de leitura com visibilidade; anexos apontam para mídia; listas possuem itens tipados e colaboradores; `user_up_next` guarda a próxima leitura do usuário. Policies diferenciam dados próprios, públicos e compartilhados com amigos/clubes.

### 5.4 Metas, milestones e médias de quiz (7 tabelas)

`milestones`, `user_milestone_progress`, `reading_goals`, `reading_goal_progress`, `challenge_prompts`, `user_quiz_averages` e `chapter_quiz_averages`.

Os milestones podem ser gerados para temporadas; metas acompanham progresso; médias agregadas são atualizadas após tentativas de quiz.

### 5.5 Feed e matching social (8 tabelas)

`feed_posts`, `feed_post_media`, `feed_post_likes`, `feed_post_comments`, `follows`, `user_reading_preferences`, `user_reading_embeddings` e `user_match_cache`.

O feed inclui visibilidade/escopo, anexos, curtidas e comentários. Preferências e embeddings são insumos de compatibilidade entre leitores; cache guarda resultados do matching. Trate embeddings e histórico de leitura como dados potencialmente pessoais.

### 5.6 Assinaturas e newsletter (8 tabelas)

`membership_plans`, `user_subscriptions`, `payment_events`, `user_membership_perks`, `newsletter_subscribers`, `newsletter_issues`, `newsletter_deliveries` e `affiliate_clicks`.

O schema descreve planos, status de assinatura, eventos de pagamento e rastreamento de newsletter/afiliados. **Não** configura produtos, preços, credenciais Stripe, domínio de envio, consentimento de marketing ou execução de cobranças por si só. A edição de boas-vindas do seed está em rascunho/não enviada.

### 5.7 Conteúdo extra, atividades e renderização (6 tabelas)

`chapter_extra_content`, `chapter_activities`, `chapter_activity_attempts`, `chapter_prompts`, `chapter_prompt_responses` e `social_render_jobs`.

Materiais podem ter referências de storage/URLs; atividades guardam configuração JSON; respostas guardam submissões; `social_render_jobs` representa fila/estado de renderização, não um worker de imagem já instalado.

### 5.8 Avaliações comunitárias (1 tabela adicionada)

`book_reviews` permite no máximo uma avaliação por usuário/livro. Guarda `rating` (0–5), `spice_level` (0–5), texto opcional até 20.000 caracteres, `contains_spoilers`, `deleted_at` e timestamps. Avaliações removidas logicamente não compõem as estatísticas públicas. RLS permite leitura anônima somente do conteúdo ativo; o titular/admin pode gerenciar conteúdo autorizado. A tabela está vazia no estado auditado.

### 5.9 Contexto de leitura dos clubes

`user_clubs` recebeu quatro campos opcionais: `current_book_id` e `current_season_id` (FKs com `ON DELETE SET NULL`), `current_started_at` e `current_ends_at`. Não houve backfill e as linhas preexistentes continuam válidas. A view `v_club_progress_panel` consulta este modelo existente, não uma nova tabela `public.clubs`.

### 5.10 Integridade e relações

As FKs e constraints são as definidas nas migrations, com contagem remota conferida de 130 FKs e índice cobrindo cada FK. Em alto nível, o fluxo relacional principal é:

```text
auth.users → profiles → user_progress / social / journal / XP
books → authors
seasons → books → chapters
chapters → meetings / comments / quizzes / activities / prompts
users + chapters → progress e tentativas de quiz
feed_posts → media / likes / comments
reading_lists → items / collaborators
membership_plans → user_subscriptions → payment_events
```

Essa figura é apenas um mapa conceitual; para nulabilidade, tipos, chaves compostas, ações `ON DELETE`, índices e constraints, consulte as migrations SQL correspondentes. Não use a tabela conceitual como substituto do DDL.

## 6. ENUMs e extensões PostgreSQL

### 6.1 Tipos ENUM (30)

**Núcleo (10):** `cycle_status`, `meeting_kind`, `meeting_status`, `notification_kind`, `poll_status`, `proposal_status`, `reaction_kind`, `shelf_status`, `user_role`, `xp_source`.

**Complementares (20):** `activity_kind`, `activity_status`, `content_warning_severity`, `editorial_pick_kind`, `extra_content_kind`, `feed_post_kind`, `feed_visibility`, `follow_status`, `journal_visibility`, `member_tier`, `mood_kind`, `newsletter_frequency`, `newsletter_status`, `pace_kind`, `payment_provider`, `reading_list_item_kind`, `reading_list_visibility`, `social_render_status`, `social_template_kind` e `subscription_status`.

Os literais permitidos são parte do contrato do banco. Ao adicionar um valor, crie migration deliberada e atualize tipos/consumidores; não escreva um valor arbitrário no frontend.

### 6.2 Extensões declaradas

As migrations declaram `pgcrypto`, `uuid-ossp`, `vector` (pgvector), `pg_trgm`, `citext`, `unaccent` e `btree_gin`. Elas habilitam recursos de UUID/criptografia, vetores, texto case-insensitive, busca aproximada/sem acentos e indexação. O Supabase advisor sinalizou cinco extensões no schema `public`; mover extensões é mudança estrutural e não foi feito.

## 7. RLS, Storage e limites de acesso

Todas as 76 tabelas do schema `public` têm RLS habilitado. As 135 policies implementam, conforme o módulo, padrões como:

- conteúdo editorial com leitura ampla e escrita administrativa;
- progressos, notificações, diário e preferências vinculados ao próprio usuário;
- comentários e itens sociais com regras de autoria, visibilidade, exclusão lógica ou relacionamento;
- listas e diários públicos/privados/compartilhados;
- assinaturas, pagamentos e newsletter com leituras/alterações administrativas ou do titular;
- uso de `public.is_admin()` em operações destinadas a admins.

RLS habilitado **não significa que toda tabela tenha policy**; nesta implementação, as três lacunas foram deliberadamente resolvidas. `meeting_rsvps` e `user_challenges` podem ser lidas pelo titular/admin e escritas pelo titular; `host_prompt_votes` permite que o titular gerencie somente seu próprio voto. As contagens dos votos de anfitrião vêm de uma view agregada. Testes anônimos confirmaram que as três tabelas privadas negam acesso direto.

### Buckets de Storage (10)

| Bucket | Público | Uso indicado pelo SDD |
|---|---:|---|
| `avatars` | Sim | Avatares, com escrita no diretório do próprio usuário. |
| `book-covers` | Sim | Capas editoriais, com escrita administrativa. |
| `manuscripts` | Não | Manuscritos/material privado. |
| `meeting-slides` | Sim | Slides dos encontros. |
| `journal-media` | Não | Anexos do diário no diretório do titular. |
| `chapter-extras` | Não | Extras de capítulos, leitura autenticada e escrita administrativa. |
| `feed-media` | Sim | Mídia do feed, com upload vinculado ao autor. |
| `newsletter-assets` | Sim | Assets de newsletter, com escrita administrativa. |
| `social-cards` | Sim | Cards compartilháveis; paths de upload usam diretório do autor. |
| `ebooks` | Não | E-books com leitura autenticada/URLs assinadas e escrita administrativa. |

A flag público/privado do bucket não substitui as policies de `storage.objects`, nem uma URL pública deve ser usada para conteúdo privado. Revise regras e caminhos de arquivos antes de permitir upload real.

## 8. Funções, triggers e views

### 8.1 Funções SQL principais

O schema contém 18 funções definidas em `public`, agrupadas por responsabilidade:

- **Identidade/admin:** `handle_new_user` cria profile, inicializa XP e streak; `is_admin` verifica o papel administrativo.
- **Gamificação:** `award_xp` registra eventos e acumula XP; `touch_streak` recalcula streak a partir de atividade.
- **Contadores sociais:** `bump_comment_likes`, `bump_comment_replies`, `bump_feed_post_counters` e `bump_journal_likes` atualizam agregados após mutações.
- **Leitura/quiz:** `refresh_user_quiz_averages`, `refresh_chapter_quiz_averages`, `refresh_reading_goal_progress` e `generate_milestones_for_season` consolidam métricas/metas.
- **Humor e avisos:** `refresh_book_mood_stats`, `trg_refresh_book_mood_stats` e `refresh_content_warning_votes` agregam votos.
- **Matching:** `match_books`, `match_readers` e `get_reader_matches` suportam busca por similaridade e consulta do cache.

O uso de `SECURITY DEFINER` deve ser entendido como execução com privilégios do proprietário da função. As 18 funções de aplicação auditadas agora têm `search_path` fixo; chamadas de cliente às rotinas privilegiadas de XP, milestones e estatística foram revogadas/restringidas. As duas funções `SECURITY DEFINER` internas em `private` retornam apenas agregados estreitos para as views invoker. Confira grants e consumers antes de adicionar qualquer nova RPC.

### 8.2 Triggers

As 12 triggers verificadas no schema `public` incluem sincronização de contadores de comentários/feed/diário, recálculo de médias de quiz, estatísticas de humor/avisos, progresso de metas e atualização de streaks. Há ainda `on_auth_user_created` no schema `auth`, anexada a `auth.users`, para inicialização do perfil de aplicação.

Triggers fazem trabalho dentro da transação que as dispara; falhas podem invalidar a operação original. Antes de mudar tabelas/eventos, revise função e trigger em conjunto e teste o comportamento de INSERT/UPDATE/DELETE.

### 8.3 Views implementadas

As nove views públicas comuns são `v_chapter_audience`, `v_season_ranking`, `v_comments_visible`, `v_host_prompt_results`, `v_video_timed_comment_stats`, `v_user_reading_overview`, `v_feed_post_counters`, `v_book_community_stats` e `v_club_progress_panel`. Todas usam `security_invoker=true`. O materialized view `mv_book_community_stats` fica em `private`; clientes devem consumir a view pública, não o objeto interno. As duas views de agregação de progresso/votos chamam helpers em `private` que nunca retornam linhas/IDs individuais.

O alerta anterior de `SECURITY DEFINER` nas views foi resolvido. `security_invoker` pode reduzir linhas visíveis em comparação à execução anterior pelo proprietário da view; valide a sessão/RLS de cada consumidor antes do lançamento.

### 8.4 Automação do refresh de estatísticas

A extensão `pg_cron` está habilitada (catalogada em `pg_catalog` neste projeto) e mantém os jobs no schema próprio `cron`; o job `refresh-mv-book-community-stats` executa `REFRESH MATERIALIZED VIEW CONCURRENTLY private.mv_book_community_stats` a cada seis horas. O registro ativo foi confirmado e o mesmo refresh foi executado manualmente com sucesso. Não foi criado o job HTTP de reminders: a função correspondente ainda não foi implantada e um agendamento sem credencial só geraria falhas. Consulte `docs/deployment-status.md`.

## 9. Realtime

A publicação `supabase_realtime` contém 15 tabelas: `comments`, `reactions`, `video_timed_comments`, `notifications`, `book_poll_votes`, `host_prompt_votes`, `feed_posts`, `feed_post_likes`, `feed_post_comments`, `reading_journal_entries`, `reading_list_items`, `user_match_cache`, `newsletter_issues`, `book_content_warning_votes` e `book_mood_votes`.

Os canais conceituais do SDD incluem comentários por capítulo, reações por comentário, comentários sincronizados com vídeo, notificações por usuário, polls, feed público/seguidores, diário, matches, votos de humor e edições de newsletter. A publicação da tabela não autoriza automaticamente o usuário a ler suas linhas: valide RLS, filtros do canal e autorização do cliente. Em particular, `host_prompt_votes` está na publicação, mas as linhas individuais continuam limitadas por RLS/grants; clientes devem usar o contrato agregado autorizado.

## 10. Edge Functions e integrações

### 10.1 Funções versionadas

| Função | Propósito previsto | Situação |
|---|---|---|
| `quiz-validate` | Receber respostas, validar quiz autenticado, registrar tentativa/respostas e conceder XP. | Fonte no repositório; não implantada. |
| `award-xp` | Conceder XP ao usuário autenticado a partir de uma origem reconhecida. | Fonte no repositório; não implantada. |
| `vote-next-book` | Registrar voto do usuário e atualizar contagem de opção. | Fonte no repositório; não implantada. |
| `scheduled-reminders` | Criar notificações de reuniões próximas a partir de RSVPs. | Fonte no repositório; não implantada; nenhum cron HTTP foi criado porque o endpoint e sua credencial de serviço ainda não existem. |
| `ai-recommendations` | Usar histórico de progresso/embeddings OpenAI para sugerir livros. | Fonte no repositório; não implantada; requer secret OpenAI. |
| `ai-user-embeddings` | Gerar vetor do snapshot de leitura e persistir embedding. | Fonte no repositório; RPC/schema agora existem; continua não implantada porque precisa validar autenticação, propriedade de `user_id`, privacidade do snapshot e secrets. |
| `match-readers` | Consultar similaridade entre leitores e atualizar cache. | Fonte no repositório; não implantada. |
| `newsletter-dispatch` | Enviar uma edição aos inscritos confirmados e registrar entregas. | Fonte no repositório; não implantada; requer Resend e autorização admin. |
| `stripe-webhook` | Verificar assinatura de webhook e sincronizar eventos/subscrições Stripe. | Fonte no repositório; não implantada; requer secrets Stripe e verificação de assinatura. |
| `social-render-card` | Criar job enfileirado para gerar card social. | Fonte no repositório; não implantada; não inclui worker de renderização. |

### 10.2 Por que o código não foi implantado

O contrato mínimo de autenticação/ownership para as dez funções está documentado em [`docs/edge-functions-authorization.md`](./docs/edge-functions-authorization.md). Ele é uma especificação para revisão, não prova que todos os handlers já a implementam.

A lista remota de Edge Functions continua vazia. O deploy literal foi suspenso após revisão porque alguns handlers usam `user_id`/`issue_id` recebidos no corpo sem comprovar propriedade/admin; a função de newsletter pode disparar para toda a lista. `verify_jwt` verifica a existência de um JWT, mas **não equivale** a verificar papel admin, propriedade, consentimento ou limites contra abuso. A dependência de schema de `ai-user-embeddings` agora existe, porém o handler ainda precisa validar ownership do `user_id` e tratar o snapshot como dado pessoal. `quiz-validate` foi ajustada na fonte para chamar `award_xp` por um cliente server-side separado, mas não foi implantada nem testada com identidade real.

Para um deploy seguro, faça revisão de autorização por endpoint, defina quem pode chamar cada ação, proteja chamadas agendadas/webhooks, configure secrets diretamente no ambiente Supabase e execute testes autenticados. Não coloque secrets em `.env` versionado ou em mensagens.

O script [`scripts/deploy-edge-functions.sh`](./scripts/deploy-edge-functions.sh) exige `SUPABASE_PROJECT_REF`, CLI Supabase autenticado e secrets já configurados. Por padrão, mantém verificação JWT; Stripe é enviado com `--no-verify-jwt` porque o handler implementa verificação própria de assinatura. **Não rode o script sem concluir a análise acima.**

### 10.3 Secrets e variáveis de ambiente

O SDD e o cliente referenciam estes nomes; configure somente os que a funcionalidade realmente usa:

- Cliente/browser e SSR: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
- Ferramentas/implantação: `SUPABASE_PROJECT_REF`.
- Somente servidor/Edge Function: `SUPABASE_SERVICE_ROLE_KEY` (privilegiada; jamais `NEXT_PUBLIC_*`).
- Integrações referenciadas: `OPENAI_API_KEY`, `RESEND_API_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `DISCORD_WEBHOOK_URL`, `YOUTUBE_API_KEY`, `AMAZON_AFFILIATE_TAG`.

Este inventário não significa que os secrets estejam configurados no Supabase, nem que todos os provedores estejam conectados. Não publique valores nos commits.

## 11. Seeds e dados demonstrativos

Os arquivos `supabase/seed.sql` e `supabase/seed_complement.sql` inicializam um catálogo demonstrativo baseado em **Dom Casmurro**, de Machado de Assis. Os dados remotos confirmados incluem autor, livro, uma temporada, cinco blocos de leitura, uma pergunta de quiz, um prompt de anfitrião, seis conquistas, avisos de conteúdo, rótulos de humor, estatística inicial, cinco milestones, materiais/atividade de demonstração, planos de membership e uma edição de newsletter.

A newsletter de seed **não foi disparada**. Materiais/URLs de exemplo no seed são placeholders demonstrativos e não garantem que os endereços estejam publicados. Os seeds originais foram distribuídos em quatro migrations remotas idempotentes. Avaliação/clube de exemplo ficam em `supabase/dev-seeds/` e não foram aplicados: o projeto remoto tinha zero perfis e zero admins, e amostras de usuário não devem ser adicionadas a produção. Use-os somente em banco de desenvolvimento após criar um perfil de teste/admin.

## 12. Auditoria de segurança e desempenho

Advisors e smoke tests foram executados depois de todas as dez migrations novas. Estado **final** observado em 8 de outubro de 2026:

| Categoria | Resultado final | Consequência prática |
|---|---|---|
| Views SECURITY DEFINER | 0; 9 views públicas `security_invoker=true` | View usa permissões/RLS do chamador; teste o contrato sob cada sessão. |
| RLS sem policy | 0 tabelas públicas | As três lacunas foram resolvidas por regras de titular/admin explicitadas. |
| `search_path` mutável nas 18 funções de aplicação | 0 | Todas têm path fixo `pg_catalog, public`. |
| FKs sem índice de cobertura | 0 / 130 FKs | Índice válido cobre cada FK; não remover em limpeza genérica. |
| Policies com `auth.uid()` direto | 0 | Uso do initplan `(select auth.uid())` aplicado sem alterar o predicado. |
| Extensões instaladas em `public` | 5 avisos | `vector`, `pg_trgm`, `citext`, `unaccent`, `btree_gin` permanecem; migração diferida por risco de compatibilidade. |
| Índices sem uso observado | 108 findings `INFO` | Sem carga representativa, `idx_scan=0` não basta para justificar remoção. |
| Múltiplas policies permissivas no modelo histórico | 215 findings | Achados por papel/ação, não por 215 tabelas; refatorar o baseline inteiro exige auditoria dedicada. Nenhuma das tabelas corrigidas nesta rodada aparece nos findings finais. |
| Índices duplicados | 0 após migration | `vtc_sec_idx` removido; `vtc_chapter_sec_idx` equivalente mantido. |

Links: [views SECURITY DEFINER](https://supabase.com/docs/guides/database/database-linter?lint=0010_security_definer_view), [RLS sem policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [`search_path` mutável](https://supabase.com/docs/guides/database/database-linter?lint=0011_function_search_path_mutable), [FK sem índice](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys), [índice sem uso](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index), [múltiplas policies](https://supabase.com/docs/guides/database/database-linter?lint=0006_multiple_permissive_policies), [duplicidade de índice](https://supabase.com/docs/guides/database/database-linter?lint=0009_duplicate_index), [extensão em public](https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public) e [auth em policies](https://supabase.com/docs/guides/database/postgres/row-level-security#call-functions-with-select).

Consulte os findings, testes HTTP e riscos restantes no [relatório de implantação](./docs/deployment-status.md). O arquivo [`supabase/security-audit.sql`](./supabase/security-audit.sql) contém consultas read-only para repetir parte das verificações.

## 13. Migrações e procedimento de operação

### 13.1 Como estão organizadas as migrations

Os arquivos `20260101…` são a fonte granular do baseline para revisão/recriação. O script gera seis grupos ordenados: `001_foundation`, `002_base_security_and_functions`, `003_realtime_and_storage`, `004_complement_schema`, `005_complement_security_functions_views` e `006_community_features_and_hardening`. O grupo 006 reúne as dez migrations novas; os seeds ficam separados.

O remoto registra **34 versões**: 24 entradas históricas `sdd_*` e dez migrations complementares `20261008…`. Os arquivos locais das dez migrations novas usam os mesmos números do histórico remoto. O baseline anterior continua com prefixos `20260101…` e não foi reconciliado para CLI.

### 13.2 Regra crítica para o banco que já está implantado

> **Não execute `supabase db push`, `supabase migration up` ou reaplicação manual do conjunto inteiro no projeto remoto atual até reconciliar o histórico.** O CLI pode entender que os arquivos locais ainda não foram aplicados e tentar recriar objetos existentes. Faça backup, compare `supabase_migrations.schema_migrations`, produza um baseline/repair controlado e teste em projeto descartável antes de sincronizar. Essa reconciliação não foi realizada nesta rodada.

Não use `supabase db reset` contra produção: esse comando recria o banco local e elimina os dados locais. Para qualquer mudança nova no remoto:

1. Defina a alteração e seu efeito em schema/API/RLS.
2. Faça migration nova e revisável, sem editar migrations que já foram aplicadas.
3. Teste em banco local/branch isolado após preparar a configuração CLI.
4. Faça backup/restore point de acordo com os procedimentos da equipe.
5. Confirme dependências e ordem; aplique somente a migration nova.
6. Verifique o resultado remoto, RLS, advisors e fluxo afetado.
7. Atualize tipos e documentação e versione a migration.

### 13.3 Gerar bundles para inspeção

Com Python 3 disponível:

```bash
python3 scripts/build-remote-bundles.py
```

O script concatena arquivos SQL em ordem fixa e gera manifests nos diretórios `supabase/deploy-bundles/`. Ele não aplica SQL nem substitui revisão, transação, backup ou reconciliação do histórico.

### 13.4 Preparar um ambiente local novo

Este repositório não inclui `supabase/config.toml`, `package.json` nem `database.types.ts`. Assim, não é possível executar a stack Supabase local ou compilar o helper Next.js apenas clonando o repositório, sem preparação adicional. Em ambiente isolado e não produtivo:

1. Instale Supabase CLI, Docker e dependências compatíveis com o app que será desenvolvido.
2. Defina a configuração local necessária sem sobrescrever os arquivos versionados sem revisão.
3. Use um projeto local/temporário vazio para validar a sequência das migrations.
4. Mantenha `supabase/migrations/blocked/` fora do caminho executável: os arquivos ali são referências históricas; os objetos equivalentes já foram criados pelas migrations `20261008…`.
5. Gere `database.types.ts` só depois de validar o schema-alvo.

Os comandos padrão do Supabase CLI são referências, não foram validados como procedimento de bootstrap deste repositório sem configuração adicional. Não os aplique ao projeto remoto existente como atalho.

## 14. Integração TypeScript/Next.js

Os helpers são exemplos de integração SSR:

- [`client.ts`](./src/lib/supabase/client.ts): `createBrowserClient`, URL e publishable/anon key expostas ao navegador.
- [`server.ts`](./src/lib/supabase/server.ts): `createServerClient` usando cookies de `next/headers`.
- [`middleware.ts`](./src/lib/supabase/middleware.ts): cliente associado às cookies da request e chamada `auth.getUser()` para atualizar/validar sessão.
- [`domain.ts`](./src/types/domain.ts): contratos para tipos base como perfil, capítulo, comentários, quiz e XP.
- [`domain.complement.ts`](./src/types/domain.complement.ts): tipos para humor, diário, listas, feed, matching, membership, newsletter e atividades.
- [`src/lib/supabase/README.md`](./src/lib/supabase/README.md): instrução para gerar tipos do banco.

O helper importa `./database.types`, mas esse arquivo ainda não existe no clone. Depois da reconciliação do histórico e da configuração do projeto, a geração documentada é:

```bash
supabase gen types typescript --linked > src/lib/supabase/database.types.ts
```

Gere os tipos contra o projeto correto, revise o diff e confirme que não há metadados/secrets anexados antes de commitar. Os tipos `domain*.ts` são modelos de produto mantidos no repositório; não substituem o tipo `Database` gerado a partir do schema remoto.

## 15. Checklist de verificação e prontidão

### Já executado nesta implantação

- [x] Comparar nomes de tabelas/ENUMs do SDD com migrations-fonte.
- [x] Validar sintaxe de 53 arquivos SQL (migrations, seeds, trechos históricos e bundles) com parser PostgreSQL.
- [x] Aplicar migrations executáveis em blocos e conferir histórico remoto.
- [x] Confirmar 76 tabelas e RLS habilitado em todas (75 do baseline + `book_reviews`).
- [x] Conferir contagens de policies, FKs, índices, views, triggers, Realtime e buckets.
- [x] Aplicar seeds e conferir contagens de conteúdo.
- [x] Executar advisors de segurança e performance após a última migration.
- [x] Testar Data API anônima: agregados públicos retornam HTTP 200 e acesso direto a votos/RSVP/desafios retorna `42501`.
- [x] Confirmar 9 views invoker, 18 funções com path fixo, 0 FK sem índice e 0 policy com `auth.uid()` direto.
- [x] Habilitar `pg_cron`, agendar refresh de `private.mv_book_community_stats` a cada 6 horas e validar manualmente o refresh concorrente.
- [x] Criar seeds de reviews/clube para dev, sem aplicá-los ao banco remoto (nenhum perfil/admin estava presente).
- [x] Confirmar que o repositório público não contém padrões de chaves literais na varredura realizada.
- [x] Publicar documentação e código no branch `main`.

### Ainda necessário antes de produção

- [ ] Atualizar o SDD com `book_reviews`, os quatro campos opcionais em `user_clubs` e as novas regras RLS.
- [ ] Testar policies com identidades de titular e admin em branch/projeto isolado; esta rodada não criou usuários reais de teste.
- [ ] Validar consumidores externos após a restrição da RPC `award_xp` ao backend `service_role`.
- [ ] Definir regras por endpoint, validar titularidade/role, consentimento, rate limits e segurança do job de newsletter.
- [ ] Configurar secrets de provedor no Supabase e confirmar domínios/webhooks de produção.
- [ ] Implantar e testar Edge Functions somente após a revisão acima.
- [ ] Criar o job HTTP de `scheduled-reminders` somente depois do deploy seguro da Edge Function, com autenticação serviço-a-serviço e observabilidade; não deixar cron falhando a cada hora.
- [ ] Reconciliar o histórico baseline remoto `sdd_*` com os arquivos locais `20260101…` antes de usar CLI para push.
- [ ] Preparar `supabase/config.toml`, dependências do aplicativo e tipos de banco gerados, se este repositório também passar a hospedar o frontend.
- [ ] Reexecutar advisors e testes de regressão depois de cada migration.

## 16. Referências operacionais

- [Supabase Database Views](https://supabase.com/docs/guides/database/views)
- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase Database Linter](https://supabase.com/docs/guides/database/database-linter)
- [Supabase Edge Functions](https://supabase.com/docs/guides/functions)
- [Supabase Storage](https://supabase.com/docs/guides/storage)
- [Supabase Realtime](https://supabase.com/docs/guides/realtime)
- [Documentação de views consultada durante a revisão](./docs/supabase-reference.md)

---

**Manutenção:** trate mudanças de schema como código: migration versionada, revisão, teste, execução controlada, verificação pós-deploy e atualização deste documento. Atualize as métricas remotas deste README sempre que houver novas migrations; não assuma que os números acima continuam atuais sem nova auditoria.

## 17. Plano detalhado e registro desta implementação

O documento [`docs/implementation-plan.md`](./docs/implementation-plan.md) é o plano de desenvolvimento completo: baseline, princípios de não regressão, cada migration na ordem de dependência, testes do catálogo e da Data API, critérios de aceite, riscos e caminho de recuperação.

### Ordem executada

1. Auditar SDD, repositório, histórico remoto, tabelas/RLS/views/funções/índices e advisors; preservar o estado inicial.
2. Criar `book_reviews` com constraints, soft-delete, índices e acesso limitado pelo RLS.
3. Adicionar quatro campos opcionais de leitura atual a `user_clubs`, sem criar `public.clubs` nem exigir backfill.
   Os seeds opcionais de review/clube foram criados para dev e não aplicados em produção, que ainda não tem perfis.
4. Definir ownership/admin para RSVP e desafios e manter votos individuais privados; publicar apenas agregados.
5. Criar views comunitárias, MV privado e snapshot invoker com validação do titular.
6. Harden de 9 views, 18 `search_path`s e grants nas rotinas privilegiadas; separar o cliente service-role do cliente com JWT na fonte `quiz-validate`.
7. Adicionar índices às 130 FKs sem cobertura, otimizar `auth.uid()` e consolidar policies novas sem sobreposição permissiva.
8. Tirar o MV de `public` e remover a cópia exata de um índice, conservando o índice equivalente.
9. Habilitar `pg_cron` e agendar o refresh concorrente do MV privado a cada seis horas; testar o refresh manual e conferir o job ativo.
10. Criar contrato documental das Edge Functions e seeds idempotentes apenas para desenvolvimento; não criar cron de reminders sem endpoint seguro.
11. Testar sintaxe, catálogo, views e controles Data API anônimos; atualizar bundles, status, blockers e README.

### Compatibilidade e riscos residuais

- DDL aditivo: nenhuma tabela/coluna existente foi apagada ou renomeada e nenhum dado de usuário foi migrado ou excluído.
- Contratos existentes de leitura podem retornar menos linhas porque as views agora observam as policies do chamador; esse é o comportamento seguro esperado, mas consumidores devem ser validados.
- `award_xp` não deve ser chamado diretamente do navegador: `EXECUTE` foi restrito a `service_role`. A função `quiz-validate` no repositório separa o cliente de request e o cliente privilegiado, porém **nenhuma Edge Function foi implantada**.
- Os testes HTTP anônimos cobrem leituras públicas e negação de dados privados; não simulam duas identidades autenticadas nem fluxo admin.
- Extensões em `public`, múltiplas policies históricas e índices sem tráfego representativo permanecem explicitamente registrados no [relatório final](./docs/deployment-status.md).
- O histórico baseline continua incompatível com `supabase db push`; os seis bundles são material de revisão/bootstrap, não autorização para reaplicar ao projeto existente. A migration de repair do anexo foi deliberadamente adiada: os 24 registros históricos já existem e inseri-los novamente não reconcilia os arquivos `20260101…`.

### Repetir verificações locais

```bash
python3 scripts/build-remote-bundles.py
python3 - <<'PY'
from pathlib import Path
from pglast import parse_sql
files = sorted(Path("supabase").rglob("*.sql"))
for path in files:
    parse_sql(path.read_text())
print(f"SQL válido: {len(files)} arquivos")
PY
git diff --check
```

Para validar o estado remoto, use as consultas read-only em [`supabase/security-audit.sql`](./supabase/security-audit.sql) e reexecute os advisors; consulte a API somente com requests GET em ambiente de verificação.
