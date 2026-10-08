# Banco de dados Supabase — Clube de Leitura

Repositório de banco de dados do **Clube de Leitura**, organizado a partir do documento de desenho [`SDDBD2.md`](./SDDBD2.md). Reúne migrations SQL revisáveis, seeds do MVP e de expansão, consultas de auditoria, bundles de execução, contratos TypeScript de domínio e fontes de Edge Functions.

> **Leia antes de usar:** o schema SQL e os seeds executáveis foram aplicados ao projeto Supabase listado abaixo, mas há pendências que não podem ser resolvidas sem completar o SDD ou autorizar alterações de segurança. O projeto **não deve ser considerado pronto para exposição ampla a usuários** até tratar os alertas de views `SECURITY DEFINER` e decidir o acesso às tabelas sem policies. Nenhuma Edge Function foi implantada.

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
| Dependências não definidas no SDD | [`docs/implementation-blockers.md`](./docs/implementation-blockers.md) |
| Referências de documentação Supabase | [`docs/supabase-reference.md`](./docs/supabase-reference.md) |

O repositório GitHub é público. **Não inclua nele** `.env`, credenciais, chaves de API, tokens, service-role keys, dados de usuários nem dumps do banco. Nenhum valor de credencial está documentado neste README.

## 2. Resumo executivo do estado atual

O escopo SQL definido de forma executável no SDD foi implantado no projeto remoto. Na revisão de 8 de outubro de 2026, a comparação entre o SDD e as migrations-fonte encontrou correspondência nominal de **75 tabelas** e **30 tipos ENUM**. A auditoria do catálogo remoto confirmou:

| Categoria | Quantidade encontrada |
|---|---:|
| Tabelas no schema `public` | 75 |
| Tabelas com Row Level Security habilitado | 75 |
| Policies RLS | 122 |
| Chaves estrangeiras | 126 |
| Índices catalogados | 150 |
| Views comuns | 7 |
| Tipos ENUM | 30 |
| Triggers de usuário no schema `public` | 12 |
| Tabelas na publicação `supabase_realtime` | 15 |
| Buckets do SDD em Storage | 10 |
| Migrations registradas remotamente | 24 |
| Arquivos SQL validados localmente pelo parser PostgreSQL | 34, sem erro de sintaxe |

Esses números descrevem o estado verificado naquela data; não garantem, por si só, segurança de aplicação, ausência de drift futuro ou funcionamento de integrações externas. Os detalhes, nomes de migrations e resultados dos Supabase Advisors estão no [relatório de implantação](./docs/deployment-status.md).

### Pendências relevantes — não ignorar

