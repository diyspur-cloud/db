# AGENTS.md — Instruções para Agentes e IAs no Repositório Backend

Estas instruções valem para qualquer agente autônomo ou assistente de IA que opere no repositório `diyspur-cloud/db`.
**Objetivo principal**: Garantir a integridade do banco de dados relacional, inviolabilidade das regras de autorização RLS, imutabilidade do histórico de migrations e compatibilidade perfeita com o frontend `diyspur-cloud/app`.

---

## 1. Princípios de Ação e Limites de Escopo

1. **A Menor Alteração Correta**:
   - Modifique estritamente o arquivo de migration, script ou documentação necessário para atender ao pedido.
   - Não refatore tabelas existentes, não reescreva migrations históricas e não faça formatação ampla de arquivos SQL não solicitados.
2. **Imutabilidade do Histórico**:
   - **NUNCA modifique ou apague migrations já commitadas em `supabase/migrations/`**.
   - Toda correção de bug, alteração de constraint, adição de coluna ou ajuste de policy DEVE ser criada em um novo arquivo com timestamp no formato `YYYYMMDDHHMMSS_descricao.sql`.
3. **Ambiente de Produção é Sagrado**:
   - NUNCA execute `supabase db reset --linked` ou qualquer comando destrutivo contra o projeto remoto em produção (`xjhehhfhhoomblcggjpk`).
   - Todos os testes de replay devem ser realizados localmente ou em banco de staging isolado.

---

## 2. Invariantes de Segurança e RLS

1. **Autoridade Server-Side**:
   - O cliente HTTP/PostgREST não tem autoridade para definir `user_id`, `role`, `status`, `xp` ou aprovar quizzes.
   - Toda policy RLS deve usar `auth.uid()` ou predicados de autorização encapsulados em funções do schema `private`.
2. **Hardening de Funções `SECURITY DEFINER`**:
   - Toda função criada com `SECURITY DEFINER` DEVE incluir `SET search_path = ''` para eliminar riscos de sequestro de caminho de busca.
   - Funções públicas devem ser wrappers finos com grants explícitos para as roles autorizadas (`authenticated`, `service_role`).
3. **Zero Secrets em Repositório**:
   - Não commite arquivos `.env`, chaves de API secretas, tokens de serviço do Supabase (`service_role key`), senhas ou dumps com dados reais.

---

## 3. Compatibilidade e Sincronização com o Frontend

- O frontend consome tipos gerados em `app/src/types/database.ts`.
- Se você adicionar, renomear ou remover colunas, views ou RPCs:
  1. Certifique-se de que a alteração seja retrocompatível com a versão ativa do frontend.
  2. Sincronize o arquivo de tipos em `app/src/types/database.ts` ou forneça as definições TypeScript correspondentes.
  3. Verifique se as queries em `app/src/features/*` continuam válidas executando `npm run typecheck` e `npm test` no repositório `app`.

---

## 4. Checklist Obrigatório para Agentes

Antes de concluir qualquer tarefa ou propor um commit no repositório `db`:
- [ ] A migration segue o padrão de nomenclatura `YYYYMMDDHHMMSS_*.sql`?
- [ ] Novas tabelas possuem `ENABLE ROW LEVEL SECURITY` e policies para `SELECT`, `INSERT`, `UPDATE` e `DELETE`?
- [ ] Novas foreign keys contam com índices cobridores criados explicitamente?
- [ ] As funções `SECURITY DEFINER` utilizam `SET search_path = ''`?
- [ ] O script de replay local ou os scripts de validação (`npm test`, `sdd_contract.test.sql`) passam sem erros?
- [ ] Resíduos de dados de homologação foram inspecionados via `scripts/ops/inspect-qa-residual.sql`?
- [ ] A mensagem de commit segue o padrão **Conventional Commits** (`feat:`, `fix:`, `docs:`, `chore:`)?

---

## 5. Referência de Deploy

Consulte o plano de implantação em produção em [`../docs/deploy/README.md`](../docs/deploy/README.md). As migrations devem ser executadas no Supabase Dashboard (SQL Editor) ou via Supabase CLI autenticado.
