-- ============================================================================
-- DIYSpur - Script de Inspeção de Resíduos de Teste e Auditoria (Read-Only)
--
-- Executar exclusivamente com conexão read-only apontada para o ambiente desejado.
-- NUNCA executar comandos destrutivos (DELETE/DROP) sem backup prévio e aprovação.
-- Nunca incluir tokens, senhas ou strings de conexão neste arquivo.
-- ============================================================================

-- 1. Clubes de leitura sintéticos ou criados durante testes
SELECT
  'user_clubs' AS entity_type,
  id,
  name AS identifier,
  owner_id,
  created_at,
  archived_at,
  is_private
FROM public.user_clubs
WHERE name ILIKE 'QA %'
   OR name ILIKE '%RETESTE%'
   OR name ILIKE '%AUDITORIA%'
   OR name ILIKE '[TESTE]%'
ORDER BY created_at DESC;

-- 2. Comentários de capítulos gerados em testes de QA
SELECT
  'comments' AS entity_type,
  id,
  LEFT(content, 80) AS identifier,
  user_id,
  chapter_id,
  is_spoiler,
  created_at
FROM public.comments
WHERE content ILIKE 'QA %'
   OR content ILIKE '%RETESTE%'
   OR content ILIKE '%AUDITORIA%'
   OR content ILIKE '[TESTE]%'
ORDER BY created_at DESC;

-- 3. Comentários com timestamp (vídeos) de testes de QA
SELECT
  'timed_comments' AS entity_type,
  id,
  LEFT(content, 80) AS identifier,
  user_id,
  chapter_id,
  timestamp_seconds,
  created_at
FROM public.timed_comments
WHERE content ILIKE 'QA %'
   OR content ILIKE '%RETESTE%'
   OR content ILIKE '%AUDITORIA%'
   OR content ILIKE '[TESTE]%'
ORDER BY created_at DESC;

-- 4. Enquetes sintéticas de QA
SELECT
  'polls' AS entity_type,
  id,
  title AS identifier,
  status,
  created_at
FROM public.polls
WHERE title ILIKE 'QA %'
   OR title ILIKE '%RETESTE%'
   OR title ILIKE '%AUDITORIA%'
   OR title ILIKE '[TESTE]%'
ORDER BY created_at DESC;

-- 5. Perfis de usuário com prefixo de teste
SELECT
  'profiles' AS entity_type,
  id,
  username,
  display_name AS identifier,
  created_at
FROM public.profiles
WHERE username ILIKE 'qa_%'
   OR username ILIKE 'test_%'
   OR display_name ILIKE 'QA %'
   OR display_name ILIKE '[TESTE]%'
ORDER BY created_at DESC;

-- 6. Resumo quantitativo de potenciais resíduos
SELECT
  'user_clubs' AS table_name,
  COUNT(*) AS residual_count
FROM public.user_clubs
WHERE name ILIKE 'QA %' OR name ILIKE '%RETESTE%' OR name ILIKE '%AUDITORIA%' OR name ILIKE '[TESTE]%'
UNION ALL
SELECT
  'comments' AS table_name,
  COUNT(*) AS residual_count
FROM public.comments
WHERE content ILIKE 'QA %' OR content ILIKE '%RETESTE%' OR content ILIKE '%AUDITORIA%' OR content ILIKE '[TESTE]%'
UNION ALL
SELECT
  'timed_comments' AS table_name,
  COUNT(*) AS residual_count
FROM public.timed_comments
WHERE content ILIKE 'QA %' OR content ILIKE '%RETESTE%' OR content ILIKE '%AUDITORIA%' OR content ILIKE '[TESTE]%'
UNION ALL
SELECT
  'polls' AS table_name,
  COUNT(*) AS residual_count
FROM public.polls
WHERE title ILIKE 'QA %' OR title ILIKE '%RETESTE%' OR title ILIKE '%AUDITORIA%' OR title ILIKE '[TESTE]%'
UNION ALL
SELECT
  'profiles' AS table_name,
  COUNT(*) AS residual_count
FROM public.profiles
WHERE username ILIKE 'qa_%' OR username ILIKE 'test_%' OR display_name ILIKE 'QA %' OR display_name ILIKE '[TESTE]%';
