# Referências de implementação Supabase

Consultadas/revisadas em 8 de outubro de 2026 durante o hardening e smoke tests:

- [Database Views — Supabase](https://supabase.com/docs/guides/database/views): views PostgreSQL com `security_invoker=true` usam permissões e RLS do chamador. As nove views públicas foram configuradas dessa forma; valide o contrato sob sessão anônima/autenticada antes de produção.
- [Tables and Data — Supabase](https://supabase.com/docs/guides/database/tables): contexto de tabelas e exposição pela Data API. O materialized view interno foi movido para `private`; o contrato público é `v_book_community_stats`.
- [PostgreSQL CREATE VIEW](https://www.postgresql.org/docs/current/sql-createview.html): referência para opções e comportamento de views.
- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security): políticas devem corresponder ao contrato de titular/administrador; `auth.uid()` pode ser avaliado via initplan com `(select auth.uid())` quando a semântica não muda.
- [Supabase Database Linter](https://supabase.com/docs/guides/database/database-linter): findings remanescentes incluem extensões no schema `public`, índices sem uso observado e múltiplas policies permissivas no baseline. O advisor deve ser reexecutado depois de qualquer mudança.
- [Supabase API keys](https://supabase.com/docs/guides/api/api-keys): publishable key é destinada a cliente e não substitui credencial administrativa/CLI para DDL.

As migrations e smoke tests foram aplicados ao projeto `xjhehhfhhoomblcggjpk`. Nenhuma credencial foi copiada do ambiente para o repositório; a publishable key fornecida é uma chave de cliente, não uma credencial administrativa para migrations.

- [Supabase Cron](https://supabase.com/docs/guides/cron): `pg_cron` cria/usa o schema `cron`, armazena jobs em `cron.job` e execuções em `cron.job_run_details`; neste projeto, o registro da extensão está em `pg_catalog`. O job local deste projeto atualiza a MV privada a cada seis horas; reminders dependem de função e autenticação ainda ausentes.