1. **Três tabelas têm RLS habilitado, mas o SDD não declara policy:** `public.meeting_rsvps`, `public.host_prompt_votes` e `public.user_challenges`. Sem policy, o PostgreSQL/Supabase nega o acesso via RLS por padrão. Nenhuma permissão foi inventada.
2. **Três objetos SQL estão em `supabase/migrations/blocked/`:** `mv_book_community_stats` e `build_user_reading_snapshot` dependem de `public.book_reviews`, que não é definida; `v_club_progress_panel` depende de `public.clubs.current_book_id`, que também não é definida. O SDD possui `public.user_clubs`, que não é a mesma relação.
3. **As sete views remotas foram sinalizadas como `SECURITY DEFINER` pelo advisor do Supabase.** Esse comportamento pode avaliar permissões/RLS como o proprietário da view, e não como o chamador. É o alerta de maior prioridade antes de expor os dados.
4. **Há funções `SECURITY DEFINER` executáveis por roles expostas e funções sem `search_path` fixo.** Também foram identificados avisos de desempenho para índices de FKs e expressões de policies RLS. Veja [Advisory checks](#12-auditoria-de-segurança-e-desempenho).
5. **As Edge Functions estão apenas versionadas:** o projeto remoto retornou zero funções implantadas. O código inclui dependências externas, operações privilegiadas e lacunas de autorização que requerem revisão.
6. **Histórico local/remoto de migrations diverge:** os arquivos locais têm prefixos `20260101…`, enquanto o Supabase MCP registrou migrations com versões `20261008…`. Não execute `supabase db push` contra o projeto existente antes de reconciliar o baseline e o histórico.
7. **Este repositório não é, hoje, um aplicativo Next.js executável isoladamente:** não contém `package.json`, `supabase/config.toml` nem o arquivo gerado `src/lib/supabase/database.types.ts`. Ele contém componentes e documentação de integração do banco.

A aplicação preservou o conteúdo do SDD literal quando possível e não adicionou schema ou autorização não especificados. Uma migration separada de hardening exige autorização porque pode alterar quem lê/escreve dados e como as views são expostas.

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

O diagrama é o desenho do SDD, não uma declaração de que todos os componentes externos, cron jobs ou clientes já foram configurados/ativados.

## 4. Organização do repositório

```text
.
├── README.md                              # este guia
├── SDDBD2.md                              # SDD integral de referência
├── docs/
│   ├── deployment-status.md               # estado remoto, contagens, alertas e bloqueios
│   ├── implementation-blockers.md         # relações/colunas ausentes no SDD
│   └── supabase-reference.md              # referências consultadas
├── scripts/
│   ├── build-remote-bundles.py            # concatena migrations em bundles ordenados
│   └── deploy-edge-functions.sh           # exemplo/script CLI; exige análise e secrets
├── supabase/
│   ├── migrations/                        # SQL-fonte, granular e revisável
│   │   └── blocked/                       # SQL válido que não pode rodar sem definições
│   ├── deploy-bundles/                    # 5 bundles e manifests para apply_migration
│   ├── functions/                         # 10 fontes Edge Function e CORS compartilhado
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
- **`supabase/migrations/blocked/`:** guarda trechos que dependem de relações/colunas ausentes. Não é uma pasta de migrations prontas para execução.
- **`supabase/deploy-bundles/`:** concatena grupos de migrations-fonte para chamadas de implantação MCP com carga maior. Cada `.manifest.txt` informa a ordem/fontes incluídas no bundle.
- **`scripts/build-remote-bundles.py`:** recria os bundles com base nos arquivos SQL. Não altera o banco remoto.
- **`supabase/seed*.sql`:** conteúdo inicial do MVP e dados demonstrativos complementares; seeds não substituem as migrations de schema.
- **`supabase/functions/`:** código Deno destinado a Edge Functions. A presença do arquivo não significa que a função exista/deployou no projeto remoto.
- **`src/types/domain*.ts`:** interfaces/enums de domínio para código TypeScript; não são tipos gerados do schema PostgreSQL.
- **`src/lib/supabase/`:** exemplos de integração Next.js/SSR. Eles importam `database.types.ts`, arquivo gerado que ainda não está presente.
- **`supabase/security-audit.sql`:** SELECTs para listar RLS, policies e buckets. É auditoria, não altera permissões.

## 5. Modelo de dados — inventário

O modelo contém **30 tabelas do núcleo** e **45 tabelas complementares**. Os nomes abaixo correspondem às migrations-fonte ativas.

### 5.1 Núcleo editorial e comunidade (30 tabelas)

| Domínio | Tabelas | Finalidade |
|---|---|---|
| Identidade | `profiles` | Perfil da aplicação ligado à identidade Supabase Auth; username, nome público, papel e onboarding. |
| Catálogo | `authors`, `books` | Autores e livros, metadados editoriais e campos usados para busca/recomendação. |
| Ciclos de leitura | `seasons`, `chapters` | Temporadas vinculadas a livros e blocos/capítulos de leitura. |
| Encontros | `meetings`, `meeting_rsvps` | Agenda de reuniões e inscrições de leitores. A tabela de RSVPs não recebeu policy no SDD. |
| Progresso | `user_progress` | Estado e percentual de leitura por usuário/capítulo. |
| Discussão | `comments`, `reactions`, `host_prompts`, `host_prompt_votes` | Comentários hierárquicos, reações e perguntas/votações conduzidas pelo anfitrião. A tabela de votos de prompts não recebeu policy no SDD. |
| Quiz | `quiz_questions`, `quiz_attempts`, `quiz_answers` | Questões, tentativas e respostas associadas a capítulos e usuários. |
| XP/streak | `user_xp`, `xp_events`, `user_streaks` | Pontos por atividade, eventos de XP e sequência de dias/atividade. |
| Enquetes | `book_polls`, `book_poll_options`, `book_poll_votes` | Enquetes de escolha de livro, opções e voto individual. |
| Conquistas | `achievements`, `user_achievements` | Catálogo de conquistas e conquistas concedidas a usuários. |
| Notificações | `notifications`, `push_subscriptions` | Notificações dentro do app e subscriptions de push. |
| Desafios | `challenges`, `user_challenges` | Desafios e participação individual. `user_challenges` não tem policy descrita no SDD. |
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

### 5.8 Integridade e relações

As FKs e constraints são as definidas nas migrations, com contagem remota conferida de 126 FKs. Em alto nível, o fluxo relacional principal é:

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

Todas as 75 tabelas do schema `public` têm RLS habilitado. As 122 policies implementam, conforme o módulo, padrões como:

- conteúdo editorial com leitura ampla e escrita administrativa;
- progressos, notificações, diário e preferências vinculados ao próprio usuário;
- comentários e itens sociais com regras de autoria, visibilidade, exclusão lógica ou relacionamento;
- listas e diários públicos/privados/compartilhados;
- assinaturas, pagamentos e newsletter com leituras/alterações administrativas ou do titular;
- uso de `public.is_admin()` em operações destinadas a admins.

RLS habilitado **não significa que toda tabela tenha policy**. `meeting_rsvps`, `host_prompt_votes` e `user_challenges` estão em RLS sem policy por lacuna do SDD e, portanto, são negadas para clientes comuns. A ferramenta não deve suprir isso com acesso presumido.

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

O uso de `SECURITY DEFINER` deve ser entendido como execução com privilégios do proprietário da função. O advisor encontrou funções nessa categoria expostas por `EXECUTE`; não assuma que o RLS protege uma chamada privilegiada sem uma análise de função, `search_path`, `GRANT` e validação do chamador.

### 8.2 Triggers

As 12 triggers verificadas no schema `public` incluem sincronização de contadores de comentários/feed/diário, recálculo de médias de quiz, estatísticas de humor/avisos, progresso de metas e atualização de streaks. Há ainda `on_auth_user_created` no schema `auth`, anexada a `auth.users`, para inicialização do perfil de aplicação.

Triggers fazem trabalho dentro da transação que as dispara; falhas podem invalidar a operação original. Antes de mudar tabelas/eventos, revise função e trigger em conjunto e teste o comportamento de INSERT/UPDATE/DELETE.

### 8.3 Views implementadas

As sete views comuns implantadas são `v_chapter_audience`, `v_season_ranking`, `v_comments_visible`, `v_host_prompt_results`, `v_video_timed_comment_stats`, `v_user_reading_overview` e `v_feed_post_counters`. Elas agregam progresso, ranking, visibilidade anti-spoiler, enquetes, comentários temporizados, overview de leitura e contadores do feed.

**Alerta:** os Supabase Advisors marcaram as sete como `SECURITY DEFINER`. Em particular, views que agregam progressos/diários podem expor informação além da policy subjacente. Não as trate como prontas para exposição externa até avaliar `security_invoker=true` ou uma estratégia equivalente. Essa correção altera o modo de autorização e exige migration aprovada.

## 9. Realtime

A publicação `supabase_realtime` contém 15 tabelas: `comments`, `reactions`, `video_timed_comments`, `notifications`, `book_poll_votes`, `host_prompt_votes`, `feed_posts`, `feed_post_likes`, `feed_post_comments`, `reading_journal_entries`, `reading_list_items`, `user_match_cache`, `newsletter_issues`, `book_content_warning_votes` e `book_mood_votes`.

Os canais conceituais do SDD incluem comentários por capítulo, reações por comentário, comentários sincronizados com vídeo, notificações por usuário, polls, feed público/seguidores, diário, matches, votos de humor e edições de newsletter. A publicação da tabela não autoriza automaticamente o usuário a ler suas linhas: valide RLS, filtros do canal e autorização do cliente.

## 10. Edge Functions e integrações

### 10.1 Funções versionadas

| Função | Propósito previsto | Situação |
|---|---|---|
| `quiz-validate` | Receber respostas, validar quiz autenticado, registrar tentativa/respostas e conceder XP. | Fonte no repositório; não implantada. |
| `award-xp` | Conceder XP ao usuário autenticado a partir de uma origem reconhecida. | Fonte no repositório; não implantada. |
| `vote-next-book` | Registrar voto do usuário e atualizar contagem de opção. | Fonte no repositório; não implantada. |
| `scheduled-reminders` | Criar notificações de reuniões próximas a partir de RSVPs. | Fonte no repositório; não implantada; não há cron remoto confirmado nesta rodada. |
| `ai-recommendations` | Usar histórico de progresso/embeddings OpenAI para sugerir livros. | Fonte no repositório; não implantada; requer secret OpenAI. |
| `ai-user-embeddings` | Gerar vetor do snapshot de leitura e persistir embedding. | Fonte no repositório; não implantada; depende de RPC/tabela bloqueada por falta de `book_reviews`. |
| `match-readers` | Consultar similaridade entre leitores e atualizar cache. | Fonte no repositório; não implantada. |
| `newsletter-dispatch` | Enviar uma edição aos inscritos confirmados e registrar entregas. | Fonte no repositório; não implantada; requer Resend e autorização admin. |
| `stripe-webhook` | Verificar assinatura de webhook e sincronizar eventos/subscrições Stripe. | Fonte no repositório; não implantada; requer secrets Stripe e verificação de assinatura. |
| `social-render-card` | Criar job enfileirado para gerar card social. | Fonte no repositório; não implantada; não inclui worker de renderização. |

### 10.2 Por que o código não foi implantado

A lista remota de Edge Functions estava vazia. O deploy literal foi suspenso após revisão porque algumas funções criam clientes com service role e usam `user_id`/`issue_id` recebidos no corpo sem comprovar que pertencem ao usuário autenticado; a função de newsletter pode disparar uma mensagem para toda a lista. `verify_jwt` verifica a existência de um JWT, mas **não equivale** a verificar papel admin, propriedade do recurso, consentimento de envio ou limites contra abuso. `ai-user-embeddings` também depende de `build_user_reading_snapshot`/`book_reviews`, ainda ausentes.

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

A newsletter de seed **não foi disparada**. Materiais/URLs de exemplo no seed são placeholders demonstrativos e não garantem que os endereços estejam publicados. Os seeds foram distribuídos em quatro migrations remotas idempotentes para aplicação; consulte o histórico em `docs/deployment-status.md`.

## 12. Auditoria de segurança e desempenho

Os advisors de Supabase foram executados depois da aplicação. Resultados reportados:

| Categoria | Resultado | Consequência prática |
|---|---|---|
| Views SECURITY DEFINER | 7, nível `ERROR` | Pode contornar RLS subjacente porque a view opera com privilégios do proprietário. Não expor antes de corrigir/revisar. |
| RLS sem policy | 3 tabelas, nível `INFO` | Tabelas ficam inacessíveis via RLS; exige política de produto explícita. |
| `search_path` mutável | 18 funções, nível `WARN` | Pode permitir resolução inesperada de objetos; fixar path em migração de hardening. |
| SECURITY DEFINER executável por `anon` | 9 funções | Revisar/revogar `EXECUTE` em rotinas privilegiadas conforme autorização desejada. |
| SECURITY DEFINER executável por `authenticated` | 9 funções | JWT sozinho não deve habilitar chamada privilegiada sem validação interna. |
| Extensões instaladas em `public` | 5 extensões | Aviso de namespace; migração pode alterar dependências/qualificações. |
| FKs sem índice de cobertura | 63 | Pode degradar joins, deletes e validação de FK em tabelas de maior volume. |
| Policies com avaliação repetida | 62 | Uso direto de `auth.*` pode ser avaliado por linha; revisar padrão `(select auth.uid())`/initplan. |

Links oficiais para os lints: [views SECURITY DEFINER](https://supabase.com/docs/guides/database/database-linter?lint=0010_security_definer_view), [RLS sem policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [`search_path` mutável](https://supabase.com/docs/guides/database/database-linter?lint=0011_function_search_path_mutable), [EXECUTE por anon](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [EXECUTE por authenticated](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [FK sem índice](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys), [extensão em public](https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public) e [auth em policies](https://supabase.com/docs/guides/database/postgres/row-level-security#call-functions-with-select).

A execução atual não aplicou remediações automáticas: adicionar policies, trocar comportamento de view, restringir RPCs ou adicionar índices pode mudar segurança, API e carga de escrita. Planeje esse trabalho como uma migration revisada, com teste e autorização explícita. O [relatório de implantação](./docs/deployment-status.md) registra os achados completos e a [auditoria read-only](./supabase/security-audit.sql) pode ajudar na revisão manual.

## 13. Migrações e procedimento de operação

### 13.1 Como estão organizadas as migrations

Os arquivos `20260101…` são a fonte granular para revisão e recriação futura. O script de bundles gera cinco grupos ordenados: `001_foundation`, `002_base_security_and_functions`, `003_realtime_and_storage`, `004_complement_schema` e `005_complement_security_functions_views`. Os seeds ficam separados desses bundles.

Na implantação remota desta tarefa, as instruções foram registradas pelo MCP em **24 versões `20261008…`**, com partes complementares separadas para limitar o tamanho de cada etapa. Portanto, as versões remotas não correspondem aos prefixos locais `20260101…`.

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
4. Confirme as migrations bloqueadas: elas devem permanecer fora do caminho executável enquanto as tabelas/colunas faltarem.
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
- [x] Validar sintaxe de 34 arquivos SQL com parser PostgreSQL.
- [x] Aplicar migrations executáveis em blocos e conferir histórico remoto.
- [x] Confirmar 75 tabelas e RLS habilitado em todas.
- [x] Conferir contagens de policies, FKs, índices, views, triggers, Realtime e buckets.
- [x] Aplicar seeds e conferir contagens de conteúdo.
- [x] Executar advisors de segurança e performance.
- [x] Confirmar que o repositório público não contém padrões de chaves literais na varredura realizada.
- [x] Publicar documentação e código no branch `main`.

### Ainda necessário antes de produção

- [ ] Completar o SDD para definir `book_reviews`, `public.clubs.current_book_id` e as policies ausentes.
- [ ] Autorizar e aplicar hardening das sete views e funções/privileges sinalizados.
- [ ] Definir regras por endpoint, validar titularidade/role, consentimento, rate limits e segurança do job de newsletter.
- [ ] Configurar secrets de provedor no Supabase e confirmar domínios/webhooks de produção.
- [ ] Implantar e testar Edge Functions somente após a revisão acima.
- [ ] Definir/deployar cron para `scheduled-reminders`, se esse comportamento for requerido.
- [ ] Reconciliar o histórico remoto `20261008…` com os arquivos locais `20260101…` antes de usar CLI para push.
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
