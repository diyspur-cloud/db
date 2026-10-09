-- Source: SDDBD2.md section 11.2; guarded for repeat execution.
-- =====================================================================
-- 1. Content Warnings padrão
-- =====================================================================
insert into public.content_warnings (code, label, description, category) values
  ('violence','Violência','Cenas de violência física ou verbal.','violence'),
  ('grief','Luto','Morte de personagens ou luto explícito.','mental_health'),
  ('abuse','Abuso','Abuso físico, psicológico ou emocional.','violence'),
  ('self_harm','Autolesão','Referências a autolesão ou suicídio.','mental_health'),
  ('racism','Racismo','Comentários ou estruturas racistas.','identity'),
  ('sexism','Machismo','Comentários ou estruturas misóginas.','identity'),
  ('mental_illness','Doença mental','Retrato de transtornos mentais.','mental_health'),
  ('adultery','Adultério','Relacionamentos extraconjugais.','relationships'),
  ('classism','Classismo','Preconceito de classe.','identity'),
  ('gaslighting','Gaslighting','Manipulação psicológica.','mental_health')
ON CONFLICT (code) DO NOTHING;

-- CW do Dom Casmurro
insert into public.book_content_warnings (book_id, warning_id, severity, is_community, community_votes, notes)
select
  '22222222-2222-2222-2222-222222222222',
  cw.id,
  'moderate',
  false,
  0,
  'Presente no núcleo do romance.'
from public.content_warnings cw
where cw.code in ('adultery','gaslighting','sexism','classism')
ON CONFLICT (book_id, warning_id) DO NOTHING;

-- =====================================================================
-- 2. Mood labels (pt-BR)
-- =====================================================================
insert into public.mood_labels (mood, label_pt, color_hex, icon) values
  ('adventurous','Aventureiro','#F59E0B','compass'),
  ('emotional','Emocionante','#EC4899','heart'),
  ('dark','Sombrio','#1F2937','moon'),
  ('funny','Divertido','#FBBF24','smile'),
  ('hopeful','Esperançoso','#10B981','sunrise'),
  ('informative','Informativo','#3B82F6','info'),
  ('inspiring','Inspirador','#8B5CF6','sparkles'),
  ('lighthearted','Descontraído','#34D399','feather'),
  ('mysterious','Misterioso','#6D28D9','search'),
  ('reflective','Reflexivo','#0EA5E9','brain'),
  ('sad','Triste','#64748B','cloud-rain'),
  ('tense','Tenso','#DC2626','alert'),
  ('challenging','Desafiador','#7C3AED','mountain')
ON CONFLICT (mood) DO NOTHING;

-- =====================================================================
-- 3. Escolha editorial do mês
-- =====================================================================
insert into public.editorial_picks (
  book_id, season_id, kind, reference_month, title, rationale, is_active
) values (
  '22222222-2222-2222-2222-222222222222',
  '33333333-3333-3333-3333-333333333333',
  'book_of_the_month',
  date_trunc('month', current_date)::date,
  'Dom Casmurro — a dúvida que nos constitui',
  'Escolhemos reler Machado porque a pergunta sobre Capitu continua sendo, antes de tudo, uma pergunta sobre nós.',
  true
) ON CONFLICT (kind, reference_month) DO NOTHING;

-- =====================================================================
-- 4. Mood stats baseline (vazio, será preenchido por votos)
-- =====================================================================
insert into public.book_mood_stats (book_id) values
  ('22222222-2222-2222-2222-222222222222')
on conflict (book_id) do nothing;

-- =====================================================================
-- 5. Milestones automáticos para a temporada 1
-- =====================================================================
select public.generate_milestones_for_season('33333333-3333-3333-3333-333333333333');

-- =====================================================================
-- 6. Conteúdo extra de exemplo
-- =====================================================================
insert into public.chapter_extra_content (chapter_id, kind, title, description, external_url, position, is_public)
select c.id, 'pdf', 'Guia de leitura — Capítulos I a V',
       'Perguntas para discussão em grupo e citações marcantes.',
       'https://exemplo.clube/guia-cap1.pdf', 1, true
from public.chapters c where c.number = 1
  and c.season_id = '33333333-3333-3333-3333-333333333333'
  AND NOT EXISTS (SELECT 1 FROM public.chapter_extra_content x WHERE x.chapter_id = c.id AND x.title = 'Guia de leitura — Capítulos I a V');

insert into public.chapter_extra_content (chapter_id, kind, title, description, external_url, position, is_public)
select c.id, 'slides', 'Slides do encontro ao vivo',
       'Deck usado na discussão síncrona.',
       'https://exemplo.clube/slides-cap1.pdf', 2, true
