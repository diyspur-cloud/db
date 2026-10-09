# Contrato de autorização das Edge Functions

**Estado em 2026-10-09:** há fonte versionada e estática para 11 funções; o inventário remoto retorna **0 funções implantadas**. Typecheck, lint e formatação Deno passaram. Esses resultados não equivalem a testes HTTP em Supabase hospedado. As funções devem permanecer sem deploy até a lista de secrets, autenticação externa, teste em staging e proteção do ambiente GitHub estarem prontas.

## Matriz por endpoint

| Função | Identidade/autorização no handler | Limites e idempotência | Gate de gateway |
|---|---|---|---|
| `award-xp` | JWT Supabase; fonte e `ref_id` validados contra atividade do próprio usuário; valores de XP são constantes server-side. Chama `award_xp` via service-role somente depois da verificação. | Índice parcial impede XP duplicado por usuário/source/ref. | JWT ligado (padrão). `streak_bonus` não é aceito pelo cliente. Prova evento no banco, não presença/leitura no mundo real. |
| `vote-next-book` | JWT; ignora UUID de usuário do body; valida poll aberto e opção pertencente por RPC/transação. | Uma linha por leitor/enquete; escrita atômica. | JWT ligado (padrão). |
| `scheduled-reminders` | Só header `x-scheduled-reminders-secret`, comparação em tempo constante; serviço lista meetings/RSVP e chama RPC de entrega. | Unique/idempotência por user/meeting/window em ledger privado. | **`verify_jwt=false` intencional**: não há JWT de usuário; segredo de serviço é validado no handler antes do cliente privilegiado. |
| `ai-recommendations` | JWT; calcula snapshot apenas para `sub` validado; não aceita dono arbitrário do body. | Limites de payload/resultados e controle de erro do provider; configurar budget/rate limit de provedor. | JWT ligado (padrão). |
| `ai-user-embeddings` | JWT/ownership; snapshot associado ao leitor autenticado; hash SHA-256 do snapshot. | Evitar recomputação por request e controlar custo do provider. | JWT ligado (padrão). |
| `match-readers` | JWT; matching parte exclusivamente do user id autenticado; entrega campos públicos limitados e overlaps calculados por RPC. | Parâmetro de quantidade validado/limitado; não retorna vetores pessoais. | JWT ligado (padrão). |
| `newsletter-dispatch` | JWT mais papel `admin` consultado em fonte confiável; somente edição existente, audiencia permitida, subscriber `confirmed` e sem unsubscribe. | Claim/lease por issue/audience; log por recipient; retry ignora entrega `sent` preexistente. | JWT ligado (padrão). |
| `stripe-webhook` | Assinatura Stripe sobre corpo bruto via `stripe-signature` e `STRIPE_WEBHOOK_SECRET`; metadados/user IDs validados. RPC privilegiada transacional registra event id e atualiza subscription. | Event id único/replay idempotente; erro transitório retorna 5xx para retry Stripe. | **`verify_jwt=false` intencional**: o chamador é Stripe, não usuário; assinatura do webhook é a autenticação. Não aceitar HTTP sem assinatura válida. |
| `social-render-card` | JWT; se `user_id` veio no body, precisa casar com `sub`; kind/payload aceitos, texto limitado/escapado, Storage path com owner. | No máximo 10 jobs/dia por usuário; output SVG sanitizado e tamanho limitado. | JWT ligado (padrão). |
| `quiz-validate` | JWT; deriva usuário de `sub`, valida capítulo publicado, payload/answers e chave idempotente; não confia em user_id do cliente. | Rate limit atômico por user/chapter; uma tentativa por request id; XP só pela RPC protegida. | JWT ligado (padrão). |
| `generate-book-embeddings` | JWT mais papel `admin`; service-role restrito ao handler; processa só livros sem embedding. | Page size 1–20; output de dimensão 1536; atualiza condicionalmente só embeddings ainda nulos. | JWT ligado (padrão). |

## Helper e privilégios compartilhados

`supabase/functions/_shared/auth.ts` centraliza:

- extração do Bearer token e validação de identidade por `auth.getUser(token)`;
- cliente privilegiado com `SUPABASE_SERVICE_ROLE_KEY`, criado apenas server-side;
- consulta de papel Admin na tabela `profiles` pelo cliente de serviço;
- responses JSON/CORS compartilhadas e comparação de segredo em tempo constante.

