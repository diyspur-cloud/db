# Relatório de implantação e auditoria final

**Data:** 2026-10-08 (UTC−03:00)  
**Projeto Supabase:** `xjhehhfhhoomblcggjpk`  
**Repositório:** [`diyspur-cloud/db`](https://github.com/diyspur-cloud/db)
**Escopo:** migrations aditivas do anexo, hardening, refresh agendado da MV, testes e documentação. Nenhuma Edge Function foi implantada; jobs de reminders e seeds de amostra não foram aplicados.

**Backup/restore:** não foi criado backup ou restore point manual durante esta execução. As migrations foram aditivas e não alteraram/apagaram linhas existentes, mas deve-se criar um restore point antes de futuras mudanças estruturais, especialmente antes de mover extensões ou reconciliar o histórico.

> **Status:** as alterações de banco descritas aqui foram aplicadas. O banco já não tem os alertas críticos anteriores de views `SECURITY DEFINER` nem FKs sem índice. Isso **não** certifica o frontend nem integrações externas: revisar chamadas RPC, autenticação e uso de extensões antes de produção.

## Estado remoto final conferido

| Objeto/métrica | Total | Observação |
|---|---:|---|
| Tabelas em `public` | 76 | 75 do baseline + `book_reviews` |
| Tabelas com RLS ativo | 76 | todas as tabelas públicas do inventário |
| Policies em `public` | 135 | inclui regras explícitas para reviews, RSVP, votos e desafios |
| FKs em `public` | 130 | nenhuma FK ficou sem índice de cobertura |
| Índices em `public` + `private` | 221 | após remoção da cópia idêntica `vtc_sec_idx` |
| Views comuns em `public` | 9 | todas com `security_invoker=true` |
| Materialized views | 1 | `private.mv_book_community_stats`, fora do schema público da Data API |
| ENUMs | 30 | compatíveis com o baseline/SDD |
| Funções de aplicação com `search_path` fixo | 18 | `pg_catalog, public` |
| Policies com `auth.uid()` direto sem initplan | 0 | verificado no catálogo |
| Migrations remotas | 34 | 24 históricas + 10 desta implementação |
| Tabelas da publicação `supabase_realtime` | 15 | publicação preexistente preservada |
| Buckets do SDD | 10 | preservados |
| Jobs pg_cron ativos | 1 | refresh da MV privada a cada 6h; nenhum job HTTP de reminders |

A tabela `book_reviews` e os quatro campos de contexto foram criados sem migrar dados de usuário; `book_reviews` tinha 0 linhas e `user_clubs` tinha 0 linhas. O MV continha a linha do livro demonstrativo. O projeto tinha 0 perfis e 0 admins; por isso os seeds opcionais de reviews/clube não foram executados. Nenhuma migration apagou nem reescreveu linhas existentes.

## Implementação de schema e acesso

- Criada `public.book_reviews`: rating e nível de conteúdo 0–5, texto opcional até 20.000 caracteres, flag de spoiler, timestamps, soft-delete e unicidade por `(book_id, user_id)`.
- Acrescentadas a `public.user_clubs` as colunas opcionais `current_book_id`, `current_season_id`, `current_started_at` e `current_ends_at`; FKs usam `ON DELETE SET NULL`.
- `meeting_rsvps` e `user_challenges`: leitura própria/admin e escrita do titular, dividida por comando SQL. `host_prompt_votes`: somente o titular pode ler/alterar linhas individuais.
- `v_chapter_audience` e `v_host_prompt_results` retornam agregados por funções internas estreitas. A API não recebe permissão de leitura para as linhas individuais de votos.
- `v_book_community_stats` publica estatísticas comunitárias; o MV que a alimenta foi movido para `private`. `v_club_progress_panel` usa `user_clubs`, não uma tabela nova `public.clubs`.
- `build_user_reading_snapshot(uuid)` é `SECURITY INVOKER`, não executável por `anon` e restringe JWT autenticado ao próprio `p_user`.
- Foram endurecidas as 9 views, fixados os paths das 18 funções de aplicação e revogado `EXECUTE` de cliente nas rotinas privilegiadas afetadas.
- Criados índices para as 130 FKs segundo critério de prefixo; removido um índice B-tree redundante exato, mantendo `vtc_chapter_sec_idx`.
- Habilitado `pg_cron` e criado `refresh-mv-book-community-stats` (`0 */6 * * *`) para refresh concorrente de `private.mv_book_community_stats`.

Detalhes, sequência e critérios estão em [`docs/implementation-plan.md`](./implementation-plan.md). Os trechos originais em `supabase/migrations/blocked/` ficam apenas para rastreabilidade e não devem ser executados.

## Verificações executadas

### Catálogo

- Confirmados 76 tabelas, 135 policies, 130 FKs, 9 views invoker, MV dentro de `private` e 18 funções com path fixo.
- Nenhuma FK sem índice de cobertura.
- Nenhuma policy pública contém chamada direta a `auth.uid()` fora do padrão initplan verificado.
- Nenhuma das quatro tabelas de políticas corrigidas foi listada nos avisos restantes de múltiplas policies permissivas.
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

Não foram criados usuários de teste, nem realizadas inserções/updates para testar a policy de titulares em um banco com dados. O caminho autenticado titular/admin precisa de integração em branch/projeto isolado.

### Advisors finais

**Segurança:** o resultado final mantém 5 avisos `extension_in_public`: `vector`, `pg_trgm`, `citext`, `unaccent` e `btree_gin`. A mudança dessas extensões foi adiada por poder alterar resolução de tipos, operadores, search path e contratos de RPC. Não restou aviso do advisor para views `SECURITY DEFINER` nem para MV exposto no schema da Data API.

**Performance:**

- 108 avisos informativos `unused_index`; o contador `idx_scan` sem tráfego suficiente não prova que o índice é inútil. Em particular, índices de FK foram mantidos para operações de integridade e futuros filtros.
- 215 achados `multiple_permissive_policies` do desenho RLS histórico. São achados do linter por papel/ação (não 215 tabelas distintas); a refatoração abrangente do baseline foi evitada para não alterar o contrato de acesso fora do escopo. As policies novas deste trabalho não aparecem nesses achados.
- Nenhum achado `duplicate_index` após remover a cópia idêntica.

## Histórico e compatibilidade com CLI

O remoto contém 34 migrations: 24 entradas históricas `sdd_*` (incluindo seeds), mais dez versões `20261008…` detalhadas no plano. Os dez arquivos locais novos correspondem exatamente às versões remotas. O baseline granular local segue com prefixo `20260101…`, diferente dos nomes agregados já registrados remotamente.

**Não execute `supabase db push`, `supabase migration up` ou reaplique os bundles sobre o projeto atual** antes de reconciliar o baseline e o histórico. O gerador de bundles contém seis grupos para bootstrap/revisão de um ambiente novo; ele não é uma instrução de reaplicação no projeto atual.

## Edge Functions e integração da aplicação

Há fontes de Edge Functions no repositório, mas a lista remota de funções implantadas continua vazia. O contrato de autorização para os dez endpoints está em [`edge-functions-authorization.md`](./edge-functions-authorization.md). `quiz-validate` foi ajustada para usar cliente separado service-role apenas para `award_xp`; isso é uma alteração de fonte, não um deploy. O RPC agora não pode ser chamado diretamente por `anon`/`authenticated`, e consumidores fora deste repositório devem migrar para uma camada de servidor validada.

`ai-user-embeddings` segue fora do script de deploy: seu RPC agora existe, mas o handler ainda recebe `user_id` sem demonstrar a propriedade do usuário e pode tratar snapshot potencialmente sensível. Newsletter, Stripe, secrets, rate limiting e autorização admin também precisam de revisão antes de qualquer deploy.

## Referências de mudança

- Migrations complementares: `supabase/migrations/20261008*.sql` (dez migrations).
- Job de refresh pg_cron: `refresh-mv-book-community-stats`; cron de reminders deliberadamente não criado.
- Seeds de demonstração de reviews/clube: `supabase/dev-seeds/`, somente para ambiente de desenvolvimento.
- Plano de desenvolvimento: [`implementation-plan.md`](./implementation-plan.md).
- Pendências históricas e decisão sobre `public.clubs`: [`implementation-blockers.md`](./implementation-blockers.md).
- Auditoria SQL read-only: [`supabase/security-audit.sql`](../supabase/security-audit.sql).
- Supabase CLI: use somente depois de reconciliar o histórico de baseline.

Nenhuma chave, token, service-role key ou dado pessoal foi gravado nesta documentação.
