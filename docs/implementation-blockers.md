# Bloqueios, decisões e pendências atuais

**Atualizado:** 2026-10-09. Este documento supersede a interpretação histórica de que todos os itens do anexo permanecem bloqueados; veja [`deployment-status.md`](./deployment-status.md) para a evidência remota e os testes realmente executados.

## Estado resumido

- **Resolvido no Supabase:** migration `20261009020600` aplicada e confirmada no histórico/catálogo; tabelas, RPCs, view e triggers novos foram inspecionados.
- **Resolvido no repositório:** tipos TypeScript gerados do schema pós-migration; fonte de 11 Edge Functions corrigida; smoke PGlite ampliado; workflows CI/deploy manual criados; SDD e README atualizados.
- **Não resolvido e não declarar sucesso:** deploy das Edge Functions, secrets de provedores, testes mutantes com Auth/Storage/Realtime real, proteção de reviewers no ambiente GitHub e reconciliação das migrations baseline.
- **Restrição decidida:** o usuário recusou criar um branch Supabase após ser informado do custo recorrente cotado de **US$ 0,01344 por hora**. Nenhum branch foi criado. O único projeto conectado é o alvo de produção; teste mutante foi omitido para preservar dados.

## Itens resolvidos no schema

| Item | Estado atual | Referência |
|---|---|---|
| Reviews ausentes | `public.book_reviews` existe com rating/spice, texto, spoiler, soft delete, unicidade, índices, grants e RLS. | `20261008214832_add_book_reviews.sql` + hardening posterior |
| Snapshot dependente de review | RPC restrita ao titular/autorização; helpers privados fora da Data API. | migrations `20261008214920…` e `20261008215324…` |
| Contexto de leitura em clubes | Quatro campos opcionais de livro/temporada/data em `public.user_clubs`; FKs com `ON DELETE SET NULL`. | `20261008214847_add_user_club_reading_context.sql` |
| Painel de clubes | View baseada em `user_clubs`/membros; nenhuma entidade `public.clubs` foi inventada. | `20261008214920_add_community_reading_views.sql` |
| RSVP, voto e progresso challenge sem policies | Policies de owner/admin aplicadas; leituras diretas anônimas bloqueadas onde apropriado. | migrations `20261008214859…` e consolidação |
| PII e consentimento | Perfil público projetado; privados via RPC do titular; timestamp mantido por trigger; grants de role/level restritos. | `20261008225152…`, `20261008225535…`, `20261008225856…` |
| Feed/quiz/spoiler | Views seguras; progresso autodeclarado explicitado como informação, não autorização de conteúdo realmente privado; validação de quiz no servidor. | hardening + migration `20261009020600` |
| XP e quizzes | Idempotência de XP/tentativas, média recalculada após mutações, rate-limit transacional e execução privilegiada restrita. | migration `20261009020600` |
| Metas e fim de leitura | Metas recalculadas por livro completo e `finished_at` carimbado pelo banco. | migration `20261009020600` |
| Likes do diário | `reading_journal_likes` criada; RLS titular; contador só por trigger. | migration `20261009020600` |
| Poll counters | Janela/opção validada e contadores atômicos; contagem preexistente reconciliada. | migration `20261009020600` |
| Reminder/newsletter/Stripe | Idempotência/lease e RPCs transacionais; handler newsletter exige Admin; Stripe valida assinatura. | migration `20261009020600` + fontes Edge |
| Tipos do schema | `src/lib/supabase/database.types.ts` gerado após aplicação. | snapshot remoto 2026-10-09 |

## Pendências e gates restantes

1. **Staging/Auth/Storage/Realtime:** executar `scripts/integration-smoke/test.ts` em branch/projeto descartável, com pelo menos dois usuários reais; cobrir leitor/admin e limpeza dos recursos. O harness está typechecked/linted/formatado e recusa explicitamente o ref de produção.
2. **Secrets e funções:** fornecer/configurar segredos de runtime por stores apropriados. Nomes exigidos no gate de deploy: `OPENAI_API_KEY`, `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` e `SCHEDULED_REMINDERS_SECRET`. Esta sessão não obteve seus valores nem listou/substituiu valores já salvos.
3. **Deploy:** inventário remoto continha zero Edge Functions. O workflow manual faz validação, compara o ref digitado e confere presença dos nomes dos secrets, mas ainda precisa de GitHub `SUPABASE_ACCESS_TOKEN`, variável `SUPABASE_PROJECT_REF` e proteção do ambiente `production` com reviewers. Nenhum deploy ocorreu.
4. **Clientes externos de `award_xp`:** localizar aplicações/serviços fora deste repositório que dependam de execução direta; redirecionar para handler servidor autenticado. Não restaurar grant a `anon`/`authenticated` sem novo desenho.
5. **Baseline CLI:** 24 entradas remotas `sdd_*` não mapeiam diretamente para migrations granulares locais `20260101…`. Projetar/revisar reconciliação num banco descartável antes de usar `supabase db push`. A migration mais nova tem ref `20261009020600`, mas isso não corrige o baseline histórico.
6. **Extensões:** os advisors mantêm 5 extensions em `public` (`vector`, `pg_trgm`, `citext`, `unaccent`, `btree_gin`). Mudar o schema delas exige staging com teste de tipos, operadores, índices e search path.
7. **Performance:** medir tráfego antes de investigar 113 índices `unused_index` e 165 findings de policies permissivas; não remover índices de FK nem refatorar o modelo por contadores do advisor isoladamente.
8. **Backup:** nenhum restore point manual foi criado para a rodada. Criar e validar ponto de restauração antes de futuras mudanças estruturais.
9. **Frontend:** repositório é de backend; integrar APIs/views/RPCs ao produto e confirmar compatibilidade do contrato é trabalho separado.
10. **Cron:** refresh da MV tem job `pg_cron`; não criar cron HTTP de reminders até deploy e autenticação serviço-a-serviço estarem testados.
11. **Seeds:** sementes de exemplo permanecem locais. O preflight encontrou 0 perfis e 0 admins antes da migration; não aplicar seed demonstrativo à produção.

## Decisão de domínio: `user_clubs` versus `clubs`

O texto histórico referenciava `public.clubs.current_book_id`, mas o schema remoto implementado usa `public.user_clubs`/`user_club_members` e não contém relação `public.clubs` separada. As quatro colunas opcionais e a view usam `user_clubs` para evitar duplicidade de estado. Se o produto quiser dois tipos distintos de clube, aprovar uma especificação nova de chaves, ownership, visibilidade, políticas e relação com membros antes de criar tabela.

## Arquivos `supabase/migrations/blocked/`

São trechos de referência histórica do SDD, não migrations executáveis. Não os aplique nem os inclua em bundles: alguns conservam nomes antigos, dependem de relações já criadas e duplicariam objetos.

## Segurança operacional

- Não use a publishable key como autorização de migração, service-role ou credencial de deploy.
- Não armazene chaves/segredos em GitHub público, `.env` versionado, README ou saída de CI.
- Não rode `db push`, `migration up`, `db reset` nem reaplique os bundles no projeto atual até reconciliação do baseline.
- Prefira migration corretiva aditiva a rollback destrutivo de schema já aplicado.
