# Relatório de correções backend

**Escopo:** `/home/ubuntu/diyspur` — somente os handlers de quiz/newsletter, a migration necessária da RPC de quiz e este relatório. Não foram alterados frontend, OpenAPI, harness de testes, bundles, Git remoto ou outras fontes.

## 1. Quiz: conflito de chave idempotente

Arquivos:

- `supabase/functions/quiz-validate/index.ts`
- `supabase/migrations/20261009032120_fix_quiz_idempotency_conflict.sql` (criada pelo `supabase migration new fix_quiz_idempotency_conflict`)

### Handler

`finishExisting` agora recebe `chapterId` e as respostas esperadas. Ao encontrar a mesma combinação usuário/chave, ele:

1. consulta também `chapter_id`;
2. consulta `quiz_answers` e converte ambos os lados para a identidade canônica `{question_id, chosen_idx}`;
3. ordena canonicamente por `question_id` e depois `chosen_idx`, portanto a ordem original do array não altera a comparação;
4. responde **HTTP 409 `{ "error": "idempotency_key_conflict" }`** se o capítulo ou as respostas diferirem;
5. responde **HTTP 503 `{ "error": "temporarily_unavailable" }`** se a leitura das respostas falhar;
6. só reaplica o XP idempotente quando capítulo e respostas coincidem.

Os dois callsites de corrida (incluindo o caminho rate-limited) foram atualizados para enviar capítulo e respostas. Se a corrida passar pelo RPC antes do pré-check, o handler também mapeia o conflito SQL `22023` para HTTP 409.

### RPC transacional

A migration substitui a implementação real de `public.record_quiz_attempt` mantendo exatamente a assinatura, o retorno, a função pública e os grants service-role-only existentes. A função agora:

- canonicaliza `question_id/chosen_idx` dentro da mesma transação;
- bloqueia uma tentativa existente com `FOR UPDATE`;
- repete a comparação depois do `ON CONFLICT DO NOTHING`, cobrindo a corrida entre requests;
- rejeita capítulo ou payload diferente com `ERRCODE '22023'`;
- preserva inserção de respostas, índice de idempotência e comportamento de duplicata.

A migration não foi aplicada ao remoto nesta sessão; deve ser aplicada pelo agente pai conforme solicitado.

## 2. Newsletter: cleanup após exceção

Arquivo: `supabase/functions/newsletter-dispatch/index.ts`.

O issue e a audience key reclamados são guardados fora do corpo principal do `try`. As variáveis só são preenchidas depois de `claim_newsletter_dispatch` retornar `true`. Assim, uma exceção posterior tenta, de forma best-effort, chamar:

```text
finish_newsletter_dispatch(p_issue, p_audience_key, p_success = false)
```

Falhas dessa tentativa são apenas registradas e não substituem o erro original. O tracking é limpo após uma finalização normal bem-sucedida. Isso evita chamar `finish false` para um request que não obteve o claim e não adiciona deleção insegura que poderia afetar um claim posteriormente recuperado por outro request.

### Limitação confirmada no SQL existente

A RPC atual é:

```sql
UPDATE private.newsletter_dispatch_runs
SET completed_at = CASE WHEN p_success THEN statement_timestamp() ELSE NULL END
WHERE issue_id = p_issue AND audience_key = p_audience_key;
```

Para `p_success = false`, ela **não apaga nem retrocede `started_at`**. Portanto, o cleanup agora é tentado, mas não libera imediatamente um lease ainda dentro das 24 horas; ele apenas mantém `completed_at` nulo. Não alterei essa RPC sem um token de ownership: transformar cegamente o `false` em `DELETE` poderia liberar o claim de outro request que recuperasse a mesma chave após a expiração. Um follow-up seguro precisa de um claim token/started-at retornado atomicamente e usado na finalização.

## Verificações executadas

Todas passaram:

- `deno fmt quiz-validate/index.ts newsletter-dispatch/index.ts`
- `deno task check`
- `deno task lint`
- `deno task fmt:check`
- teste simples `deno eval` da canonicalização (arrays reordenados iguais; resposta alterada diferente);
- verificação estática dos contratos essenciais da migration, callsites, erro 503, `22023` e grants.

O banco local não pôde ser inicializado (`supabase status`: Docker/Podman indisponível), portanto a migration SQL não foi executada contra uma instância local/remota. Nenhuma aplicação remota foi feita.
