# Supabase database — Clube de Leitura

Implementação versionada do SDD [`SDDBD2.md`](./SDDBD2.md), com migrations SQL, seeds, arquivos de referência TypeScript e fontes de Edge Functions.

## Projeto e repositório

- Supabase project ref: `xjhehhfhhoomblcggjpk`
- GitHub: [`diyspur-cloud/db`](https://github.com/diyspur-cloud/db)
- Visibilidade: pública. Não adicionar tokens, service keys, segredos de integração nem dados pessoais.

## Estado da implantação

O escopo SQL executável foi aplicado no Supabase. O relatório do double check, contagens verificadas, alertas dos advisors e pendências está em [`docs/deployment-status.md`](./docs/deployment-status.md).

As migrations-fonte estão em `supabase/migrations/`; os dados-base idempotentes estão em `supabase/seed.sql` e `supabase/seed_complement.sql`. Os bundles de execução MCP ficam em `supabase/deploy-bundles/` e são gerados por `python3 scripts/build-remote-bundles.py`.

**Atenção:** a ferramenta de implantação remota registrou versões `20261008…` no histórico do Supabase, enquanto os arquivos-fonte têm nomes `20260101…`. Não execute `supabase db push` diretamente contra o projeto já implantado antes de reconciliar esse histórico/baseline; consulte o relatório.

## Edge Functions

As fontes estão em `supabase/functions/` e o script de deploy em `scripts/deploy-edge-functions.sh`. Nenhuma Edge Function foi implantada nesta rodada: várias requerem secrets de OpenAI/Stripe/Resend e algumas precisam de endurecimento de autenticação/autorização para não expor operações privilegiadas. Consulte [`docs/deployment-status.md`](./docs/deployment-status.md) antes do deploy.

## Limites do SDD

Três objetos SQL foram isolados em `supabase/migrations/blocked/` porque o próprio SDD referencia objetos não definidos: `public.book_reviews` e `public.clubs.current_book_id`. Veja [`docs/implementation-blockers.md`](./docs/implementation-blockers.md).

## Tipos TypeScript

Depois de reconciliar o histórico de migrations, gere os tipos a partir do schema remoto e atualize `src/types/`; instruções em [`src/lib/supabase/README.md`](./src/lib/supabase/README.md).
