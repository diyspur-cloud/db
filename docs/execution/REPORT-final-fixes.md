# Relatório final — correções backend confirmadas

**Data:** 2026-10-09
**Escopo:** somente backend Supabase/Postgres/Edge Functions em `/home/ubuntu/diyspur`.
**Não executado:** aplicação remota, deploy, reset remoto, Git/commit/push, frontend, OpenAPI, quiz, Stripe e `scripts/security-smoke`.

## Arquivos completos entregues

As alterações estão completas nos arquivos abaixo; não foram editadas migrations históricas:

- `supabase/functions/social-render-card/index.ts`
- `supabase/functions/ai-user-embeddings/index.ts`
- `supabase/functions/newsletter-dispatch/index.ts`
- `supabase/migrations/20261009034508_fix_atomic_rate_limits_and_club_season.sql`
- `supabase/migrations/20261009034511_fix_newsletter_claim_ownership.sql`
- este relatório: `docs/execution/REPORT-final-fixes.md`

As duas migrations foram criadas pela CLI exigida:

```text
/home/ubuntu/bin/supabase migration new fix_atomic_rate_limits_and_club_season
/home/ubuntu/bin/supabase migration new fix_newsletter_claim_ownership
```

CLI utilizada: `supabase 2.120.0`.

## 1. Rate limits atômicos

A auditoria confirmou duas corridas read-before-write:

- cards sociais: contagem dos jobs nas últimas 24 horas seguida de insert;
- embeddings do usuário: leitura de `updated_at`, chamada OpenAI e upsert posterior.

No histórico local conferido não havia uma função `take_rate_limit`; por isso a primeira migration acima cria a implementação atômica e os handlers passam a usá-la. A operação é um `INSERT ... ON CONFLICT ... DO UPDATE` na chave `(user_id, bucket)`, que serializa concorrentes no mesmo bucket.

### Contrato aplicado

| Handler | Bucket | Limite | Janela | Resposta acima do limite |
|---|---|---:|---:|---|
| `social-render-card` | `social-render-card` | 10 | janela de 24h iniciada na primeira tentativa | `429 daily_limit_reached` |
| `ai-user-embeddings` | `ai-user-embeddings` | 1 | 3600s | `429 rate_limited`, `retry_after_seconds: 3600` |

A RPC é `SECURITY INVOKER`, com `search_path = ''`, tabela em `private` e `EXECUTE` concedido somente a `service_role`. O handler continua validando o Bearer via `requestUser` e usa sempre `user.id` validado como chave. Não foi introduzido bypass para admin nem foi permitido que `user_id` do corpo escolha a identidade; portanto o comportamento administrativo existente (admin opera como sua própria identidade nestes endpoints) foi preservado.

O limite é consumido no ponto em que o código antigo fazia a contagem. Assim, uma tentativa concorrente é contabilizada antes do insert/OpenAI; falhas posteriores não liberam artificialmente a janela.

## 2. Agregados do painel de clubes

`20261009034508_fix_atomic_rate_limits_and_club_season.sql` substitui apenas o helper privado e a view existente:

- `private.club_progress_counts` agora filtra `s.id = uc.current_season_id` quando `current_season_id` não é nulo;
- a mesma condição já usada pelo painel legado permanece na contagem de `distinct_readers`;
- os aliases `chapters_read`, `chapters_in_progress`, `finished_count`, `reading_count` e `not_started_count` continuam na view, com `cs.title` agrupado como `current_season_title`;
- a view continua `security_invoker`; o helper continua privado, sem retornar IDs ou linhas individuais de progresso;
- quando `current_season_id` é nulo, a semântica histórica de agregar todas as temporadas do livro é mantida;
- não foi criada `public.clubs`, nem qualquer nova entidade de clube.

## 3. Newsletter: `false` podia desfazer sucesso?

**Sim, confirmado.** A função anterior executava:

```sql
completed_at = case when p_success then statement_timestamp() else null end
```

sem token de ownership. Portanto um `finish_newsletter_dispatch(..., false)` atrasado podia limpar `completed_at` de um claim já concluído; também não distinguia um claim recuperado após 24 horas.

### Correção

`20261009034511_fix_newsletter_claim_ownership.sql` é aditiva e preserva o histórico:

