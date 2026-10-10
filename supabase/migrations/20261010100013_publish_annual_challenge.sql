INSERT INTO public.challenges (title, description, year, prompt_rules)
SELECT '12 livros em 12 meses',
       'Escolha uma leitura por mês e acompanhe seu ritmo ao longo do ano.',
       2026,
       '{"type":"annual_books","target":12}'::jsonb
 WHERE NOT EXISTS (
   SELECT 1 FROM public.challenges WHERE title = '12 livros em 12 meses'
 );
