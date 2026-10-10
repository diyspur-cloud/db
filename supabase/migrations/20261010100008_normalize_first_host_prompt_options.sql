UPDATE public.host_prompts AS p
   SET options = '["Curiosidade","Desconfiança","Ainda não sei"]'::jsonb
  FROM public.chapters AS c
  JOIN public.seasons AS s ON s.id = c.season_id
 WHERE p.chapter_id = c.id
   AND s.slug = 't1-verity'
   AND c.number = 1
   AND p.question = 'Qual sensação ficou mais forte depois deste primeiro encontro com Verity?';