from public.chapters c where c.number = 1
  and c.season_id = '33333333-3333-3333-3333-333333333333'
  AND NOT EXISTS (SELECT 1 FROM public.chapter_extra_content x WHERE x.chapter_id = c.id AND x.title = 'Slides do encontro ao vivo');

-- =====================================================================
-- 7. Atividade interativa de exemplo
-- =====================================================================
insert into public.chapter_activities (chapter_id, kind, status, title, instructions, config, xp_reward, position)
select
  c.id, 'crossword', 'published',
  'Palavras cruzadas — personagens do romance',
  'Complete as lacunas com os nomes dos personagens.',
  jsonb_build_object(
    'rows', 5, 'cols', 5,
    'words', jsonb_build_array(
      jsonb_build_object('word','BENTINHO','row',0,'col',0,'dir','h'),
      jsonb_build_object('word','CAPITU','row',2,'col',0,'dir','h')
    )
  ),
  25, 1
from public.chapters c where c.number = 1
  and c.season_id = '33333333-3333-3333-3333-333333333333'
ON CONFLICT (chapter_id, position) DO NOTHING;

-- =====================================================================
-- 8. Prompt de caderno interativo
-- =====================================================================
insert into public.chapter_prompts (chapter_id, position, prompt, hint, min_chars, max_chars)
select c.id, 1,
       'Qual sua hipótese sobre o ciúme de Bentinho antes de terminar o capítulo?',
       'Não há resposta certa — anote sua leitura.',
       20, 2000
from public.chapters c where c.number = 3
  and c.season_id = '33333333-3333-3333-3333-333333333333'
ON CONFLICT (chapter_id, position) DO NOTHING;

-- =====================================================================
-- 9. Planos de assinatura
-- =====================================================================
insert into public.membership_plans (code, tier, name, description, price_cents, interval, perks) values
  ('free','free','Leitor','Acesso ao ciclo atual e à comunidade.',
   0, 'month',
   '[]'::jsonb),
  ('plus_monthly','plus','Plus (mensal)','Acesso antecipado, listas ilimitadas, badges premium.',
   1990, 'month',
   '[{"code":"early_access","label":"Acesso antecipado"},{"code":"unlimited_lists","label":"Listas ilimitadas"},{"code":"premium_badges","label":"Badges premium"}]'::jsonb),
  ('plus_annual','plus','Plus (anual)','Tudo do Plus com 2 meses de desconto.',
   19900, 'year',
   '[{"code":"early_access","label":"Acesso antecipado"},{"code":"unlimited_lists","label":"Listas ilimitadas"},{"code":"premium_badges","label":"Badges premium"},{"code":"annual_discount","label":"Desconto anual"}]'::jsonb),
  ('patron','patron','Patrono','Apoia o clube e recebe menções no podcast.',
   4990, 'month',
   '[{"code":"patron_credit","label":"Créditos no podcast"},{"code":"shop_discount","label":"Desconto na loja"}]'::jsonb)
ON CONFLICT (code) DO NOTHING;

-- =====================================================================
-- 10. Conquistas específicas (complementando o seed original)
-- =====================================================================
insert into public.achievements (code, title, description, rule, xp_reward) values
  ('brazilian_lit_expert','Especialista em Literatura Brasileira',
   'Leu 5 ou mais obras de autores brasileiros no clube.',
   '{"type":"genre_count","genre":"Literatura Brasileira","gte":5}'::jsonb, 150),
  ('five_books','Cinco livros lidos',
   'Concluiu 5 livros no clube.',
   '{"type":"count","source":"finish_book","gte":5}'::jsonb, 100),
  ('perfect_quiz','100% no quiz',
   'Acertou todas as perguntas de um quiz.',
   '{"type":"perfect_quiz","gte":1}'::jsonb, 75)
on conflict (code) do nothing;

-- =====================================================================
-- 11. Newsletter de exemplo (não disparada)
-- =====================================================================
insert into public.newsletter_issues (slug, subject, preview_text, body_markdown, audience_filter, created_by)
select
  'boas-vindas-t1',
  'Bem-vindo ao Clube — Temporada Dom Casmurro',
  'Começamos a leitura dia 1º. Veja como funciona.',
  E'# Bem-vindo ao Clube\n\nNesta temporada lemos **Dom Casmurro**.\n\n- Leia em blocos.\n- Marque o progresso.\n- Comente sem spoilers.',
  '{"tags":["welcome"]}'::jsonb,
  (select id from public.profiles where role = 'admin' limit 1)
ON CONFLICT (slug) DO NOTHING;
