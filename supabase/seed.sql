-- Source: SDDBD2.md section 11.1; guarded for repeat execution.
-- Autor
insert into public.authors (id, name, slug, bio) values
  ('11111111-1111-1111-1111-111111111111',
   'Machado de Assis','machado-de-assis','Escritor brasileiro (1839–1908).') ON CONFLICT (id) DO NOTHING;

-- Livro
insert into public.books (id, title, slug, author_id, isbn13, total_chapters, total_pages, publication_year, amazon_url, tags, synopsis)
values
  ('22222222-2222-2222-2222-222222222222',
   'Dom Casmurro','dom-casmurro',
   '11111111-1111-1111-1111-111111111111',
   '9788535910663', 148, 256, 1899,
   'https://www.amazon.com.br/dp/8535910663?tag=clubedolivro-20',
   array['Literatura Brasileira','Realismo','Clássico'],
   'Bentinho, Capitu e o ciúme que atravessa gerações.') ON CONFLICT (id) DO NOTHING;

-- Temporada
insert into public.seasons (id, number, title, slug, book_id, status, starts_at, ends_at)
values
  ('33333333-3333-3333-3333-333333333333', 1, 'Dom Casmurro','t1-dom-casmurro',
   '22222222-2222-2222-2222-222222222222','active', current_date, current_date + interval '35 days') ON CONFLICT (id) DO NOTHING;

-- 5 capítulos (blocos)
insert into public.chapters (season_id, number, title, reading_range, youtube_url, summary)
values
  ('33333333-3333-3333-3333-333333333333',1,'Capítulos I a V','pág. 1–35 · ~25 min','https://youtu.be/...','Do trem ao seminário.'),
  ('33333333-3333-3333-3333-333333333333',2,'Capítulos VI a X','pág. 36–70 · ~28 min',null,'A promessa e o seminário.'),
  ('33333333-3333-3333-3333-333333333333',3,'Capítulos XI a XV','pág. 71–110 · ~30 min',null,'Capitu e o primeiro ciúme.'),
  ('33333333-3333-3333-3333-333333333333',4,'Capítulos XVI a XX','pág. 111–160 · ~35 min',null,'O casamento.'),
  ('33333333-3333-3333-3333-333333333333',5,'Capítulos XXI a fim','pág. 161–256 · ~45 min',null,'Ezequiel e o desfecho.') ON CONFLICT (season_id, number) DO NOTHING;

-- Quiz do Cap. 1
insert into public.quiz_questions (chapter_id, position, question, options, correct_idx, explanation)
select c.id, 1, 'Quem narra Dom Casmurro?',
       '["Capitu","Bentinho","José Dias","Ezequiel"]'::jsonb, 1,
       'Bentinho é o narrador em primeira pessoa.'
from public.chapters c where c.number = 1
  and c.season_id = '33333333-3333-3333-3333-333333333333'
ON CONFLICT (chapter_id, position) DO NOTHING;

-- Pergunta do anfitrião do Cap. 3
insert into public.host_prompts (chapter_id, question, options)
select c.id, 'José Dias realmente estava tentando ajudar Bentinho?',
       '["Concordo","Discordo","Ainda não sei"]'::jsonb
from public.chapters c where c.number = 3
  and c.season_id = '33333333-3333-3333-3333-333333333333'
  AND NOT EXISTS (SELECT 1 FROM public.host_prompts hp WHERE hp.chapter_id = c.id AND hp.question = 'José Dias realmente estava tentando ajudar Bentinho?');

-- Conquistas padrão
insert into public.achievements (code, title, description, rule, xp_reward) values
  ('first_book','Primeiro livro','Concluiu o primeiro livro do clube.',
    '{"type":"count","source":"finish_book","gte":1}'::jsonb, 50),
  ('streak_4w','4 semanas seguidas','Manteve streak de 4 semanas.',
    '{"type":"streak","gte":28}'::jsonb, 100),
  ('machado_master','Mestre do Machado','Concluiu todas as obras de Machado na plataforma.',
    '{"type":"author_complete","author":"machado-de-assis"}'::jsonb, 200) ON CONFLICT (code) DO NOTHING;
