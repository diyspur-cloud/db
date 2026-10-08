# Bloqueios históricos, decisões e pendências

A auditoria anterior encontrou referências a relações/colunas ausentes no SDD e guardou SQL derivado em `supabase/migrations/blocked/`. Em 8 de outubro de 2026, parte do escopo foi implementada com migrations aditivas revisáveis. Este documento substitui a interpretação antiga de que todos os itens abaixo permanecem bloqueados.

## Resolvido no banco

| Item | Estado atual | Migration/decisão |
|---|---|---|
| `book_reviews` ausente | Criada em `public.book_reviews`, com rating, nível de conteúdo, texto, spoiler, timestamps, soft-delete, constraints, RLS e policies. | `20261008214832_add_book_reviews.sql` |
| Snapshot pessoal dependia de reviews | `public.build_user_reading_snapshot(uuid)` agora existe como função `SECURITY INVOKER`; um JWT autenticado só pode solicitar seu próprio snapshot; `anon` não tem `EXECUTE`. | `20261008214920_add_community_reading_views.sql` e hardening posterior |
| Estatísticas agregadas por livro | MV criado e movido para `private`; o contrato REST é `public.v_book_community_stats`. | `20261008214920_add_community_reading_views.sql` + `20261008215324_harden_community_data_access.sql` |
| Contexto de leitura de clubes | Quatro campos opcionais adicionados a `public.user_clubs`; linhas já existentes permanecem válidas. | `20261008214847_add_user_club_reading_context.sql` |
| Painel de clube | A view `v_club_progress_panel` consulta `user_clubs`, `user_club_members`, progresso, livros e temporadas existentes. | `20261008214920_add_community_reading_views.sql` |
| Três tabelas RLS sem policies | Rules explícitas de titular/admin implementadas para RSVP, votos e progresso de desafios. | `20261008214859_restore_missing_rls_policies.sql` + consolidação posterior |

## Decisão de modelo: `public.clubs` versus `public.user_clubs`

O documento/trecho histórico usa `public.clubs.current_book_id`, mas o esquema implementado contém `public.user_clubs` e `user_club_members`, sem uma relação separada `public.clubs`. Para não inventar uma segunda entidade nem duplicar estado, as novas colunas e a view usam `user_clubs`.

Se a regra de produto realmente exige duas classes distintas de clube, o responsável pelo SDD precisa aprovar e especificar separadamente `public.clubs`, suas chaves, ownership, visibilidade, policies e relação com membros. Não crie essa relação silenciosamente.

## Pendências que continuam válidas

1. **Atualizar o SDD** para incorporar a tabela `book_reviews`, os quatro campos de leitura atual e as policies acrescentadas, deixando claro que são uma extensão deliberada do contrato original.
2. **Testar policies com identidades reais de teste** titular e admin em ambiente isolado. O smoke test feito nesta tarefa cobriu Data API anônima e catálogo, não uma sessão autenticada gravando linhas.
3. **Revisar consumidores de RPC.** `award_xp` passou a ser exclusivamente invocável por `service_role`; chamadas diretas pelo app devem ser substituídas por endpoints seguros. A Edge Function `quiz-validate` ajustada continua sem deploy.
4. **Edge Functions:** revisar autenticação, autorização por ownership/admin, payloads, rate limits, consentimento e secrets antes do deploy. `ai-user-embeddings` precisa verificar que o solicitante pode calcular o snapshot de `user_id` recebido.
5. **Extensões em `public`:** cinco permanecem nesse schema. Mover `vector`, `pg_trgm`, `citext`, `unaccent` e `btree_gin` requer testes de tipos/operadores/RPCs e revisão do search path.
6. **Histórico CLI:** as migrations baseline `sdd_*` registradas remotamente não correspondem diretamente aos nomes granulares `20260101…` locais. Não usar `supabase db push` no projeto atual até reconciliação controlada.
7. **Frontend e tipos:** o repositório do banco não contém aplicação Next.js executável nem `database.types.ts`; gerar e revisar os tipos apenas depois de configurar/reconciliar o ambiente.

## Arquivos históricos em `blocked/`

Os arquivos ali preservados são referências originais do SDD, não migrations executáveis. Os objetos substitutos foram aplicados em migrations numeradas na raiz de `supabase/migrations/`. Não execute os arquivos arquivados manualmente, porque repetiriam relações/functions já criadas e alguns trechos conservam nomes antigos.

## Automação e seeds opcionais

O refresh de `private.mv_book_community_stats` foi agendado por `pg_cron` no job `refresh-mv-book-community-stats` a cada seis horas; o registro ativo foi conferido. O job `scheduled-reminders` continua pendente: a Edge Function não foi implantada e não há autenticação serviço-a-serviço configurada, então agendá-lo agora só produziria chamadas falhas.

Os seeds de avaliação e clube estão em `supabase/dev-seeds/` para testes locais. Não foram aplicados ao remoto, que não tinha perfis nem administradores. As cinco extensões ainda em `public` não foram movidas, porque não havia branch de desenvolvimento disponível para testar tipos, operadores e RPCs afetados.
