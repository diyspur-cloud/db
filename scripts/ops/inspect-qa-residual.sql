-- Executar com uma conexão read-only apontada para o ambiente explicitamente aprovado.
-- Nunca incluir tokens ou URLs de conexão neste arquivo.
SELECT
  id,
  name,
  owner_id,
  created_at,
  archived_at,
  is_private
FROM public.user_clubs
WHERE name = 'QA RETESTE 20261010'
ORDER BY created_at DESC
LIMIT 10;
