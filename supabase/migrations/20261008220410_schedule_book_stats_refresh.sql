-- A extensão cria seu schema cron; não a force para extensions.
create extension if not exists pg_cron;

-- Mantém o cache de estatísticas atualizado sem bloquear leituras da view.
-- O índice único em book_id permite REFRESH ... CONCURRENTLY.
select cron.schedule(
  'refresh-mv-book-community-stats',
  '0 */6 * * *',
  'refresh materialized view concurrently private.mv_book_community_stats;'
);
