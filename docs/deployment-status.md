# Relatório de implantação e auditoria final

**Data:** 2026-10-08 (UTC−03:00)  
**Projeto Supabase:** `xjhehhfhhoomblcggjpk`  
**Repositório:** [`diyspur-cloud/db`](https://github.com/diyspur-cloud/db)
**Escopo:** migrations aditivas do anexo, refresh agendado da MV, hardening de autorização/PII/quiz/spoilers/membership/consentimento, suíte PGlite e documentação. Nenhuma Edge Function foi implantada; jobs de reminders e seeds de amostra não foram aplicados.

**Backup/restore:** não foi criado backup ou restore point manual durante esta execução. As migrations não apagaram linhas; a migration de autorização normalizou `comments.min_percent` apenas onde o valor legado era `NULL` (`100` para spoiler, `0` nos demais casos). Nenhum dado demonstrativo de usuário foi inserido. Criar restore point antes de futuras mudanças estruturais, especialmente antes de mover extensões ou reconciliar o histórico.

> **Status:** todas as alterações descritas aqui foram aplicadas ao projeto remoto e registradas localmente. Não há funções/views `SECURITY DEFINER` expostas no schema `public`, e não há FKs sem índice. A suíte PGlite verifica regressões em ambiente isolado; isso **não** certifica Auth real, frontend, Edge Functions nem integrações externas.

## Estado remoto final conferido

| Objeto/métrica | Total | Observação |
|---|---:|---|
| Tabelas em `public` | 76 | 75 do baseline + `book_reviews` |
| Tabelas com RLS ativo | 76 | todas as tabelas públicas do inventário |
| Policies em `public` | 155 | inclui regras explícitas de ownership, privacidade, membership e policies por operação |
| FKs em `public` | 130 | nenhuma FK ficou sem índice de cobertura |
| Índices em `public` + `private` | 222 | após remoção da cópia idêntica `vtc_sec_idx` e índice de rate-limit |
| Views comuns em `public` | 12 | todas com `security_invoker=true` |
| Materialized views | 1 | `private.mv_book_community_stats`, fora do schema público da Data API |
| ENUMs | 30 | compatíveis com o baseline/SDD |
| Funções `public`/`private` com `search_path` fixo | 32 | inclui helpers com referências de esquema explícitas |
| Policies com `auth.uid()` direto sem initplan | 0 | verificado no catálogo |
| Triggers de aplicação em `public` | 13 | inclui timestamp LGPD gerado pelo banco |
| Migrations remotas | 37 | 24 históricas + 13 complementares |
| Tabelas da publicação `supabase_realtime` | 15 | publicação preexistente preservada |
| Buckets do SDD | 10 | preservados |
| Jobs pg_cron ativos | 1 | refresh da MV privada a cada 6h; nenhum job HTTP de reminders |
| Arquivos SQL validados | 56 | sintaxe parseada com PostgreSQL `pglast` |

A tabela `book_reviews` e os quatro campos de contexto foram criados sem migrar dados de usuário; `book_reviews` tinha 0 linhas e `user_clubs` tinha 0 linhas. O MV continha a linha do livro demonstrativo. O projeto tinha 0 perfis e 0 admins; por isso os seeds opcionais de reviews/clube não foram executados. Nenhuma migration apagou linhas; além da normalização documentada de `comments.min_percent`, não foi executado DML para reescrever registros de usuário.

## Implementação de schema e acesso

- Criada `public.book_reviews`: rating e nível de conteúdo 0–5, texto opcional até 20.000 caracteres, flag de spoiler, timestamps, soft-delete e unicidade por `(book_id, user_id)`.
- Acrescentadas a `public.user_clubs` as colunas opcionais `current_book_id`, `current_season_id`, `current_started_at` e `current_ends_at`; FKs usam `ON DELETE SET NULL`.
- `meeting_rsvps` e `user_challenges`: leitura própria/admin e escrita do titular, dividida por comando SQL. `host_prompt_votes`: somente o titular pode ler/alterar linhas individuais.
- `v_chapter_audience` e `v_host_prompt_results` retornam agregados por funções internas estreitas. A API não recebe permissão de leitura para as linhas individuais de votos.
- `v_book_community_stats` publica estatísticas comunitárias; o MV que a alimenta foi movido para `private`. `v_club_progress_panel` usa `user_clubs`, não uma tabela nova `public.clubs`.
- `build_user_reading_snapshot(uuid)` é `SECURITY INVOKER`, não executável por `anon` e restringe JWT autenticado ao próprio `p_user`.
- Foram endurecidas 12 views e 32 funções verificadas; as RPCs públicas de perfil/consentimento são `SECURITY INVOKER`, com helper de leitura estrito em schema `private`.
- Comentários e posts do feed aplicam proteção contra spoilers por progresso; a view pública de quiz exclui resposta/explicação e a fonte `quiz-validate` valida a tentativa no servidor, mas ainda não foi implantada.
- Grants de `profiles` protegem PII, `level`, `role` e o timestamp de consentimento; um trigger server-side define/limpa `lgpd_consent_at` e `updated_at`.
- Membership de clube só permite self-join como `member`; apenas owner atribui papéis (`owner`, `moderator`, `member`). Diário e respostas de prompts usam policies separadas por comando SQL.
- `feed-media` é privado (0 objetos no momento da auditoria); mídias extras permanecem em buckets privados.
- Criados índices para as 130 FKs segundo critério de prefixo; removido um índice B-tree redundante exato, mantendo `vtc_chapter_sec_idx`.
- Habilitado `pg_cron` e criado `refresh-mv-book-community-stats` (`0 */6 * * *`) para refresh concorrente de `private.mv_book_community_stats`.

Detalhes, sequência e critérios estão em [`docs/implementation-plan.md`](./implementation-plan.md). Os trechos originais em `supabase/migrations/blocked/` ficam apenas para rastreabilidade e não devem ser executados.

## Verificações executadas

### Catálogo

- Confirmados 76 tabelas/RLS, 155 policies, 130 FKs, 12 views invoker, MV em `private` e 32 funções verificadas com path fixo.
- Nenhuma FK sem índice de cobertura.
- Nenhuma policy pública contém chamada direta a `auth.uid()` fora do padrão initplan verificado.
- Nenhuma das tabelas tocadas pelas policies de membership, diário e respostas de prompts aparece nos findings finais de múltiplas policies permissivas.
- Os dois RPCs públicos de perfil/consentimento são `SECURITY INVOKER`; helper de perfil estrito fica em `private`. O timestamp LGPD é gerado/limpo pelo trigger.
- `authenticated` pode atualizar apenas `lgpd_consent`, não `lgpd_consent_at`, `updated_at`, `role` ou `level`; `user_club_members.role` está limitado a `owner`/`moderator`/`member`.
- MV acessível pelo SELECT necessário à view invoker, mas `private` sem `CREATE` para `anon`.
- Cópia `vtc_sec_idx` removida; `vtc_chapter_sec_idx` mantido.
- Job pg_cron ativo confirmado como `jobid=1`, com comando para refresh concorrente da MV privada. O refresh manual único também foi executado sem erro; a primeira execução automática ainda aguarda o próximo horário programado.

### Data API (GET anônimo, sem escrita)

| Requisição | Status | Resultado |
|---|---:|---|
| `v_book_community_stats` | 200 | Dom Casmurro; 0 avaliações |
| `v_chapter_audience` | 200 | contagens agregadas |
| `v_host_prompt_results` | 200 | contagens agregadas |
| `book_reviews` | 200 | conjunto vazio, acesso de leitura |
| `host_prompt_votes` direto | 401 / SQLSTATE `42501` | acesso negado |
| `meeting_rsvps` direto | 401 / SQLSTATE `42501` | acesso negado |
| `user_challenges` direto | 401 / SQLSTATE `42501` | acesso negado |

Não foram criados usuários reais nem gravadas linhas de teste no projeto remoto. Para testar os caminhos positivos/negativos sem alterar produção, `scripts/security-smoke/test.mjs` executa as três migrations em PostgreSQL WASM e simula `anon` e dois usuários autenticados por claims; cobre PII, setter/timestamp LGPD, progress unlock de spoiler, feed privado, quiz, listas, membership e atribuição de role pelo owner. Ainda é necessário repetir com usuários/sessões Supabase Auth reais em branch ou projeto isolado, e validar Storage e Edge Functions.

### Advisors finais

**Segurança:** o resultado final mantém somente 5 avisos `extension_in_public`: `vector`, `pg_trgm`, `citext`, `unaccent` e `btree_gin`. Não há aviso de SECURITY DEFINER exposto/callable no schema `public`, nem de MV exposto pela Data API. As funções privilegiadas necessárias usam `search_path` vazio, schemas explícitos e escopo próprio/limitado; helpers ficam em `private`.

**Performance:**

- 109 avisos informativos `unused_index`; o contador `idx_scan` sem tráfego suficiente não prova que o índice é inútil. Em particular, índices de FK foram mantidos para operações de integridade e futuros filtros.
- 165 achados `multiple_permissive_policies` do desenho RLS histórico. São achados do linter por papel/ação (não 165 tabelas distintas); a refatoração abrangente do baseline foi evitada para não alterar o contrato fora do escopo. As policies de membership, diário e respostas de prompts corrigidas não aparecem nesses findings.
- Nenhum achado `duplicate_index` após remover a cópia idêntica.

## Histórico e compatibilidade com CLI

O remoto contém 37 migrations: 24 entradas históricas `sdd_*` (incluindo seeds), mais 13 versões `20261008…`. Os arquivos locais novos correspondem exatamente às versões remotas: `20261008225152_harden_core_authorization`, `20261008225535_prevent_client_privilege_escalation` e `20261008225856_encapsulate_profile_consent_privilege` completam a sequência. O baseline granular local segue com prefixo `20260101…`, diferente dos nomes agregados já registrados remotamente.

**Não execute `supabase db push`, `supabase migration up` ou reaplique os bundles sobre o projeto atual** antes de reconciliar o baseline e o histórico. O gerador de bundles contém seis grupos para bootstrap/revisão de um ambiente novo; ele não é uma instrução de reaplicação no projeto atual.

## Edge Functions e integração da aplicação

Há fontes de Edge Functions no repositório, mas a lista remota de funções implantadas continua vazia. O contrato de autorização para os dez endpoints está em [`edge-functions-authorization.md`](./edge-functions-authorization.md). `quiz-validate` foi ajustada para usar cliente separado service-role apenas para `award_xp`; isso é uma alteração de fonte, não um deploy. O RPC agora não pode ser chamado diretamente por `anon`/`authenticated`, e consumidores fora deste repositório devem migrar para uma camada de servidor validada.

`ai-user-embeddings` segue fora do script de deploy: seu RPC agora existe, mas o handler ainda recebe `user_id` sem demonstrar a propriedade do usuário e pode tratar snapshot potencialmente sensível. Newsletter, Stripe, secrets, rate limiting e autorização admin também precisam de revisão antes de qualquer deploy.

## Referências de mudança

- Migrations complementares: `supabase/migrations/20261008*.sql` (13 migrations, incluindo três de hardening final).
- Job de refresh pg_cron: `refresh-mv-book-community-stats`; cron de reminders deliberadamente não criado.
- Seeds de demonstração de reviews/clube: `supabase/dev-seeds/`, somente para ambiente de desenvolvimento.
- Plano de desenvolvimento: [`implementation-plan.md`](./implementation-plan.md).
- Pendências históricas e decisão sobre `public.clubs`: [`implementation-blockers.md`](./implementation-blockers.md).
- Auditoria SQL read-only: [`supabase/security-audit.sql`](../supabase/security-audit.sql).
- Supabase CLI: use somente depois de reconciliar o histórico de baseline.

Nenhuma chave, token, service-role key ou dado pessoal foi gravado nesta documentação.
