-- Conteúdo editorial mínimo do ciclo Verity.
-- As perguntas usam apenas fatos presentes na sinopse/seed versionado; não
-- antecipam revelações do romance. Links de reunião externos ficam NULL até
-- a equipe publicar o canal oficial.
WITH items(season_slug, chapter_number, position, question, options, correct_idx, explanation) AS (
  VALUES
    ('t1-verity', 1, 1, 'Quem contrata Lowen para concluir os livros restantes da série de Verity?', '["Jeremy Crawford","Verity Crawford","Lowen Ashleigh","A editora de Verity"]'::jsonb, 0, 'Jeremy Crawford faz a proposta a Lowen.'),
    ('t1-verity', 1, 2, 'Qual é a profissão de Lowen no início da leitura?', '["Escritora","Advogada","Médica","Editora"]'::jsonb, 0, 'Lowen é uma escritora em dificuldades.'),
    ('t1-verity', 1, 3, 'Por que Verity está impossibilitada de escrever?', '["Após um acidente","Por uma viagem","Por falta de editora","Por ter mudado de país"]'::jsonb, 0, 'A sinopse informa que Verity fica impossibilitada após um acidente.'),
    ('t1-verity', 1, 4, 'O que Lowen encontra ao organizar os materiais de Verity?', '["Um manuscrito autobiográfico confidencial","Um contrato de tradução","Uma coleção de cartas da editora","Um diário de viagens"]'::jsonb, 0, 'O manuscrito autobiográfico confidencial é o achado central da sinopse.'),
    ('t1-verity', 1, 5, 'Qual atmosfera orienta a leitura coletiva de Verity?', '["Suspense psicológico","Fantasia épica","Comédia romântica","Ensaio histórico"]'::jsonb, 0, 'O livro está catalogado como suspense psicológico.'),
    ('t1-verity', 2, 1, 'Qual trabalho Lowen aceita para continuar sua trajetória?', '["Concluir a série de sucesso de Verity","Revisar um catálogo de poemas","Escrever uma biografia de Jeremy","Traduzir uma coleção"]'::jsonb, 0, 'A tarefa descrita na sinopse é concluir a série de Verity.'),
    ('t1-verity', 2, 2, 'Qual sobrenome identifica a família ligada à autora?', '["Crawford","Ashleigh","Britto","Record"]'::jsonb, 0, 'Verity e a família do ciclo são identificadas pelo sobrenome Crawford.'),
    ('t1-verity', 2, 3, 'Que tipo de material muda a decisão de Lowen?', '["Um manuscrito autobiográfico confidencial","Um mapa da cidade","Um álbum de fotografias da editora","Um roteiro de filme"]'::jsonb, 0, 'O manuscrito confidencial coloca Lowen diante de uma decisão difícil.'),
    ('t1-verity', 2, 4, 'Onde Lowen encontra o material confidencial?', '["Entre os materiais de Verity","Na editora de Jeremy","Em uma biblioteca pública","Em um arquivo da tradutora"]'::jsonb, 0, 'Ela encontra o material enquanto organiza os materiais de Verity.'),
    ('t1-verity', 2, 5, 'Qual gênero é informado para o livro do ciclo?', '["Suspense psicológico","Ficção científica","Fantasia","Não ficção"]'::jsonb, 0, 'O catálogo editorial identifica Verity como suspense psicológico.'),
    ('t1-verity', 3, 1, 'A mansão do título está ligada a qual família?', '["Crawford","Ashleigh","Hoover","Record"]'::jsonb, 0, 'O título do capítulo menciona a mansão Crawford.'),
    ('t1-verity', 3, 2, 'Quem é a autora impossibilitada de escrever após um acidente?', '["Verity Crawford","Lowen Ashleigh","Jeremy Crawford","A editora"]'::jsonb, 0, 'A sinopse identifica Verity Crawford como a autora.'),
    ('t1-verity', 3, 3, 'Qual descoberta funciona como eixo do suspense?', '["Um manuscrito autobiográfico confidencial","Um novo contrato editorial","Um convite para viajar","Uma crítica publicada"]'::jsonb, 0, 'A descoberta do manuscrito move a decisão de Lowen.'),
    ('t1-verity', 3, 4, 'Qual personagem aceita concluir a série de Verity?', '["Lowen Ashleigh","Verity Crawford","Jeremy Crawford","A tradutora"]'::jsonb, 0, 'Lowen aceita o trabalho descrito na sinopse.'),
    ('t1-verity', 3, 5, 'Que tipo de decisão a descoberta coloca diante de Lowen?', '["Uma decisão difícil","Uma mudança de editora","Uma viagem internacional","Uma escolha de tradução"]'::jsonb, 0, 'A sinopse descreve a decisão de Lowen como difícil.')
)
INSERT INTO public.quiz_questions (chapter_id, position, question, options, correct_idx, explanation)
SELECT c.id, i.position, i.question, i.options, i.correct_idx, i.explanation
  FROM items AS i
  JOIN public.seasons AS s ON s.slug = i.season_slug
  JOIN public.chapters AS c ON c.season_id = s.id AND c.number = i.chapter_number
ON CONFLICT (chapter_id, position) DO NOTHING;

INSERT INTO public.host_prompts (chapter_id, question, options)
SELECT c.id,
       'Que pista até agora mais influencia sua confiança nas versões da história?',
       '["As anotações","O ambiente da casa","As conversas","Ainda estou em dúvida"]'::jsonb
  FROM public.chapters AS c
  JOIN public.seasons AS s ON s.id = c.season_id
 WHERE s.slug = 't1-verity' AND c.number = 3
   AND NOT EXISTS (
     SELECT 1 FROM public.host_prompts AS existing
      WHERE existing.chapter_id = c.id
        AND existing.question = 'Que pista até agora mais influencia sua confiança nas versões da história?'
   );

INSERT INTO public.meetings (chapter_id, title, kind, status, scheduled_at, duration_min, meeting_url, location, agenda)
SELECT c.id,
       'Encontro do clube · Capítulo 1',
       'online',
       'scheduled',
       TIMESTAMPTZ '2026-10-14 23:00:00+00',
       60,
       NULL,
       'Online · link será publicado pela equipe',
       'Conversa sobre primeiras impressões, manuscrito e versões da história. Sem spoilers além do capítulo 1.'
  FROM public.chapters AS c
  JOIN public.seasons AS s ON s.id = c.season_id
 WHERE s.slug = 't1-verity' AND c.number = 1
   AND NOT EXISTS (
     SELECT 1 FROM public.meetings AS existing
      WHERE existing.chapter_id = c.id
        AND existing.title = 'Encontro do clube · Capítulo 1'
   );
