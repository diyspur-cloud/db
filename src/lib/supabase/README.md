# Tipos gerados do schema Supabase

`database.types.ts` nesta pasta é um snapshot gerado do schema público remoto depois da migration `20261009020600` (2026-10-09). Ele foi produzido pelo gerador Supabase; os tipos gerados não foram escritos manualmente.

Em um ambiente autorizado, regenerar após migration revisada e comparar o diff:

```bash
supabase gen types typescript --project-id xjhehhfhhoomblcggjpk --schema public > src/lib/supabase/database.types.ts
```

Não rode o comando com credenciais administrativas indisponíveis nem grave secrets em `.env` versionado/CI logs. Revise mudanças inesperadas em views, grants/RPCs e relações antes de aceitar o novo contrato. Como o histórico CLI baseline ainda não está reconciliado, use `--project-id` somente para gerar tipos; não faça `db push` por causa disso.

## Adapters de produto

- `media.ts`: upload somente no diretório do usuário e URLs assinadas temporárias; extras consultam `chapter_extra_content` antes de assinar.
- `realtime.ts`: canais nomeados por tela, callback de status e cleanup; o callback de mudança deve recarregar a view autorizada, nunca renderizar `payload.new` diretamente.
- `profile.ts`, `stats.ts`, `reading.ts` e `clubs.ts`: selects explícitos sobre views públicas/aliases já existentes.
- `quiz.ts` e `gamification.ts`: respostas/gamificação passam por Edge Functions; o browser não calcula score nem faz DML privilegiado.
- `social.ts` e `activities.ts`: normalizam o retorno de matching e o job síncrono de cards; `src/components/reading/SocialCard.tsx` exibe `queued`, `rendered` e `failed`.

Os adapters são fontes locais de contrato, não comprovam que o working tree foi publicado. A sessão real, RLS, Storage, WebSocket, providers e deploy devem ser validados no ambiente descartável/controlado documentado em `docs/execution/`.
