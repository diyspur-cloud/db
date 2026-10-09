# Relatório backend — migrations incrementais

## Correções

Foram criadas oito migrations pela CLI `supabase migration new`: helpers privados de visibilidade de buddy reads e listas removem ciclos de RLS; helper admin lê somente a identidade `auth.uid()` e wrapper público invoker retorna booleano; triggers privados privilegiados mantêm contadores/streak sem RPC de cliente; grants restauram edição própria de level/onboarding_done/WhatsApp sem role/consentimento; aliases das estatísticas de livros e painel coletivo são acrescentados ao final das views, conservando ordem e tipos anteriores; bônus diário de25 usa prova de atividade independente, data do streak e UUID determinístico com ledger idempotente.

Não foram recriadas entidades, removidos dados, reabertos grants de contadores ou alteradas migrations históricas.

## Verificação local real

`node /home/ubuntu/jobs/c8bbddf74f76_a0/test-migrations.mjs` foi executado pelo responsável e novamente pelo pai. Aplicou as oito migrations em scratch PGlite e terminou `PASS: PGlite migration replay and authorization/trigger/view assertions`. Esse harness verifica admin anônimo/admin, visibilidade Buddy/listas, contadores de likes/replies/feed, streak, grants de onboarding/WhatsApp, proteção de role/consentimento, ordem/tipos/aliases de views, agregação coletiva e bônus diário service-only/idempotente. O scratch usa fixtures reduzidas e um ledger stub; não substitui os testes consolidados com função award_xp real nem stack Supabase.

## Aplicação remota real

As oito aplicações pelo conector retornaram `{success:true}` e foram confirmadas no histórico real:

| Migration | Versão remota |
|---|---|
| fix_buddy_read_policy_recursion | 20261009030146 |
| fix_reading_list_policy_recursion | 20261009030149 |
| restore_admin_predicate | 20261009030152 |
| restore_internal_counter_triggers | 20261009030204 |
| restore_profile_onboarding_contract | 20261009030207 |
| restore_community_stats_contract | 20261009030211 |
| restore_club_progress_panel_contract | 20261009030214 |
| award_daily_streak_bonus | 20261009030217 |

A migration adicional schedule_meeting_reminders foi criada pela CLI, aplicada e testada por pg_net. Job2 ativo horário; job1 de refresh preservado.

## Catálogo e HTTP remotos

77/77 tabelas públicas mantêm RLS. As quatro funções internas de contador/streak não possuem EXECUTE para anon/authenticated/service_role. Bônus diário só service_role. Role de profiles não é legível nem editável diretamente pelo cliente; level/onboarding_done/WhatsApp editáveis sob ownership. Contadores de comments não editáveis.

GET limit0 das seis relações que retornavam42P17 agora HTTP200. is_admin anônimo HTTP200 false, duas views aliases HTTP200. Não afirmar teste JWT Auth multiusuário ou onboarding real a partir desses probes.

Definers públicos preexistentes encontrados no catálogo (handle_new_user, generate_milestones_for_season, refresh_book_mood_stats, refresh_* e rls_auto_enable) continuam com EXECUTE de anon/authenticated=false e search_path explícito; não foram duplicados nem tornados chamáveis nesta rodada.

## Limites

A data de bônus segue `current_date` UTC, como o streak original. Atividade usa user_progress do dia ou XP não-streak do dia; o progresso permanece autodeclarado conforme contrato, não comprovação material de leitura. Sem credenciais OAuth/provider, não foram exercidas assinaturas, e-mail ou chamadas OpenAI. Reset/replay completo do baseline e os dois seeds continuam sujeitos à validação consolidada; nenhuma ausência de Docker foi disfarçada como sucesso.
