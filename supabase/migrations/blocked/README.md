# Referências históricas resolvidas

Os SQLs desta pasta foram separados originalmente porque o SDD referenciava relações/colunas que ainda não existiam. Em 8 de outubro de 2026, as dependências necessárias foram implementadas por migrations versionadas na raiz `supabase/migrations/`.

- `views_missing_relations.sql`: os contratos foram implementados em `20261008214920_add_community_reading_views.sql`; estatísticas do livro usam `public.book_reviews` e `v_club_progress_panel` usa `public.user_clubs` com contexto opcional. O materialized view fica em `private` após `20261008215324_harden_community_data_access.sql`.
- `functions_missing_relations.sql`: `public.build_user_reading_snapshot(uuid)` foi criada em `20261008214920_add_community_reading_views.sql` com restrição de titular e privilégios ajustados.

**Não execute nem copie estes trechos para produção.** Permanecem somente para rastreabilidade do texto histórico do SDD; aplicar novamente causará objetos duplicados ou comportamento incompatível com os grants/RLS finais. O caminho executável é a sequência registrada no histórico remoto e espelhada nos arquivos `20261008*.sql`.
