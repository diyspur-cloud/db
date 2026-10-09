-- Alinha o snapshot de estatísticas ao contrato original sem expor uma
-- materialized view administrativa como superfície de API.
-- A definição anterior não pode ser substituída com CREATE OR REPLACE MATERIALIZED VIEW;
-- a troca controlada preserva o nome privado, o índice e a agenda de refresh.

DROP VIEW IF EXISTS public.v_book_community_stats;
DO $$
DECLARE
  v_kind "char";
BEGIN
  SELECT c.relkind
    INTO v_kind
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public'
     AND c.relname = 'mv_book_community_stats';
  IF v_kind = 'v' THEN
    EXECUTE 'DROP VIEW public.mv_book_community_stats';
  ELSIF v_kind = 'm' THEN
    EXECUTE 'DROP MATERIALIZED VIEW public.mv_book_community_stats';
  END IF;
END;
$$;
DROP MATERIALIZED VIEW IF EXISTS private.mv_book_community_stats;

CREATE MATERIALIZED VIEW private.mv_book_community_stats AS
SELECT
  b.id AS book_id,
  COALESCE(bms.mood_percent, '{}'::jsonb) AS mood_percent,
  COALESCE(
    bms.pace_percent,
    '{"slow":0,"medium":0,"fast":0}'::jsonb
  ) AS pace_percent,
  bms.plot_vs_character_avg,
  bms.sample_size,
  COALESCE(AVG(br.rating), 0::numeric) AS avg_rating,
  COUNT(br.id) AS ratings_count,
  COALESCE(AVG(br.spice_level), 0::numeric) AS avg_spice_level
FROM public.books AS b
LEFT JOIN public.book_mood_stats AS bms
  ON bms.book_id = b.id
LEFT JOIN public.book_reviews AS br
  ON br.book_id = b.id
 AND br.deleted_at IS NULL
GROUP BY
  b.id,
  bms.mood_percent,
  bms.pace_percent,
  bms.plot_vs_character_avg,
  bms.sample_size;

CREATE UNIQUE INDEX mv_book_community_stats_book_id_idx
  ON private.mv_book_community_stats (book_id);

REVOKE ALL ON TABLE private.mv_book_community_stats
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE private.mv_book_community_stats
  TO anon, authenticated, service_role;

-- O contrato público usa o mesmo snapshot para todas as métricas. O alias
-- public.mv_book_community_stats permanece como compatibilidade de leitura,
-- mas não é uma materialized view nem uma nova fonte de dados.
CREATE VIEW public.v_book_community_stats
WITH (security_invoker = true)
AS
SELECT
  book_id,
  mood_percent,
  pace_percent,
  plot_vs_character_avg,
  sample_size,
  avg_rating,
  ratings_count,
  avg_spice_level
FROM private.mv_book_community_stats;

CREATE VIEW public.mv_book_community_stats
WITH (security_invoker = true)
AS
SELECT
  book_id,
  mood_percent,
  pace_percent,
  plot_vs_character_avg,
  sample_size,
  avg_rating,
  ratings_count,
  avg_spice_level
FROM private.mv_book_community_stats;

GRANT SELECT ON public.v_book_community_stats,
  public.mv_book_community_stats
  TO anon, authenticated, service_role;
