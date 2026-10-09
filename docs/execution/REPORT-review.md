# Auditoria read-only do backend Diyspur

**Data:** 2026-10-09
**Escopo:** backend Supabase exclusivo; leitura de `docs/execution/sdd-pendencias-original.txt` §§1–15 e 26–27, `docs/execution/SDDBD2-original.md`, migrations `20261009025153`–`20261009025524`, `20261009030241`, handlers em `supabase/functions/`, grants/RLS/seeds e evidências remotas já registradas.
**Fora do escopo:** frontend, execução de DML/DDL remoto, replay/reset remoto, chamadas de negócio com identidade real, alteração de scripts/testes e Git. Nenhum arquivo foi alterado além deste relatório.

## 1. Veredito executivo

O patch remoto aparenta ter corrigido a **disponibilidade de rota** e os oito problemas de autorização/contrato que motivaram a rodada, mas ainda não há prova ponta a ponta de autorização A/B, negócio ou integração externa. Os artefatos remotos registram dez funções `ACTIVE`, seis probes de tabelas/views/RPC em HTTP 200, reminders HTTP 200 com zero reuniões, `pg_net` HTTP 200 e dois jobs Cron ativos; os GET dos handlers retornam 405, o que prova publicação/roteamento, não o fluxo de negócio.

**Conclusão:** backend parcialmente pronto para validação controlada; não declarar aceite final. Os bloqueadores reais são segredos de OpenAI/Resend/Stripe, OAuth não configurado, ausência de histórico de execução do novo Cron e replay local não reprodutível. Os defeitos técnicos confirmados abaixo são independentes desses bloqueadores.

### Achados confirmados por prioridade

| Prioridade | Achado confirmado | Impacto |
|---|---|---|
| **P1** | O replay local do view de comunidade de clubes falha: `supabase/migrations/20261008214920_add_community_reading_views.sql:127` seleciona `s.title`, enquanto `:145` agrupa `current_season.title` (documentado também em `sdd-pendencias-original.txt:541-543`). PostgreSQL retorna 42803. | Uma base limpa não reproduz a sequência local; qualquer validação de seeds/contratos sobre o replay fica bloqueada. O view remoto existente não prova que o arquivo local seja replayável. |
| **P1 — integridade/contrato** | `20261009025201_restore_profile_onboarding_contract.sql:3-4` devolve ao cliente `UPDATE(level,onboarding_done)`; `20261008225535_prevent_client_privilege_escalation.sql:4-5` havia revogado `UPDATE(level)` porque o tratava como progressão derivada. Não há CHECK de domínio para `level`. | Um usuário autenticado pode escrever qualquer texto em `profiles.level`. Isso é compatível com o texto do SDD que captura `level`, mas incompatível com o contrato técnico anterior de nível derivado; se consumidores confiarem nesse campo para progressão/badges, há falsificação de estado. `role`, consentimento e timestamps continuam protegidos. A decisão deve ser registrada como regra de produto, não mascarada como correção RLS. |
| **P1 — quiz** | O caminho de idempotência identifica uma tentativa apenas por `(user_id, request_id)`: `supabase/functions/quiz-validate/index.ts:30-43` não recebe `chapter_id`, e `:105-106` devolve a tentativa existente antes de validar o capítulo. A RPC `record_quiz_attempt` repete a mesma lacuna em `supabase/migrations/20261009020600_20261009014533_implement_audit_followups.sql:443-455`. | Reutilizar a mesma chave para outro capítulo retorna o resultado antigo em vez de `409/conflict` ou rejeição. Não é vazamento entre usuários, mas é replay semântico incorreto e pode confundir o consumidor/contabilização. O request ID deve ser vinculado ao capítulo, ou o conflito deve ser validado explicitamente. |
| **P2 — concorrência newsletter** | `newsletter-dispatch` faz claim no banco (`supabase/functions/newsletter-dispatch/index.ts:107-117`), o que impede duas audiências simultâneas, mas o `catch` de `:217-223` não chama `finish_newsletter_dispatch`. O lease fica pendente até a recuperação de 24 horas definida pela RPC (`20261009020600...sql:526-532`). | Falha/crash depois do claim deixa a newsletter sem retry por até 24h. Depois de um envio externo aceito e falha no log (`:182-200`), o retry depende do idempotency key do Resend; não há transação entre provedor externo e `newsletter_deliveries`. É uma janela operacional, não uma autorização indevida. |
| **P2 — agregação de clube** | `20261009025205_restore_club_progress_panel_contract.sql:18-35` calcula `finished_count`, `reading_count`, `not_started_count` por **todas as temporadas do livro**. A mesma view expõe `current_season_id` em `:53-54`, e o painel antigo filtra a temporada atual em `:80-83`. | Se um livro tiver múltiplas temporadas, os aliases novos podem incluir progresso fora da temporada corrente, enquanto `distinct_readers` não inclui. O SDD original fala em `public.clubs` inexistente e não decide o papel de `current_season_id`; portanto o defeito de coerência é confirmado no contrato implementado, mas a regra correta de temporada permanece uma decisão, não autorização para inventar `clubs`. |
| **P2 — snapshot de estatísticas** | `20261009025203_restore_community_stats_contract.sql:17-23` combina `mood_percent` da tabela corrente com as demais métricas da MV privada, que só mudam no refresh. | Um payload pode misturar instantes de atualização. O SDD exige nomes/defaults compatíveis, mas não define atomicidade temporal; registrar a escolha ou atualizar todas as métricas em uma única fonte/refresh antes de chamar o contrato de “snapshot”. |

