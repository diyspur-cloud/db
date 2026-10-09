# Evidências remotas — 09/10/2026 UTC

## Supabase
Projeto: https://xjhehhfhhoomblcggjpk.supabase.co

- Catálogo e histórico acessíveis administrativamente pelo conector nesta sessão.
- Oito migrations de correção registradas: 20261009030146 fix_buddy_read_policy_recursion; 20261009030149 fix_reading_list_policy_recursion; 20261009030152 restore_admin_predicate; 20261009030204 restore_internal_counter_triggers; 20261009030207 restore_profile_onboarding_contract; 20261009030211 restore_community_stats_contract; 20261009030214 restore_club_progress_panel_contract; 20261009030217 award_daily_streak_bonus.
- Dez Edge Functions ACTIVE versão 1. User endpoints verify_jwt=true; Stripe/reminders false com autenticação própria.
- GET das seis relações buddy/listas, is_admin e duas views com aliases retornou HTTP200 após patches, contra 500/401/400 anterior. Consultas limit0 comprovam contrato acessível, não autorização A/B completa.
- Todos dez handlers GET405: inexistência corrigida; isso não demonstra operação de negócio.
- POST reminders com segredo interno correto: HTTP200 `{ok:true,created:0,skipped:0,meetings:0}`. Sem reuniões na janela, nenhum destinatário criado.
- Vault/runtime possuem agora segredo interno novo `scheduled_reminders_secret`/`SCHEDULED_REMINDERS_SECRET`, criado com entropia criptográfica; valor não versionado.
- pg_net chamada request_id1 retornou HTTP200 com o mesmo JSON e sem timeout.
- cron.job jobid2 reminders-every-hour active=true `0 * * * *`; jobid1 refresh-mv-book-community-stats preservado `0 */6 * * *`. cron.job_run_details ainda vazio para novo job; primeira execução horária ainda não observada. Não simular histórico de execução.
- pg_stat_statements instalado 1.11. Planos feed/match/quiz usam índices existentes; volume feed0/quiz1/match0 não representativo.
- Advisors pós-cron: seis warnings extension_in_public (cinco pré-existentes e pg_net). Não mudar localização de extensões dependentes às cegas. Remediação: https://supabase.com/docs/guides/database/database-linter?lint=0014_extension_in_public

## Painel autenticado

https://supabase.com/dashboard/project/xjhehhfhhoomblcggjpk/functions/secrets
Antes: “No custom secrets created”. Depois: somente novo SCHEDULED_REMINDERS_SECRET. Portanto OpenAI/Resend/Stripe secrets personalizados ausentes, não apenas não verificáveis. As variáveis de OpenAI do sandbox são credenciais do ambiente Manus e não foram transferidas para Supabase.

https://supabase.com/dashboard/project/xjhehhfhhoomblcggjpk/database/backups/scheduled
Exibe “Free Plan does not include project backups. Upgrade to the Pro Plan for up to 7 days of scheduled backups.” Nenhum upgrade, compra ou mudança de cobrança executado. Backup automático não pode ser marcado concluído nesta configuração.

https://supabase.com/dashboard/project/xjhehhfhhoomblcggjpk/auth/providers
Painel acessível; estado HTTP `/auth/v1/settings` confirma Google/GitHub false. Não habilitados sem credenciais OAuth reais nem URL de aplicação, especialmente após frontend retirado do escopo.

## Documentação oficial consultada
- https://supabase.com/changelog.md
- https://supabase.com/docs/guides/functions/auth.md
- https://supabase.com/docs/guides/functions/auth-headers.md
- https://supabase.com/docs/guides/functions/schedule-functions.md
- https://supabase.com/docs/guides/database/vault.md
- https://supabase.com/docs/guides/monitoring-and-debugging.md

JWT gateway atual aceita HS256 e chaves assimétricas; manter gate user e validação requestUser. Vault guarda segredo cifrado e cron lê somente administrativamente. Provedores não recebem chaves fabricadas.
