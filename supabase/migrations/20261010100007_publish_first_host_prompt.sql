INSERT INTO public.host_prompts (chapter_id, question, options)
SELECT c.id,
       'Qual sensação ficou mais forte depois deste primeiro encontro com Verity?',
       '["Curiosidade","Desconfiança","Empatia","Ainda estou formando uma impressão"]'::jsonb
  FROM public.chapters AS c
  JOIN public.seasons AS s ON s.id = c.season_id
 WHERE s.slug = 't1-verity'
   AND c.number = 1
   AND NOT EXISTS (
     SELECT 1
       FROM public.host_prompts AS existing
      WHERE existing.chapter_id = c.id
        AND existing.question = 'Qual sensação ficou mais forte depois deste primeiro encontro com Verity?'
   );
