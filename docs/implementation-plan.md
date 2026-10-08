# Plano de implementação e execução — Clube de Leitura

**Projeto:** `xjhehhfhhoomblcggjpk`
**Repositório:** [`diyspur-cloud/db`](https://github.com/diyspur-cloud/db)
**Data de execução:** 8 de outubro de 2026 (UTC−03:00)
**Objetivo:** implementar os itens anexados de forma incremental, conservar os dados existentes, reduzir exposição indevida e deixar migrations/testes/documentação reproduzíveis.

## 1. Princípios de segurança e de não regressão

1. Fazer inventário do repositório, do SDD, do histórico de migrations, do schema remoto, das policies e dos advisors antes de escrever DDL.
2. Não reescrever migrations já aplicadas nem confiar que os timestamps locais `20260101…` correspondem ao histórico remoto.
3. Alterar o schema de forma aditiva: criar uma tabela nova, acrescentar somente colunas nullable e criar índices/policies/views/functions. Não renomear nem remover tabelas, colunas, constraints existentes ou linhas de usuário.
4. Tratar `user_clubs` como a relação existente para clubes de usuários; **não** inventar uma tabela `public.clubs` para satisfazer um nome inconsistente do anexo/SDD.
5. Fazer leitura pública somente através de contratos agregados/explicitamente públicos; manter votos, RSVP, progresso individual e snapshots pessoais atrás de grants e RLS.
6. Manter código de Edge Functions fora do deploy enquanto a autorização dos endpoints e os secrets não forem auditados. A presença do código no repositório não comprova que está implantado.
7. Registrar as limitações que continuam abertas, em vez de chamar a solução de “zero risco” ou de produção-ready.

## 2. Baseline apurado

Antes das alterações, o estado correspondia a 75 tabelas públicas, 122 policies, 126 FKs, 7 views, 30 ENUMs e 24 migrations remotas. Foram identificados: dependência ausente `book_reviews`, ausência de campos de livro/temporada em `user_clubs`, 3 tabelas RLS sem policy, 7 views com comportamento SECURITY DEFINER, 18 funções sem `search_path` fixo, 63 FKs sem índice que cobrisse a chave e policies com avaliação repetida de `auth.uid()`.

O catálogo confirmou que `meeting_rsvps`, `host_prompt_votes` e `user_challenges` estavam inacessíveis via cliente por não possuírem policies; não havia razão para presumir acesso. Também foi feita revisão estática das fontes Edge Function. Nenhuma função foi implantada nesta tarefa.

## 3. Sequência de desenvolvimento implementada

### Etapa 0 — Preparação e reconciliação

- Clonar `diyspur-cloud/db` em cópia de trabalho limpa; não alterar a branch antes da verificação de `git status`.
- Ler o SDD, README, migrations e arquivos bloqueados.
- Identificar o projeto pelo ref `xjhehhfhhoomblcggjpk`, consultar o histórico e inspecionar relações/policies/índices/views/funções existentes.
- Manter segredos fora de arquivos versionados e não usar a publishable key como autoridade administrativa.

**Resultado:** baseline documentado; nenhum dado de usuário foi exportado ou alterado.

### Etapa 1 — Definir avaliações (`book_reviews`)

Arquivo: `supabase/migrations/20261008214832_add_book_reviews.sql`.

1. Criar a relação com UUID e FKs para `books` e `profiles`; deleções em cascata somente com a deleção da entidade referenciada, conforme o contrato da nova tabela.
2. Incluir `rating` numérico de 0–5, `spice_level` inteiro de 0–5, texto opcional limitado a 20.000 caracteres, flag de spoiler, soft-delete e timestamps.
3. Garantir no máximo uma avaliação por usuário/livro e criar índices de consulta por livro/data e usuário/data.
4. Habilitar RLS e conceder ao papel `anon` somente `SELECT`; `authenticated` recebe DML sujeito a policy; `service_role` permanece privilegiado.
5. Políticas finais: leitura pública apenas para linhas ativas, leitura própria/admin para linhas removidas, e INSERT/UPDATE/DELETE do titular ou admin. As ações foram separadas para evitar policies permissivas redundantes.

**Critério de aceite:** tabela existe, RLS está ligada, constraints e grants conferidos, nenhuma linha antiga foi modificada. Resultado remoto: tabela vazia após criação; critérios aprovados.

### Etapa 2 — Contexto de leitura em clubes existentes

Arquivo: `supabase/migrations/20261008214847_add_user_club_reading_context.sql`.

1. Acrescentar `current_book_id`, `current_season_id`, `current_started_at` e `current_ends_at` a `public.user_clubs`.
2. Fazer os identificadores referenciarem `books`/`seasons`, com `ON DELETE SET NULL`.
3. Deixar todos os campos opcionais para clubes preexistentes continuarem válidos.
4. Criar índices parciais para os valores não nulos; a migration de índices também cobre integralmente as FKs para manutenção das constraints.

**Critério de aceite:** colunas nullable presentes, FKs e índices presentes, contagem de linhas em `user_clubs` inalterada (0 no estado auditado).

### Etapa 3 — Restaurar acesso deliberado às três tabelas sem policies

Arquivo: `supabase/migrations/20261008214859_restore_missing_rls_policies.sql`; policies finais consolidadas em `20261008215324_harden_community_data_access.sql`.

- `meeting_rsvps`: leitura do próprio RSVP/admin; INSERT/UPDATE/DELETE somente do titular.
- `user_challenges`: leitura do próprio progresso/admin; INSERT/UPDATE/DELETE do titular.
- `host_prompt_votes`: somente o próprio usuário pode ler ou alterar o voto. A leitura agregada é exposta separadamente, não via linhas de votos.
- Acesso anônimo às tabelas privadas é removido; grants explícitos complementam RLS.

**Critério de aceite:** RLS ativa; quatro policies em RSVP, quatro em progresso de desafios, uma policy própria para votos; consulta anônima direta às três tabelas negada pelo banco. Os dados existentes não foram alterados.

### Etapa 4 — Views comunitárias e snapshot pessoal

Arquivo: `supabase/migrations/20261008214920_add_community_reading_views.sql`.

1. Criar `private` sem permitir CREATE por papéis de cliente e conceder somente `USAGE` necessário.
2. Colocar em `private` duas funções SECURITY DEFINER pequenas e com `search_path = pg_catalog`, que retornam apenas totais de progresso/votos; não retornam IDs ou linhas pessoais.
3. Recriar `v_chapter_audience` e `v_host_prompt_results` como views `security_invoker=true` e manter o formato agregado público.
4. Criar `mv_book_community_stats` inicialmente a partir do catálogo, humor e avaliações, com índice único de refresh e colunas agregadas.
5. Publicar `v_book_community_stats` como contrato REST; criar `v_club_progress_panel` sobre `user_clubs`/membros/progresso, sem introduzir `public.clubs`.
6. Criar `build_user_reading_snapshot(uuid)` como `SECURITY INVOKER`; um JWT autenticado só pode solicitar seu próprio `p_user`. O uso service-role fica restrito a backend confiável.

Arquivo: `supabase/migrations/20261008215324_harden_community_data_access.sql` move o materialized view para `private`. A API deve consumir `public.v_book_community_stats`, não consultar o detalhe interno diretamente.

**Critério do marco original:** habilitar `security_invoker=true` em todas as views públicas comuns então existentes; manter 1 materialized view no schema interno; expor agregações sem liberar votos individuais; impedir execução do snapshot por `anon`. Migrations posteriores ampliaram o total final a 12 views públicas seguras.

### Etapa 5 — Hardening das views, funções e privilégios

Arquivo: `supabase/migrations/20261008215009_harden_views_and_functions.sql`.

1. Fixar o `search_path` nas 18 funções centrais inicialmente identificadas; hardening posterior adicionou wrappers/helpers, chegando a 32 funções catalogadas com path fixo em `public`/`private`.
2. Aplicar `security_invoker=true` nas 7 views existentes e nas 2 views novas, totalizando 9.
3. Revogar `EXECUTE` de roles de cliente nas funções privilegiadas de XP, milestones e atualização de estatística de humor; conceder as chamadas administrativas necessárias a `service_role`.
4. Restringir funções internas/trigger-only que não devem ser chamadas diretamente por usuários.
5. Separar cliente com JWT do cliente service-role em `quiz-validate`: a consulta da request continua sob a identidade do leitor e somente a RPC privilegiada de XP usa um cliente servidor separado. Essa fonte foi editada, mas a Edge Function não foi implantada.

**Impacto deliberado que deve ser verificado por consumidores:** chamadas diretas de navegador para RPC privilegiada como `award_xp` deixam de funcionar; o caminho esperado é endpoint backend validado. Como não há frontend executável neste repositório e nenhuma Edge Function foi implantada, não foi possível validar todos os consumidores externos. Essa mudança é hardening, mas exige revisão de integração antes de release.

### Etapa 6 — Cobertura de índices das FKs

Arquivo: `supabase/migrations/20261008215045_index_uncovered_foreign_keys.sql`.

- Criar índices para FKs sem um índice válido e não parcial que tenha as colunas da FK como prefixo.
- Não relaxar nem remover constraints.
- Incluir as novas relações/colunas na verificação.

**Critério de aceite:** 130 FKs no schema `public`; zero FKs sem índice de cobertura. As recomendações de índices continuam sujeitas a validação sob tráfego real.

### Etapa 7 — Reduzir reavaliação de `auth.uid()`

Arquivo: `supabase/migrations/20261008215117_optimize_rls_auth_initplans.sql`.

- Reescrever expressions para o padrão `(select auth.uid())` onde seguro.
- Preservar roles, comando, condição e semântica de ownership das policies; não abrir linhas adicionais.

**Critério de aceite:** consulta final do catálogo encontrou zero expressions diretas de `auth.uid()` não envolvidas em initplan.

### Etapa 8 — Consolidar policies e ocultar materialized view

Arquivo: `supabase/migrations/20261008215324_harden_community_data_access.sql`.

- Mover `mv_book_community_stats` de `public` para `private`, manter o SELECT mínimo exigido pela view invoker e revogar `CREATE` de clientes no schema privado.
- Manter dados pessoais de RSVP/desafio legíveis pelo titular/admin, mas escritáveis somente pelo titular; voto bruto só pelo titular.
- Desdobrar INSERT/UPDATE/DELETE em policies separadas nos casos em que uma policy `FOR ALL` se sobrepunha à policy de SELECT. As quatro tabelas novas/afetadas não aparecem nos avisos remanescentes de múltiplas policies permissivas.

### Etapa 9 — Remover índice duplicado exato

Arquivo: `supabase/migrations/20261008215751_drop_duplicate_video_timed_comments_index.sql`.

- Comparar o DDL dos dois índices em `public.video_timed_comments` no catálogo remoto.
- Ambos eram B-tree sobre `(chapter_id, video_sec)` e nenhum era constraint unique.
- Remover `vtc_sec_idx`, manter `vtc_chapter_sec_idx`.

**Critério de aceite:** o índice remanescente conserva a mesma cobertura de consulta e o advisor deixa de apontar duplicidade.

### Etapa 10 — Atualizar estatísticas de livros via pg_cron

Arquivo: `supabase/migrations/20261008220410_schedule_book_stats_refresh.sql`.

1. Habilitar `pg_cron` sem mover o catálogo da extensão; no projeto, ela está catalogada em `pg_catalog` e guarda jobs no schema `cron`.
2. Registrar `refresh-mv-book-community-stats`, a cada seis horas, para executar `REFRESH MATERIALIZED VIEW CONCURRENTLY private.mv_book_community_stats` (a MV tem índice único apropriado).
3. Conferir o registro ativo em `cron.job` e testar o refresh concorrente uma vez manualmente.

**Resultado:** job `jobid=1`, ativo, schedule `0 */6 * * *`; o refresh manual retornou sem erro. A primeira execução automática futura ainda não foi observada. Não foi criado cron HTTP para reminders.

## 4. Plano de teste executado

### Testes estáticos e reprodutibilidade

- Parser PostgreSQL `pglast` nos arquivos SQL versionados: migrations, seeds, trechos arquivados e bundles gerados; foram validados 56 arquivos SQL sem erro.
- `git diff --check` para whitespace/patches.
- Executar `python3 scripts/build-remote-bundles.py` e verificar seis bundles/manifests, com o grupo 006 contendo as 13 migrations complementares na ordem registrada.

### Smoke tests do catálogo Supabase

- Confirmar `pg_cron` e job de refresh ativo; executar o refresh concorrente da MV privada sem erro.

- Conferir totais de tabelas, RLS, policies, FKs, views e funções fixadas.
- Consultar todas as views novas, testar `security_invoker` e confirmar a existência do MV no schema `private`.
- Verificar que a view de estatísticas retorna a linha do livro de seed; o MV tinha uma linha e `book_reviews` nenhuma.
- Conferir que não há FKs sem índice, nem policies com `auth.uid()` direto.
- Comparar as definições de índices antes de descartar uma cópia.

### Testes na Data API anônima, somente leitura

Resultados executados com publishable key (sem operações de escrita):

| Recurso | Resultado esperado | Resultado |
|---|---|---|
| `v_book_community_stats` | leitura agregada pública | HTTP 200; livro seed `Dom Casmurro`, zero avaliações |
| `v_chapter_audience` | totais públicos, sem linhas de leitor | HTTP 200 |
| `v_host_prompt_results` | totais públicos, sem voto individual | HTTP 200 |
| `book_reviews` | leitura apenas de conteúdo ativo | HTTP 200; conjunto vazio |
| `host_prompt_votes` direto | negar acesso à linha de voto | HTTP 401 / `42501 permission denied` |
| `meeting_rsvps` direto | negar acesso privado ao anônimo | HTTP 401 / `42501 permission denied` |
| `user_challenges` direto | negar acesso privado ao anônimo | HTTP 401 / `42501 permission denied` |

Não foi criado usuário de teste nem gravado payload em produção. Assim, isolamento entre dois JWTs autenticados foi validado pela inspeção das policies/catalog, não por teste end-to-end com contas reais.

### Advisors após a última migration

- **Segurança:** permanece apenas o aviso de 5 extensões em `public` (`vector`, `pg_trgm`, `citext`, `unaccent`, `btree_gin`). Não há aviso de SECURITY DEFINER exposto/callable no schema `public`, nem do MV exposto pela Data API.
- **Performance:** 109 índices com `idx_scan = 0` (inclui índices novos e históricos; não remover sem medir carga), 165 findings do linter de múltiplas policies permissivas herdadas do modelo original. As policies de membership, diário e respostas de prompts corrigidas não aparecem nos findings. Aviso de índice duplicado: zero.

## 5. Estado de aceite

- [x] Implementação por migrations novas, sem reescrever histórico já aplicado.
- [x] Tabela de avaliações, contexto opcional em `user_clubs` e policies faltantes.
- [x] Views agregadas e snapshot com restrição por titular.
- [x] Views invoker e funções de aplicação com `search_path` fixo.
- [x] Índice de FK para as 130 constraints e initplans para `auth.uid()`.
- [x] MV interno, policies novas sem sobreposição permissiva e remoção do índice duplicado.
- [x] pg_cron ativo para refresh concorrente a cada seis horas; refresh manual validado.
- [x] Smoke tests read-only pelo banco e pela Data API anônima.
- [x] Smoke test PGlite das três migrations finais com claims `anon`/`authenticated`, dois titulares, owner de clube, negações e caminhos permitidos para perfil/consentimento.
- [ ] Testar leitura/escrita com contas Supabase Auth reais de titular e admin em branch/projeto isolado.
- [ ] Atualizar e reconciliar o SDD, que ainda não descreve integralmente `book_reviews` e o contexto em `user_clubs`.
- [ ] Validar consumidores externos do RPC `award_xp` após a revogação de execução direta.
- [ ] Fazer auditoria dos endpoints/ownership e secrets antes de implantar qualquer Edge Function.
- [ ] Planejar uma migration separada para mover extensões somente após checar operadores, tipos, search path e integrações.
- [ ] Criar o job `scheduled-reminders` somente após deploy/autenticação de serviço da Edge Function.
- [ ] Aplicar os seeds de exemplo apenas em dev com perfil de teste; não no projeto de produção.
- [ ] Resolver a divergência do histórico baseline antes de usar `supabase db push`.

## 6. Rollback e recuperação

As migrations foram desenhadas para preservar linhas existentes, mas DDL não é automaticamente reversível. **Não** faça rollback destrutivo de `book_reviews`, colunas de `user_clubs` ou índices em produção sem verificar se o aplicativo já começou a gravar/ler esses objetos.

**Registro desta execução:** nenhum backup ou restore point manual foi criado antes do deploy. Nenhuma linha foi apagada; a migration de autorização preencheu `comments.min_percent` apenas para linhas legadas nulas (`100` se spoiler, `0` caso contrário). Não houve inserção de linhas de usuário. Para novas mudanças estruturais, crie e valide um restore point e prefira ambiente isolado.

- Se uma view/ACL causar regressão, preferir migration corretiva para ajustar grants/contract, mantendo RLS habilitado.
- Se uma aplicação depender do RPC `award_xp` direto, redirecionar para serviço de backend validado; não restaurar indiscriminadamente `EXECUTE` para `anon`/`authenticated`.
- Para mudança de policy, manter a versão anterior em migration/histórico e preparar testes de titular/admin antes da alteração.
- Antes de futuras mudanças, usar backup/restore point do Supabase e validar em branch/projeto isolado quando disponível.
- Nunca executar `supabase db reset` ou `db push` no projeto atual como mecanismo de reversão.

## 7. Migrations remotas deste plano

As 13 migrations registradas para esta implementação são:

1. `20261008214832 add_book_reviews`
2. `20261008214847 add_user_club_reading_context`
3. `20261008214859 restore_missing_rls_policies`
4. `20261008214920 add_community_reading_views`
5. `20261008215009 harden_views_and_functions`
6. `20261008215045 index_uncovered_foreign_keys`
7. `20261008215117 optimize_rls_auth_initplans`
8. `20261008215324 harden_community_data_access`
9. `20261008215751 drop_duplicate_video_timed_comments_index`
10. `20261008220410 schedule_book_stats_refresh`
11. `20261008225152 harden_core_authorization`
12. `20261008225535 prevent_client_privilege_escalation`
13. `20261008225856 encapsulate_profile_consent_privilege`

Os nomes/versões acima foram confirmados no histórico remoto e espelhados nos arquivos do repositório. O histórico baseline anterior permanece com nomes agregados `sdd_*`; por isso a advertência de não executar CLI push sem reconciliação continua válida. O total final remoto é 37 migrations (24 históricas + 13 novas).

## 8. Decisões de escopo e itens do anexo adiados

A reconciliação/repair do histórico baseline não foi executada. O projeto já tinha 24 entradas históricas `sdd_*`; inserir de novo os mesmos pares com `ON CONFLICT DO NOTHING` não alinha os arquivos granulares locais `20260101…`, e escrita manual no schema de migrations cria risco ao CLI. As 13 migrations novas estão versionadas com as versões remotas exatas; baseline antigo segue bloqueado para `db push`.

As cinco extensões em `public` foram mantidas. O endpoint de branches do Supabase não listou um ambiente isolado; sem branch de teste, mover extensões que fornecem tipos e operadores pode quebrar colunas, índices, RPCs ou search path. A pendência fica para uma mudança futura com cópia/restauração e validação de dependências.

O job de refresh da MV foi implementado. O cron HTTP de `scheduled-reminders` não foi criado porque a Edge Function não está implantada e não há credencial de serviço configurada; um job horário sem autenticação produziria falhas recorrentes. O contrato de autorização está documentado em `docs/edge-functions-authorization.md`.

Seeds idempotentes de review/clube foram criados sob `supabase/dev-seeds/`, mas não foram aplicados ao projeto remoto: a auditoria encontrou zero perfis e zero admins. Não foram inseridos dados de amostra. Nenhuma Edge Function foi implantada, conforme o escopo do anexo. A validação RLS com duas sessões JWT reais continua necessária em ambiente isolado.


## 9. Plano de desenvolvimento ponta a ponta — próximos passos

As migrations 1–13 deste documento estão no Supabase e versionadas. O plano abaixo é a sequência de produto ainda necessária para transformar o banco preparado numa aplicação implantável. **Não pule as gates de ambiente isolado e autorização real.** Esta etapa não autoriza `supabase db push` contra o projeto existente: o baseline `sdd_*` ainda diverge dos arquivos granulares locais `20260101…`.

### 9.1 Estado de saída desta rodada

- **Concluído:** auditoria de schema/RLS/views/Storage/Realtime/cron/advisors; migrations incrementais; hardening de dados pessoais, quiz, spoilers, clube e consentimento; bundle/manifests; README e status; parser SQL, Deno type-check e smoke PGlite.
- **Ainda não concluído:** reconciliação do SDD/histórico CLI, teste autenticado com Supabase Auth real, integração do frontend, tipos gerados, deploy de Edge Functions, secrets, pipelines e liberação para usuários.
- **Regra de mudança:** toda alteração futura segue `especificar → criar migration → testar localmente → testar isolado com JWT real → aplicar controladamente → verificar catálogo/API/logs → documentar`. Sem teste positivo e negativo do papel adequado, não libere escrita.

### 9.2 Sequência de implementação

| Fase | Trabalho e ordem recomendada | Evidência/critério para avançar |
|---|---|---|
| 0. Alinhar contrato do produto | Atualizar `SDDBD2.md` com `book_reviews`, os quatro campos de leitura de `user_clubs`, ownership de cada recurso, níveis de privacidade, campos pessoais, tratamento de spoilers, quiz server-authoritative, consentimento e papel/role. Registrar explicitamente decisões sobre `public.clubs` versus `user_clubs` e o que é público, autenticado, titular, membro de clube ou admin. | Matriz entidade × ação × role aprovada; cada endpoint/tabela tem owner e regra de visibilidade; nenhum item depende de pressuposto implícito.
| 1. Criar staging e reconciliar histórico | Obter backup/restore point do projeto; criar branch Supabase ou projeto descartável; comparar schema remoto, `supabase_migrations.schema_migrations`, arquivos e bundles; produzir plano de baseline/repair revisável. Usar ferramenta/fluxo compatível com o histórico `sdd_*`; validar todas as migrations numa base limpa e provar que o plano incremental não recria objetos. | Restore point verificável; diff remoto/local explicado; replay em projeto limpo conclui; reconciliar CLI em ambiente separado; só então remover o bloqueio formal de `db push`.
| 2. Preparar aplicação e tipos | Definir `supabase/config.toml`, lockfile/dependências e ambiente local; gerar `src/lib/supabase/database.types.ts` contra o schema correto; revisar enums, RPCs, views, colunas nullable e diferenças entre base e complementos. Guardar publishable key apenas nas variáveis públicas esperadas e qualquer secret somente no servidor; nunca commitar `.env` nem `service_role`. | Build/tipos compilam; busca por chave/token/dados de usuário não encontra segredos; SSR/browser/server usam clientes separados e tipos atualizados.
| 3. Auth, perfil e consentimento | Implementar signup/login/logout/refresh com `@supabase/ssr`; tratar ausência/expiração de sessão sem fallback de privilégio. Criar perfil de onboarding com campos públicos vindos de `v_profiles_public`, PII apenas pela RPC própria, consentimento pela RPC `set_my_lgpd_consent`, timestamp apenas gerado pelo banco, e `role`/`level` somente leitura para cliente. | Com 2 contas reais: cada conta lê só sua PII/consentimento; tentativa de ler whatsapp alheio, atualizar role/level/timestamp ou chamar RPC anônima falha; consentimento on/off tem timestamp correto e auditoria documentada.
| 4. Catálogo, progresso e discussão sem spoilers | Integrar livros/temporadas/capítulos; gravar progresso apenas sob owner/JWT válido; consumir `v_comments_visible` e `v_feed_posts_visible`, nunca selecionar corpo sensível diretamente. Fixar significado e origem confiável do percentual/progresso; confirmar que o mecanismo não permite desbloquear spoiler por update arbitrário fora das rules de progresso do contrato. | Teste A/B com progresso abaixo/igual/acima do limite; `content`, `body`, `quote_text` e metadados ocultos até a condição; exclusão lógica e paginação não quebram filtros.
| 5. Quiz authoritative e XP | Conectar a UI somente à projeção `v_quiz_questions_public`; retirar fetch direto de `quiz_questions.correct_idx`/explicação. Antes de deployar `quiz-validate`, substituir seu pre-check de rate limit (não atômico sob concorrência) por limite atômico no banco/gateway; validar que o caller tem acesso ao capítulo; fazer tentativa e atribuição de XP idempotentes; configurar secrets. `award_xp` deve ser chamado exclusivamente com cliente service-role no backend e só após resposta válida. | Resposta correta não aparece em payload cliente; tentativas são persistidas sem insert direto do usuário; replay, chapter errado, body malformado, flood concorrente e chamada de capítulo não autorizado são negados; XP é atribuído exatamente uma vez.
| 6. Clubes, feed e relações | Implementar criação/edição de clubes e membership; self-join somente `member`; owner atribui moderador/owner conforme a matriz aprovada; testar clube público/privado e remoção de membro. Implementar feed, mídia, follows, comentários, likes, listas e colaboração usando ownership e visibilidade; o bucket `feed-media` é privado e deve usar URLs assinadas/endpoint autorizado em vez de URL pública. | Titular/owner/reader não membro/admin testados entre si; users não leem nem alteram linhas de terceiro; upload/download de mídia segue visibilidade do post; políticas de colaboração não permitem modificar owner/lista de outro usuário.
| 7. Diário e conteúdo de capítulo | Conectar `reading_journal_entries`, anexos e `chapter_prompt_responses` às suas policies separadas por operação; testar combinações `private`, `friends`, `club`, `public`, reciprocity de follow e participação em clube. Validar se o contrato de grupo permite ver só campos/textos autorizados. | Casos de isolamento com titular, follower unilateral, friends recíprocos, membro/não membro e admin; anexo privado sem acesso cross-user; exclusão/soft-delete e update de owner testados.
| 8. Storage, Realtime e cron | Inventariar cada bucket, confirmar bucket público/privado e cada policy de `storage.objects`, limites/tamanho/MIME e prefixo de path. Validar tabela por tabela a publicação `supabase_realtime` e payload sem PII desnecessária. Revisar o job ativo do refresh; somente criar `scheduled-reminders` após endpoint implantado com auth de serviço, timeout/retry e observabilidade. | Teste upload/download/remove como anon, dono, colaborador e admin; canais Realtime não revelam dados privados a espectadores; jobs têm runbook, idempotência, health/alarm e plano de pausa.
| 9. Integrações externas e operações server-side | Para `ai-user-embeddings`, vincular `user_id` ao JWT ou proibir cálculo cruzado; definir expurgo/retenção de embeddings. Revisar Resend/newsletter, Stripe/webhooks e provedores externos: assinatura de webhook, duplicidade/idempotência, mínimo de dados, autorização admin, rate-limit e tratamento de erros. Definir secrets em ambiente Supabase e rotação sem expor valores. | Testes com secrets de staging; assinaturas/replay inválidos negados; logs sem payload sensível; não há chamada administrativa possível a partir do navegador.
| 10. Remediar findings sem regressão | Avaliar as cinco extensões em `public` em branch: dependências de tipo, operadores, casts, funções, índices e search path antes de mover. Triar os 165 findings `multiple_permissive_policies` por tabela/role/command e semântica OR das policies; decidir explicitamente quais são intencionais, quais reduzem performance e quais mudam autorização. Investigar os 109 `unused_index` somente com observação de carga suficiente. | Cada finding tem owner, risco, query/plano antes e depois e teste de regressão; nenhum índice crítico é removido por `idx_scan=0` isolado; advisor limpo não é critério único de segurança.
| 11. Testes de integração e release candidate | Adicionar testes SQL/pgTAP no Supabase local ou branch; incluir anon/auth A/B, titular/admin/owner, Data API REST, RPC, Edge Functions, Storage e Realtime. Rodar unit/integration, Deno, migrations do zero, type-generation diff e verificações de secrets. Comparar o projeto isolado com o inventário de 76 tabelas, 155 policies, 12 views, FKs/índices, funções e triggers. | Pipeline CI reproduzível passa em ambiente limpo; cobertura inclui sucesso e negação; nenhuma migration fica faltando; regressões de API e performance são revisadas/aprovadas.
| 12. Lançamento, monitoramento e recuperação | Com backup/restore point, janela e owner de aprovação definidos, aplicar migrations novas uma a uma pelo método compatível com o histórico já reconciliado. Verificar catálogo/histórico, grants, policies, advisors, Data API, função, Storage e cron imediatamente; acompanhar logs/erros/latência. Se houver falha, aplicar migration corretiva aditiva; restaurar backup somente conforme playbook testado, não usar `db reset`. | Checklist de release assinado; versão remota = versão de Git; alarmes e runbook ativos; rollback/forward-fix demonstrado em staging; suporte sabe pausar jobs/canais e rotacionar secrets.

### 9.3 Matriz mínima de autorização para testes reais

| Ator de teste | Deve poder | Deve ser negado |
|---|---|---|
| `anon` | Conteúdo explicitamente público, views agregadas e perfil público sanitizado | PII, linhas pessoais, mídia privada, respostas de quiz, tentativas e RPCs de escrita |
| Titular A | Ler/alterar só perfil, consentimento, progresso e recursos que possui; acessar conteúdo compatível com seu progresso | PII/diário/listas/membership/tentativas de B; `role`, `level` ou timestamp definidos pelo cliente |
| Titular B (não relacionado) | Acesso público e próprios recursos | Feed/diário/lista/consentimento de A e clube privado de A |
| Follower | Conteúdo de amizade somente quando a relação e visibilidade satisfazem o contrato | Leitura por follow unilateral se o recurso exige reciprocidade |
| Membro de clube | Conteúdo e mídia do clube no qual participa | Conteúdo de clube privado sem membership; promover a si mesmo a owner/moderator |
| Owner/moderador | Gerir apenas clube próprio e operações atribuídas pelo SDD | Alterar owner de clube alheio, administrar outra tenancy ou conceder papel arbitrário |
| Admin | Operações de suporte/admin explicitamente documentadas e auditáveis | Bypass implícito de consentimento, exposição sem necessidade ou uso do secret no cliente |
| `service_role` | Rotinas server-side necessárias com privilégio mínimo operacional | Uso em frontend, logs, código público ou endpoint sem validação do usuário e finalidade |

Para cada linha, registrar query/endpoint, identity/JWT, resultado esperado, resultado observado, status HTTP/SQLSTATE e se a tentativa foi feita por Data API ou Postgres. PGlite já cobre uma amostra automatizada, mas o gate de produção exige reproduzir a matriz com contas isoladas de Supabase Auth.

### 9.4 Definition of Done antes de liberar produção

- [ ] SDD, README, migrations e tipos gerados descrevem o mesmo contrato.
- [ ] Histórico baseline foi reconciliado sem recriar nem apagar objetos remotos.
- [ ] CI aplica todas as migrations desde banco vazio; branch isolada valida migrations incrementais.
- [ ] Cada tabela exposta possui RLS; roles/policies/grants e nomes de RPC foram revisados; nenhum cliente usa `service_role`.
- [ ] A matriz de anon/titular/follower/member/owner/admin/service-role tem testes positivos e negativos com Auth real.
- [ ] PII, quiz, spoilers, consentimento, Storage, Realtime, webhooks, cron e Edge Functions foram validados em staging.
- [ ] Secrets, backups, alertas, logging sem PII, rate limits, expiração de URLs e playbook de incidentes estão prontos.
- [ ] Os findings Supabase têm triagem escrita; riscos remanescentes têm decisão explícita, owner e prazo.
- [ ] Checklist de deploy/forward-fix e verificação pós-deploy foi executado por pessoa responsável.

Até estes gates passarem, o estado correto é **banco endurecido e documentado; aplicação e integrações ainda não prontas para produção**.
