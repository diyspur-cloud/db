# Supabase database — Clube de Leitura

Repositório de implementação baseado em [`SDDBD2.md`](./SDDBD2.md). Inclui migrations SQL modulares, seeds, Edge Functions e arquivos TypeScript do cliente/perfil.

## Projeto alvo

- Supabase project ref: `xjhehhfhhoomblcggjpk`
- Git remote: `https://github.com/diyspur-cloud/db`
- **Visibilidade do repositório:** pública (confirmada pelo GitHub ao validar o destino). Não coloque segredos, tokens ou dados pessoais neste repositório.

## Aplicação

As migrations em `supabase/migrations/` mantêm a separação modular e a ordem definida pelo SDD. Para execução via Supabase MCP, `supabase/deploy-bundles/` contém os grupos concatenados e manifestos auditáveis, gerados por `python3 scripts/build-remote-bundles.py`. Os seeds ficam separados em `supabase/seed.sql` e `supabase/seed_complement.sql`.

A aplicação remota ocorre nesta ordem: `001_foundation`, `002_base_security_and_functions`, `003_realtime_and_storage`, `004_complement_schema`, `005_complement_security_functions_views`, depois os dois seeds. Os objetos dependentes de referências não definidas estão em `supabase/migrations/blocked/` e **não** nos bundles ativos.

## Edge Functions

As fontes correspondem aos exemplos do SDD em `supabase/functions/`. Para deploy via CLI, configure `SUPABASE_PROJECT_REF` e secrets do lado do Supabase (por exemplo, `OPENAI_API_KEY`, `RESEND_API_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`) sem versioná-los. Veja `scripts/deploy-edge-functions.sh`. `ai-user-embeddings` aguarda a definição explícita do RPC/tabela de reviews ausentes.

## Bloqueios do SDD

Veja [`docs/implementation-blockers.md`](./docs/implementation-blockers.md): `book_reviews` e `clubs.current_book_id` são referenciados por três objetos SQL, mas não definidos no documento. Não criei schema fictício.

## Geração de tipos

Após aplicar as migrations, gere o tipo de banco real via `supabase gen types typescript --linked`; instruções em `src/lib/supabase/README.md`.
