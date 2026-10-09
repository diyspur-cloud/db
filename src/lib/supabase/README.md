# Tipos gerados do schema Supabase

`database.types.ts` nesta pasta é um snapshot gerado do schema público remoto depois da migration `20261009020600` (2026-10-09). Ele foi produzido pelo gerador Supabase; os tipos gerados não foram escritos manualmente.

Em um ambiente autorizado, regenerar após migration revisada e comparar o diff:

```bash
supabase gen types typescript --project-id xjhehhfhhoomblcggjpk --schema public > src/lib/supabase/database.types.ts
```

Não rode o comando com credenciais administrativas indisponíveis nem grave secrets em `.env` versionado/CI logs. Revise mudanças inesperadas em views, grants/RPCs e relações antes de aceitar o novo contrato. Como o histórico CLI baseline ainda não está reconciliado, use `--project-id` somente para gerar tipos; não faça `db push` por causa disso.
