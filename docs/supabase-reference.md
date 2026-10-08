# Referências de implementação Supabase

Consultadas em 8 de outubro de 2026 durante a revisão do SDD:

- [Database Views — Supabase](https://supabase.com/docs/guides/database/views): views PostgreSQL normalmente verificam acesso às tabelas subjacentes como o proprietário da view; `security_invoker=true` faz a consulta usar permissões/RLS do chamador. As views do SDD foram mantidas conforme especificadas; revisar esse atributo antes de expor views com dados pessoais.
- [Tables and Data — Supabase](https://supabase.com/docs/guides/database/tables): contexto da criação de tabelas e acesso pela Data API.
- [PostgreSQL CREATE VIEW](https://www.postgresql.org/docs/current/sql-createview.html): referência para opções e comportamento de views.

Nenhuma credencial foi copiada do ambiente para o repositório. A chave publishable fornecida é uma chave de cliente, não uma credencial administrativa para migrações.
