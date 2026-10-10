INSERT INTO public.book_content_warnings (book_id, warning_id, severity, is_community, notes)
SELECT b.id, w.id, 'moderate'::public.content_warning_severity, false, 'Aviso editorial da ficha do livro.'
  FROM public.books AS b
  JOIN public.content_warnings AS w ON w.code IN ('abuse', 'gaslighting')
 WHERE b.slug = 'verity'
   AND NOT EXISTS (
     SELECT 1
       FROM public.book_content_warnings AS existing
      WHERE existing.book_id = b.id
        AND existing.warning_id = w.id
   );
