# Fontes oficiais consultadas em 2026-10-09

Estas referências foram consultadas antes das migrations incrementais desta execução:

- [Supabase changelog](https://supabase.com/changelog.md) — atualização PostgreSQL 15.19/17.11 de 2026-09-25; bloqueio de alterações no schema `realtime` desde 2026-07-14; mudança de exposição automática do Data API em 2026-04-28.
- [Views e materialized views](https://supabase.com/docs/guides/database/views) — views usam permissões do criador por padrão; `security_invoker=true` aplica as políticas da tabela subjacente; materialized views precisam de refresh explícito e índice único para refresh concorrente.
- [Seeding your database](https://supabase.com/docs/guides/local-development/seeding-your-database) — seeds são executados após migrations; `sql_paths` preserva a ordem declarada e deduplica arquivos casados por mais de um padrão.
- [Local development workflow](https://supabase.com/docs/guides/local-development/cli-workflows) — `db reset` local é descartável, `--linked` deve ser reservado para ambiente controlado e `--include-seed` não deve ser usado em produção.
- [Database migrations](https://supabase.com/docs/guides/local-development/database-migrations) — criar migrations com `supabase migration new`, validar o replay local e não tratar `db diff` como saída final sem revisão.
- [Realtime Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes) — tabelas precisam estar na publicação `supabase_realtime`; canais usam `postgres_changes`, filtros `eq` e cleanup com remoção do canal.

Nenhuma destas fontes autoriza habilitar providers OAuth, cadastrar preços Stripe, publicar funções ou inventar URLs de conteúdo sem as credenciais/dados correspondentes.
