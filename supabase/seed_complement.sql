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

-- A classificação indicativa de Verity (18 anos) está na ficha do livro.
-- Não são inseridos avisos granulares sem validação editorial específica.

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
)
select b.id, s.id, 'book_of_the_month', date_trunc('month', current_date)::date,
       'Verity — o suspense por trás do manuscrito',
       'Um suspense psicológico em que um manuscrito e uma casa cheia de perguntas convidam o clube a comparar versões.',
       true
  from public.books b
  join public.seasons s on s.book_id = b.id
 where b.slug = 'verity' and s.slug = 't1-verity'
on conflict (kind, reference_month) do update set
  book_id = excluded.book_id,
  season_id = excluded.season_id,
  title = excluded.title,
  rationale = excluded.rationale,
  is_active = excluded.is_active;

-- =====================================================================
-- 4. Mood stats baseline (vazio, será preenchido por votos)
-- =====================================================================
insert into public.book_mood_stats (book_id)
select id from public.books where slug = 'verity' limit 1
on conflict (book_id) do nothing;

-- =====================================================================
-- 5. Milestones automáticos para a temporada 1
-- =====================================================================
select public.generate_milestones_for_season((select id from public.seasons where slug = 't1-verity' limit 1));

-- =====================================================================
-- 6. Conteúdo extra
-- =====================================================================
-- Sem links externos fictícios; adicionar material somente quando publicado.

-- =====================================================================
-- 7. Atividade interativa de exemplo
-- =====================================================================
insert into public.chapter_activities (chapter_id, kind, status, title, instructions, config, xp_reward, position)
select
  c.id, 'crossword', 'published',
  'Palavras cruzadas — personagens de Verity',
  'Complete as lacunas com nomes apresentados na sinopse editorial.',
  jsonb_build_object(
    'rows', 6, 'cols', 6,
    'words', jsonb_build_array(
      jsonb_build_object('word','LOWEN','row',0,'col',0,'dir','h'),
      jsonb_build_object('word','VERITY','row',2,'col',0,'dir','h'),
      jsonb_build_object('word','JEREMY','row',4,'col',0,'dir','h')
    )
  ),
  25, 1
from public.chapters c where c.number = 1
  and c.season_id = (select id from public.seasons where slug = 't1-verity' limit 1)
ON CONFLICT (chapter_id, position) DO NOTHING;

-- =====================================================================
-- 8. Prompt de caderno interativo
-- =====================================================================
insert into public.chapter_prompts (chapter_id, position, prompt, hint, min_chars, max_chars)
select c.id, 1,
       'Que detalhe da narrativa influencia sua confiança nas versões da história até aqui?',
       'Não há resposta certa — anote sua leitura sem spoilers.',
       20, 2000
from public.chapters c where c.number = 3
  and c.season_id = (select id from public.seasons where slug = 't1-verity' limit 1)
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
  'Bem-vindo ao Clube — Temporada Verity',
  'Começamos a leitura dia 1º. Veja como funciona.',
  E'# Bem-vindo ao Clube\n\nNesta temporada lemos **Verity**, de Colleen Hoover.\n\n- Leia em blocos.\n- Marque o progresso.\n- Comente sem spoilers.',
  '{"tags":["welcome"]}'::jsonb,
  (select id from public.profiles where role = 'admin' limit 1)
ON CONFLICT (slug) DO NOTHING;