O cliente privilegiado não é aceito como substituto para autorização: handlers checam token, ownership, papel ou autenticação de serviço antes de usá-lo. A lista de funções permanece vazia no remote; não houve alteração de secrets nem deploy na execução documentada.

## Overrides de `verify_jwt`

Em `supabase/config.toml`, **somente** `stripe-webhook` e `scheduled-reminders` têm `verify_jwt = false`. Ambos implementam autenticação alternativa no próprio handler (assinatura Stripe ou segredo de serviço em header); o `false` do gateway **não** é controle de autorização. As outras nove funções mantêm verificação JWT do gateway e verificam o usuário/papel novamente no código quando necessário. A workflow de deploy usa essa configuração local.

Não configure `verify_jwt=false` para funções client-facing. Se adicionar novo serviço, defina protocolo autenticado, limite de corpo e rate limit antes de criar exceção.

## Secrets exigidos pelo deploy

O runtime Edge Supabase fornece `SUPABASE_URL` e a service-role key de projeto. Confirme a chave pública/anon (`SUPABASE_ANON_KEY`, `SUPABASE_PUBLISHABLE_KEY` ou `SB_PUBLISHABLE_KEY`) para validação do token. Segredos externos utilizados pelos handlers:

- `OPENAI_API_KEY` — recomendações e embeddings;
- `RESEND_API_KEY`, `RESEND_FROM_EMAIL` — newsletter;
- `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` — SDK e assinatura do webhook;
- `SCHEDULED_REMINDERS_SECRET` — chamada serviço-a-serviço.

Os valores devem ser guardados por Secrets do Supabase/GitHub Actions, jamais no repositório. O workflow verifica apenas a presença dos nomes no Supabase, não valores, e não grava nem imprime esses valores. Não foi confirmado nesta tarefa se esses nomes já estão configurados no projeto; faltaram credenciais de provedores no escopo. O workflow interrompe antes do deploy se faltar qualquer pré-requisito.

## Testes e autorização antes de release

- **Executado:** Deno `check`, `lint`, `fmt:check` nas 11 funções; PGlite cobre RPCs de quiz, XP, votes, reminders, newsletter, Stripe e matching.
- **Executado:** check/lint/format do harness `scripts/integration-smoke/`.
- **Não executado:** invocar os handlers via `supabase functions serve`, Auth real, webhook Stripe em sandbox, Resend/OpenAI, armazenamento ou WebSocket em projeto isolado.
- **Não executado:** deploy; não há funções hospedadas para testar/monitorar.

Para testes ao vivo use projeto/branch descartável, `SUPABASE_TEST_PROJECT_REF` e secrets exclusivos de staging. O harness recusa o ref de produção. A branch foi recusada pelo usuário por custo recorrente de US$ 0,01344/h; por isso a execução é uma pendência, não um teste “bloqueado e aprovado”.

Antes de deploy:

1. passar CI/revisão e mergear a branch de código;
2. provisionar `SUPABASE_ACCESS_TOKEN` e `SUPABASE_PROJECT_REF` no GitHub;
3. proteger environment `production` com reviewers humanos;
4. configurar/validar secrets de runtime, sem ecoar valores;
5. testar endpoints com anon, user A, user B, admin, evento duplicado e payload inválido em staging;
6. inspecionar logs sem PII, status de respostas, retries e side effects; só então acionar `workflow_dispatch` digitando o project ref correto.

## Limitações funcionais que exigem decisão de produto

- `user_progress.status`/`percent` é autodeclarado; `award-xp` prova que a linha de progresso existe, mas não prova leitura física. Similarmente, uma RSVP `attending=true` comprova inscrição, não presença. Se XP precisa ser antifraude, defina um evento de confirmação confiável.
- A política de spoiler do feed/diário depende de progresso autodeclarado para UX; não usá-la como controle para conteúdo restrito/publicação antecipada.
- Atualizações front-end/consumidores não fazem parte deste repositório; RPCs como `award_xp` não devem ser chamadas diretamente pelo navegador.
- A divergência baseline `sdd_*`/`20260101…` segue bloqueando `supabase db push`; o deploy de functions não aplica migrations.
