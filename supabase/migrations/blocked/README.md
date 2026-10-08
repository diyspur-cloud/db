# Objetos aguardando definições ausentes no SDD

Não aplicar estes trechos até o esquema incluir explicitamente as tabelas/colunas referenciadas. O documento fornecido não define `public.book_reviews`, nem `public.clubs.current_book_id`. Não foram inventados objetos ou colunas.

- `views_missing_relations.sql`: `mv_book_community_stats` depende de `book_reviews`; `v_club_progress_panel` depende de `clubs.current_book_id`.
- `functions_missing_relations.sql`: `build_user_reading_snapshot` depende de `book_reviews`.
