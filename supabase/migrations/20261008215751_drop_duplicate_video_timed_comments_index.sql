-- vtc_sec_idx era estruturalmente idêntico a vtc_chapter_sec_idx.
-- Mantém-se o índice com nome de domínio explícito e remove-se a cópia exata.
drop index if exists public.vtc_sec_idx;
