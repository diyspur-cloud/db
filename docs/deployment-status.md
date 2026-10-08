# Relatório de implantação e double check

**Data:** 2026-10-08 (UTC−03:00)  
**Projeto Supabase:** `xjhehhfhhoomblcggjpk`  
**Escopo:** implementação do SDD `SDDBD2.md`, sem inventar schema ou regras ausentes.

## Estado aplicado e verificado

O schema e os seeds foram aplicados remotamente. Comparação automatizada dos nomes no SDD com as migrations-fonte: **75/75 tabelas** e **30/30 ENUMs** correspondem, sem tabelas ou enums extras nas migrations ativas. O parser PostgreSQL validou **34 arquivos SQL**, sem erros de sintaxe.

| Item | Verificação remota |
|---|---:|
| Tabelas públicas | 75 |
| Tabelas com RLS habilitado | 75 |
| Policies RLS | 122 |
| Chaves estrangeiras | 126 |
| Índices catalogados | 150 |
| Views | 7 |
| ENUMs | 30 |
| Triggers de usuário | 12 |
| Tabelas na publicação Realtime | 15 |
| Buckets especificados | 10 |
| Seeds registrados | 4 migrations idempotentes |

Os seeds confirmados contêm 1 autor, 1 livro, 1 temporada, 5 capítulos, 1 quiz, 1 prompt de anfitrião, 6 conquistas, 10 avisos de conteúdo, 13 rótulos de humor, 4 avisos associados ao livro, 5 milestones, 2 conteúdos extras, 1 atividade, 1 prompt de caderno, 4 planos de assinatura e 1 edição de newsletter **não enviada**.

O histórico remoto contém migrations executadas por blocos: `sdd_001`–`sdd_003`, `sdd_004a`–`sdd_004i`, `sdd_005a`–`sdd_005c`, `sdd_006`–`sdd_008c` e `sdd_009`–`sdd_010c`. O último seed foi registrado com o nome `sdd_010c_seed_plans_newsletter_retry` após uma colisão de timestamp no histórico; a instrução era idempotente e foi verificada pelos contadores.

## Pendências estritas do SDD

1. **Três tabelas têm RLS habilitado, mas não possuem policy no documento:** `public.meeting_rsvps`, `public.host_prompt_votes` e `public.user_challenges`. Foram mantidas sem policies, exatamente como especificado. Sem policy, o acesso via RLS fica negado por padrão; uma regra de leitura/escrita não foi inventada.
2. **Três objetos SQL bloqueados por relações/colunas ausentes:** `mv_book_community_stats` e `build_user_reading_snapshot` dependem de `public.book_reviews`; `v_club_progress_panel` depende de `public.clubs.current_book_id`. O SDD não define `book_reviews`, a tabela `public.clubs` nem essa coluna; os objetos permanecem em `supabase/migrations/blocked/`.
3. **Histórico CLI:** o Supabase MCP gerou versões remotas `20261008…`, diferentes dos prefixos `20260101…` dos arquivos locais. Não rode `supabase db push` diretamente contra este projeto antes de reconciliar o histórico/baseline para evitar reaplicações conflitantes.

## Edge Functions

Há dez fontes de Edge Functions no repositório; **nenhuma está implantada** no projeto. O listado remoto estava vazio. O deploy foi deixado pendente porque:

- integrações podem exigir secrets do projeto (`OPENAI_API_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `RESEND_API_KEY`), e os valores não foram incluídos nem transferidos;
- `ai-user-embeddings` chama `build_user_reading_snapshot`, que depende da tabela `book_reviews` ausente;
- a revisão estática encontrou endpoints que usam `SUPABASE_SERVICE_ROLE_KEY` e aceitam identificadores enviados no corpo sem validar que pertençam ao usuário autenticado. Em especial, o despacho de newsletter pode enviar para todos os inscritos confirmados e não contém verificação de administrador. Implantá-los literalmente daria acesso a operações privilegiadas a qualquer chamador com JWT válido.

As fontes foram preservadas sem alterações para respeitar a fidelidade estrita solicitada. Antes do deploy é necessário autorizar ajustes de autorização e configurar os secrets na plataforma Supabase — não enviar valores de secrets no chat ou versioná-los.

## Advisory checks do Supabase

Executados após a implantação por meio dos advisors de segurança e performance. Alertas reportados:

- **7 views SECURITY DEFINER** — linter nível `ERROR`; views comuns podem executar com os privilégios do proprietário e contornar RLS. Revisão: [Supabase linter 0010](https://supabase.com/docs/guides/database/database-linter?lint=0010_security_definer_view).
- **3 tabelas RLS sem policies** — nível `INFO`; correspondem aos três itens acima. [Linter 0008](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).
- **18 funções com `search_path` mutável** e **9 funções SECURITY DEFINER executáveis por `anon` e `authenticated`** — requerem revisão de `search_path` e privilégios `EXECUTE`. [Linter 0011](https://supabase.com/docs/guides/database/database-linter?lint=0011_function_search_path_mutable), [linter 0028](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [linter 0029](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
- **5 extensões no schema `public`** — [linter 0014](https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public).
- **63 FKs sem índice de cobertura** — [linter 0001](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys).
- **62 policies com avaliação de funções `auth.*` linha a linha** — oportunidade de otimização por initplan; [guia de RLS](https://supabase.com/docs/guides/database/postgres/row-level-security#call-functions-with-select).

Esses advisories refletem o SQL literal do SDD; não foram alterados porque as instruções exigiam não modificar schema ou lógica. Recomendações típicas incluem `security_invoker=true` nas views, `SET search_path` explícito e restrição de `EXECUTE` nas funções privilegiadas, mas isso exige uma migration de hardening separada, fora da especificação literal. Não disponibilize o projeto a usuários finais antes de decidir como tratar os alertas `ERROR` de views.

## Segredos

Nenhum valor de secret foi gravado no repositório ou incluído neste relatório. O repositório GitHub configurado é público; mantenha nele apenas código e configuração não sensível.
