# Smoke de integração Auth / Storage / Realtime

`test.ts` executa testes que **criam e apagam dados temporários**; não é incluído no CI sem credenciais e não deve ser apontado à produção. O harness é bloqueado se o URL referir o projeto de produção atual (`xjhehhfhhoomblcggjpk`), se o project ref declarado não casar ou se `SUPABASE_TEST_ALLOW_MUTATIONS=true` não estiver explicitamente definido.

## Pré-requisitos

- Projeto Supabase descartável/staging contendo as migrations da aplicação, o bucket privado `feed-media`, o catálogo de ao menos um livro e `reading_journal_entries` publicado em `supabase_realtime`.
- Publishable key e service-role key do **projeto de teste** fornecidas apenas no ambiente local/CI protegido. Nunca grave essas chaves em arquivo, shell history, issue ou Git.
- Node não é necessário; usar Deno 2.

## Execução

```bash
export SUPABASE_URL='https://<test-project-ref>.supabase.co'
export SUPABASE_TEST_PROJECT_REF='<test-project-ref>'
export SUPABASE_PUBLISHABLE_KEY='<publishable-key-de-staging>'
export SUPABASE_SERVICE_ROLE_KEY='<service-role-key-de-staging>'
export SUPABASE_TEST_ALLOW_MUTATIONS=true

deno task --config scripts/integration-smoke/deno.json check
deno task --config scripts/integration-smoke/deno.json lint
deno task --config scripts/integration-smoke/deno.json fmt:check
deno task --config scripts/integration-smoke/deno.json test
```

O teste cria dois usuários confirmados via Admin API, autentica/renova sessões, confirma isolamento de PII e consentimento, grava e remove um objeto em `feed-media`, tenta acessos anônimos/cruzados e publica uma entrada privada temporária para verificar a entrega Realtime somente ao titular. O `finally` tenta excluir objeto, entrada, sessões e contas, inclusive em caso de asserção falhar. Revise o projeto antes de habilitar a flag; remova qualquer resíduo manualmente se uma falha de rede impedir cleanup.

**Execução nesta tarefa:** check estático pode ser feito localmente, mas o teste mutante foi intencionalmente não executado. Não foi autorizada a criação de branch (custo recorrente informado de US$ 0,01344/h) e o único projeto ligado é produção; não foi seguro criar contas nem upload no banco de produção.
