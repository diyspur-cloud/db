# Limites de execução encontradas no SDD

A estrutura foi montada sem inventar nomes de tabelas, colunas ou regras. Três objetos SQL foram separados em `supabase/migrations/blocked/` porque dependem de elementos que não existem no documento nem no banco inicial vazio:

1. `mv_book_community_stats` e `build_user_reading_snapshot` fazem JOIN com `public.book_reviews`, não definida no SDD.
2. `v_club_progress_panel` consulta `public.clubs.current_book_id`, também não definido (o SDD define `public.user_clubs`, mas sem essa coluna).

A aplicação do restante é independente desses objetos. Edge Functions com dependências externas também podem exigir secrets específicos (Resend/Stripe/OpenAI) para funcionar em runtime.
