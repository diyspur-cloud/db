# Relatório de testes — security-smoke

**Data:** 2026-10-09
**Projeto:** `/home/ubuntu/diyspur`
**Escopo:** correção do fixture/grants do harness `scripts/security-smoke/test.mjs` e execução local em PGlite.
**Fora do escopo:** migrations/SQL de produção, handlers Edge, OpenAPI, frontend, replay/reset remoto e operações remotas.

## Comando executado

```bash
npm test --prefix scripts/security-smoke
```

O comando executa:

```text
node test.mjs && node business-rules.mjs
```

## Resultado final

**PASS — exit code 0.** A execução final completou as duas suítes:

- `test.mjs`: `ALL SECURITY SMOKE ASSERTIONS PASSED`
- `business-rules.mjs`: `ALL BUSINESS-RULE TESTS PASSED`

As asserções efetivamente aprovadas na execução final cobrem:

- views anônimas: mascaramento de spoilers, posts privados e respostas corretas de quiz;
- negação de leitura direta de conteúdo/PII e RPC privado para anônimo;
- consentimento, onboarding próprio, negação de escalada de role e atualização cross-owner;
- tentativas de quiz fabricadas e mutação cross-owner de lista;
- associação/promocão indevida em clube privado/público;
- acesso de autor ao próprio post privado e autorização do owner para promover membro;
- `is_admin` falso/verdadeiro, policies de editorial picks e limites administrativos de Storage;
- Buddy Reads e listas: visibilidade, edição do owner, colaborador `can_edit` e tentativa de IDOR por troca de `list_id`;
- contadores de reactions/replies/feed e streak mantidos por triggers privados;
- bloqueio de mutação direta de streak pelo cliente;
- bônus diário de streak: cliente bloqueado, atividade do dia exigida, 25 XP, referência determinística, idempotência em retry e uma única linha no ledger;
- regras de negócio: aplicação da migration follow-up, RPCs privilegiadas invoker-only, XP idempotente/seasonal, metas, journal, quiz/rate limit, votos, reminders, newsletter, Stripe e matching.

## Falhas intermediárias reproduzidas e correções

As falhas abaixo foram reproduzidas em sequência; nenhuma foi mascarada e não houve enfraquecimento de asserções:

1. **`permission denied for table comments` no reply próprio.**
   - O fixture `public.comments` não tinha o `DEFAULT gen_random_uuid()` presente na definição de produção.
   - O teste fornecia explicitamente `id`, mas a migration concede INSERT somente nas colunas de conteúdo/ownership, sem `id`.
   - Correção somente no harness: adicionar o default ao fixture e inserir o reply sem `id`, usando `RETURNING id` para a exclusão posterior. O teste continua verificando INSERT próprio, trigger de replies e decremento após DELETE.

2. **`permission denied for table follows` ao consultar um post público.**
   - O fixture não concedia acesso a `public.follows`, embora a policy de feed contenha essa relação e a tabela permaneça necessária para a avaliação da policy.
   - Correção somente no harness: incluir `public.follows` no conjunto de grants de `anon`/`authenticated`.

3. **Falha de comparação de `DATE` em PGlite.**
   - O driver retornou o campo `date` como representação JavaScript não-canônica para `String(...)`.
   - Correção somente no harness: selecionar `last_activity_at::text` e manter a comparação com a data atual. A exigência de atividade no dia não foi removida.

4. **`permission denied for table xp_events` ao verificar o ledger como `service_role`.**
   - O fixture permitia executar o RPC server-only, mas não concedia ao papel de teste `service_role` o SELECT usado pela própria asserção de verificação.
   - Correção somente no harness: `GRANT SELECT ON public.xp_events TO service_role`.

## Cobertura adicional e duplicação evitada

- O caso positivo **non-cross-owner** já está exercitado pelo reply inserido pelo próprio usuário, pelas mutações próprias de reação/feed/progresso, pelo onboarding próprio, pelo checkpoint do owner e pelas ações autorizadas do owner. A correção do reply preservou essa cobertura; não foi criado um teste redundante.
- A cobertura do bônus diário já existe em `test.mjs`: chama `private.award_daily_streak_bonus` duas vezes, verifica `true`/retry, uma única entrada `streak_bonus`, `amount = 25` e `ref_id` derivado de `md5(user || current_date)`. A migration chama o `public.award_xp` real; a suíte `business-rules.mjs` também testa `public.award_xp` quanto à idempotência e ao rollover de temporada. Nenhum RPC ou teste duplicado foi adicionado.

## Arquivos alterados

- `scripts/security-smoke/test.mjs` — somente ajustes de fixture/grants e adaptação da leitura de `DATE` ao harness PGlite.
- `docs/execution/REPORT-tests.md` — este relatório solicitado.

Não foram alterados SQL de migrations, handlers, OpenAPI, frontend ou outros artefatos de produção. Não foi confirmado defeito de source: após as correções de paridade do fixture, a execução completa passou.