### Riscos de limite concorrente, confirmados por inspeção estática

- **Cards:** `supabase/functions/social-render-card/index.ts:85-106` conta jobs e só depois insere. Requisições concorrentes podem ultrapassar o limite declarado de 10/dia.
- **Embeddings:** `supabase/functions/ai-user-embeddings/index.ts:40-49` lê `updated_at`, chama OpenAI e só grava em `:72-77`; chamadas concorrentes podem passar juntas pelo limite de uma hora. O handler é admin/usuário conforme o contrato do SDD, mas a limitação não é atômica.

Esses dois itens não foram exercidos remotamente por falta de credenciais e não devem ser apresentados como reproduzidos; a corrida é dedutível do read-before-write.

## 2. O que foi corrigido e o que a evidência realmente prova

### RLS, auth, IDOR e grants

- **Buddy reads:** `20261009025153_fix_buddy_read_policy_recursion.sql:7-41` move a avaliação para `private.can_view_buddy_read`, com `SECURITY DEFINER`, `search_path=''`, identidade somente de `auth.uid()` e policy explícita para `anon,authenticated`. A policy de membros continua com a semântica original; não foi criada tabela nova.
- **Reading lists:** `20261009025155_fix_reading_list_policy_recursion.sql:7-41` faz o equivalente para `private.can_view_reading_list`; `unlisted` não virou pública.
- **Admin:** `20261009025157_restore_admin_predicate.sql:7-43` encapsula leitura de `profiles.role` em helper privado, sem parâmetro controlável. O wrapper `public.is_admin()` é invoker e só delega ao helper; não reabre SELECT da coluna `role`.
- **Funções de trigger:** `20261009025159_restore_internal_counter_triggers.sql:8-127` usa funções privadas privilegiadas e `search_path=''`; `:129-167` revoga execução RPC e reaponta somente os triggers. Não foram concedidos UPDATE direto de contadores nem escrita em `user_streaks`.
- **Onboarding:** `20261009025201...:9-16` mantém `USING` e `WITH CHECK` com o próprio `auth.uid()`. O achado de `level` acima é uma divergência de integridade/regra, não um IDOR entre perfis.
- **Handlers:** `_shared/auth.ts:16-33` exige Bearer e valida a identidade via `auth.getUser`; `isAdmin` lê role somente pelo cliente service-role (`:35-44`). Os handlers que aceitam `user_id` rejeitam identidade diferente: quiz (`quiz-validate/index.ts:83-86`), embeddings (`ai-user-embeddings/index.ts:28-35`), match (`match-readers/index.ts:32-35`) e cards (`social-render-card/index.ts:64-67`). Vote e XP derivam o usuário do JWT, não do body.
- **Views:** os views novos de estatísticas/clube conservam `security_invoker` (`20261009025203:4-6`, `20261009025205:45-47`) e as agregações coletivas ficam em helper privado. A autorização A/B para terceiro, membro, owner e anônimo **não foi provada** por `limit=0`.
- **Privileged RPCs:** as RPCs server-only em `20261009020600...` e `20261009025524...` revogam `PUBLIC,anon,authenticated` e concedem apenas a `service_role`. Não há evidência de service key em código público.

**Limite da evidência:** `docs/execution/remote/http-probes-latest.json` registra `method: GET; sem identidade` (`:2-5`). Os 200 das seis rotas (`:7-49`) e `is_admin=false` (`:37-40`) comprovam acessibilidade/ausência de recursão, mas não comprovam owner/membro/terceiro, UPDATE com troca de chave, INSERT/DELETE ou exposição de PII. Os dez handlers só foram exercitados por GET e responderam 405 (`:86-152`).

### Counters, XP e streak