1. adiciona `claim_token uuid` a `private.newsletter_dispatch_runs` e preenche claims antigos;
2. cria `claim_newsletter_dispatch_token(issue, audience_key)`, que gera token novo no insert e também ao recuperar lease expirado;
3. mantém `claim_newsletter_dispatch(issue, audience_key) returns boolean` como wrapper compatível para callers antigos;
4. mantém a assinatura histórica `finish_newsletter_dispatch(issue, audience_key, success)`, mas `false` não altera nada; `true` só completa um claim ainda aberto;
5. cria a RPC distinta `finish_newsletter_dispatch_owned(issue, audience_key, success, claim_token)` para o handler atual:
   - `true` só marca o claim cujo token coincide;
   - `false` remove somente o claim aberto cujo token coincide, liberando retry imediato;
   - token antigo não pode remover nem finalizar um claim recuperado por outra execução;
6. o handler `newsletter-dispatch` usa o token retornado no sucesso e no cleanup do `catch`.

Foi usada uma RPC com nome distinto para a versão com token. Isso evita overload de funções, que não é suportado de forma segura pelo endpoint RPC/PostgREST. O claim continua restrito a `service_role`.

A semântica de audiência não foi alterada: o handler continua despachando todos os confirmados não cancelados, conforme a decisão registrada no relatório anterior.

## Verificações executadas

### Deno — passou

Com o conjunto completo de Edge Functions:

```text
/home/ubuntu/bin/deno fmt supabase/functions/newsletter-dispatch/index.ts
/home/ubuntu/bin/deno task --config supabase/functions/deno.json check
/home/ubuntu/bin/deno task --config supabase/functions/deno.json lint
/home/ubuntu/bin/deno task --config supabase/functions/deno.json fmt:check
```

Resultado: `check`, `lint` e `fmt:check` passaram; `deno check` verificou as 11 fontes listadas no task e `deno lint`/formatação verificaram os 13 arquivos configurados. Também foi feita verificação estática dos buckets, ausência do count antigo, ausência da janela baseada em `updated_at`, grants service-only, filtro de temporada, token de claim e RPC owned.

### SQL/concorrência — passou no harness isolado

Harness temporário executado:

```text
/home/ubuntu/jobs/job_y5Pm43f3/test-final-fixes.mjs
```

Resultado:

```text
PASS: final-fixes PGlite migration and concurrency assertions
```

Asserções realizadas:

- primeira tomada de limite permitida e segunda tomada do mesmo bucket rejeitada;
- painel de clube com duas temporadas conta somente a `current_season_id` e mantém aliases coerentes;
- `public.clubs` continua inexistente;
- segundo claim newsletter ativo é rejeitado;
- owner finaliza com sucesso;
- `false` legado não apaga claim já concluído;
- claim expirado recebe token novo;
- token antigo não apaga o claim recuperado;
- falha com token correto libera somente o próprio claim.

O harness usa PGlite em memória. Como a distribuição PGlite disponível não contém `pgcrypto`, somente no texto carregado pelo harness `gen_random_uuid()` foi substituído por um gerador UUID de teste totalmente qualificado; as migrations versionadas não foram alteradas para isso. A semântica SQL foi exercitada, mas isso **não substitui** PostgreSQL/Supabase real nem um teste de carga com várias sessões.

## Limitações honestas

- Não há Docker/Podman/Postgres local disponível nesta sessão; não foi afirmado replay completo das migrations.
- Nenhum banco remoto foi consultado ou alterado e nenhum handler foi deployado.
- Não foram usados secrets reais; portanto não houve chamada OpenAI, envio Resend ou POST autenticado hospedado.
- A concorrência SQL foi validada por cenário de recuperação/ownership no harness e pela chave única do UPSERT, mas não por teste de carga multi-sessão.
- A migration `take_rate_limit` precisa ser aplicada antes de publicar os dois handlers. Se um ambiente remoto tiver uma função homônima com assinatura incompatível, a assinatura esperada desta entrega é `(uuid, text, integer, integer)` com parâmetros `p_user`, `p_bucket`, `p_limit` e `p_window_seconds`.

## Aplicação e fechamento pelo responsável principal

As duas migrations foram aplicadas e confirmadas no projeto remoto, versões `20261009035042` e `20261009035049`; total remoto 50 migrations. Os três handlers afetados foram republicados ACTIVE. Catálogo confirma anon sem EXECUTE de rate limit, authenticated sem EXECUTE da finalização owned e service_role com rate limit. O harness foi adaptado a caminhos relativos como `scripts/security-smoke/final-fixes.mjs` e incluído no `npm test`; as três suítes passaram. A implementação usa janela fixa desde a primeira tentativa, não sliding window exata. Nenhum envio Resend/inferência OpenAI foi realizado.