- Os corpos históricos de likes/replies/feed/streak foram preservados em funções `private` e chamados pelos triggers. Os novos arquivos não fazem `DROP TABLE`, `DROP COLUMN`, `DELETE` ou `TRUNCATE`; os `DROP` encontrados são apenas `DROP POLICY` e `DROP TRIGGER` para substituição idempotente.
- `20261009025524_award_daily_streak_bonus.sql:7-66` exige `last_activity_at=current_date`, atividade de hoje em `user_progress` ou `xp_events` não-streak, gera uma referência diária determinística e chama `award_xp` service-only. O índice único criado em `20261009020600...:7-9` evita crédito duplicado concorrente.
- O branch `award-xp/index.ts:34-60` ignora `ref_id` enviado pelo cliente e deriva o usuário do token. Isso atende à decisão nova: **25 pontos no máximo uma vez por dia com atividade**. A função retorna somente boolean; a resposta hoje quase sempre informa `duplicate:false`, mesmo em retry idempotente, mas isso não duplica o ledger.
- A condição “atividade real”, fuso do dia e semântica de `ref_id` não estavam definidos no SDD original (`sdd-pendencias-original.txt:438-451` e `:1282`); a rodada decidiu `current_date` + progresso/XP. Essa decisão precisa ficar documentada como contrato executável, não ser apresentada como igualdade literal do anexo.

### Quiz

O handler calcula o score no servidor, nunca aceita `correct_idx` do cliente, exige capítulo disponível/temporada ativa ou finalizada, valida opções e usa `record_quiz_attempt` + `award_xp` idempotentes (`quiz-validate/index.ts:108-230`). A lacuna de reuso da mesma chave em capítulo diferente permanece no achado P1.

O exemplo original do SDDBD não envia `request_id`; a fonte atual gera UUID quando omitido (`quiz-validate/index.ts:87-102`). Isso mantém compatibilidade de uma chamada, mas **não** torna retries sem chave idempotentes. O consumidor deve persistir e reenviar a mesma chave; se a exigência for compatibilidade literal com retry implícito, falta uma decisão adicional.

### Newsletter e audiência

A decisão recebida nesta rodada está implementada: `newsletter-dispatch/index.ts:32-35` fixa `NEWSLETTER_AUDIENCE="todos_confirmados"`; `:73-100` aceita/valida `tags`, `tags_any`, `tags_all` e `frequency`, mas `:149-156` não aplica nenhum filtro e seleciona apenas `status=confirmed` + `unsubscribed_at IS NULL`. Portanto **tags são ignoradas na audiência**, não transformadas silenciosamente em `tags_any`.

A chave de claim é estável por issue/audiência (`:107-117`), a seleção pagina entregas já enviadas (`:119-130`) e usa idempotency key por destinatário (`:168-189`). Isso é uma boa defesa concorrente, mas não elimina o lease pendente/crash e a fronteira não transacional do achado P2. O envio real não foi validado porque Resend não tem secrets no painel.

### Reminders/Cron

- `20261009030241_schedule_meeting_reminders.sql:18-53` exige o secret no Vault, evita segundo job pelo nome e agenda `reminders-every-hour` em `0 * * * *` com `x-scheduled-reminders-secret`.
- A evidência existente registra dois jobs ativos, preservando `refresh-mv-book-community-stats`; `scheduled-reminders` respondeu HTTP 200 com `{ok:true,created:0,skipped:0,meetings:0}` e o request `pg_net` respondeu HTTP 200 (`docs/execution/remote-observations.md:7-14`).
- **Ainda não há `cron.job_run_details` do novo job**. Não afirmar primeira execução, não duplicação de notificação ou payload entregue. Zero reuniões significa somente que o smoke atual não criou destinatários.
- O arquivo verifica se o job existe, mas não corrige um job preexistente com mesmo nome e schedule/comando errado (`:27-35`). O estado remoto registrado está correto; fica como defesa operacional para futuras reexecuções, não como falha já observada.

## 3. Seeds, drops e replay

- `supabase/config.toml:67-72` agora carrega `seed.sql` e `seed_complement.sql` na ordem. Os seeds têm guards de repetição: `seed.sql:3-57` e `seed_complement.sql:5-172` usam `ON CONFLICT`/`NOT EXISTS`; filtros por capítulo estão amarrados à temporada Dom Casmurro. Isso corrige a pendência de reset local; não constitui autorização para aplicar seed no remoto.
- O issue de newsletter no seed ainda contém `{"tags":["welcome"]}` (`seed_complement.sql:164-172`), mas a audiência nova é deliberadamente todos os confirmados; não há conflito enquanto essa decisão permanecer explícita.
- O seed é demonstrativo: sem perfil admin, `created_by` do issue pode ser `NULL` (`:171`), e não cria reuniões/contas reais. Não inventar dados para fazer reminders, newsletter ou XP parecerem aprovados.
- O baseline remoto contém bundles `sdd_*` e o local contém migrations granulares `20260101…`; `docs/execution/reconciliation.md:5-15` confirma que não há mapeamento 1:1. Os timestamps remotos dos oito patches também diferem dos nomes locais. Não usar `db push`, replay de bundles ou `migration repair` sem manifesto/reconciliação.
- O replay também permanece bloqueado pelo erro 42803 do view citado no P1. Um banco remoto com view já presente não substitui replay de uma base limpa.

## 4. Requisitos atendidos, indefinidos e fora do escopo

### Decisões atendidas

- Streak bonus: 25, uma vez por dia, com atividade e referência server-side idempotente.
- Newsletter: todos os inscritos confirmados não cancelados; `tags` ignoradas na seleção.
- Buddy/listas/admin/views: correções aditivas sem ampliar visibilidade privada; probes de rota acessíveis.
- Contadores: trigger interno privilegiado, sem UPDATE de contador pelo cliente.
- Seeds: dois arquivos no reset local, sem seed demonstrativo remoto.

### Requisitos ainda indefinidos no SDD (não inventar)

- `public.clubs` aparece no view original, mas não há DDL; o código usa `user_clubs`. O documento já manda não criar uma entidade `clubs` sem especificação de chave, ownership, visibilidade e membros (`sdd-pendencias-original.txt:545-552` e `:1279`).
- A coluna `level` conflita entre onboarding e progressão derivada; os valores do anexo não formam enum fechado (`:224-236`).
- O nome físico `mv_book_community_stats` foi movido para `private`; a API pública é `v_book_community_stats`. Isso é compatibilidade de API, não igualdade física.
- A semântica de “not started” do painel é status `want_to_read` registrado; não contar membros sem linha sem nova decisão (`sdd-pendencias-original.txt:549-552`).
- Badges/desafios, games, layouts de cards, Discord/Google Calendar e rotação editorial automática não têm motor/contrato completo (`:1283-1290`).
- OAuth Google/GitHub exige credenciais, callback, `site_url` e allowlist; a ausência não deve ser preenchida com secrets falsos.

### Frontend cancelado/intocado

`src/` contém apenas scaffolding de cliente/server/middleware, tipos e `README` (`src/lib/supabase/middleware.ts:1-18`, `src/middleware.ts:1-12`); não existem `src/app`, páginas, componentes ou fluxo de cancelamento de UI. Isso confirma a decisão de não auditar/alterar frontend. A falta de consumidores de UI é assunto fora deste backend review, não defeito do Supabase.

## 5. Blockers reais e próximos testes necessários

1. **Secrets ausentes no painel/runtime:** a evidência administrativa registra somente `SCHEDULED_REMINDERS_SECRET`; estão ausentes `OPENAI_API_KEY`, `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, `STRIPE_SECRET_KEY` e `STRIPE_WEBHOOK_SECRET` (`docs/execution/remote-observations.md:18-22`). O secret de reminders foi criado e não está versionado.
2. **OAuth:** Google/GitHub continuam `false` (`remote-observations.md:26-27`); sem frontend/callback real, não declarar Auth completo.
3. **Backups:** o painel informa que o Free Plan não inclui backups agendados (`remote-observations.md:23-24`). Não marcar backup automático como concluído; nenhuma compra/upgrade foi feita.
4. **Validação autorizada pendente:** executar em ambiente apropriado, com dois usuários isolados, owner/admin/terceiro/anônimo: SELECT/INSERT/UPDATE/DELETE de buddy/listas/clubes/progresso, troca de `list_id`/`club_id`, `is_admin`, quiz retry/capítulo divergente, contador de likes/replies/feed, streak concorrente, claim/retry de newsletter e reminders duplicados.
5. **Integrações:** após secrets reais, testar POST autorizado dos dez handlers; provider error, 401/403/422/429/503 e respostas de negócio. GET 405 não substitui esses testes.
6. **Performance/observabilidade:** os planos e volumes registrados (`remote-observations.md:14-16`) não são representativos; `EXPLAIN (ANALYZE, BUFFERS)` e primeira execução do Cron continuam pendentes. O smoke agent separado deve ser a fonte dos testes mutantes; esta revisão não editou scripts nem fabricou evidências.

**Estado final recomendado:** manter as migrations aplicadas e o Cron atual, não reverter/drop destrutivo; corrigir o replay 42803 e decidir formalmente `level`, vínculo do idempotency key do quiz e filtro de temporada do agregado antes de declarar SDD literal ou produção pronta.
