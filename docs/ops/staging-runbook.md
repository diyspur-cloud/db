# Runbook Operacional de Staging e Higiene de Dados — DIYSPUR

**Data:** 11 de outubro de 2026  
**Repositório:** `diyspur-cloud/db` (branch `docs/audit-data-hygiene-2026-10`)

---

## 1. Princípios Operacionais e Limites de Acesso

1. **Nunca executar mutations arbitrárias contra produção**: Testes de escrita, criação de contas temporárias, RSVPs de teste e seeds devem ser direcionados exclusivamente a instâncias de desenvolvimento local ou projeto de staging.
2. **Reversibilidade**: Nenhuma migration deve conter comandos destrutivos sem plano de contingência e backup verificado.
3. **Auditoria de Operações**: Todas as execuções manuais devem ser registradas em commit ou log operacional contendo autor, data, hash da migração ou UUID do registro afetado, sem inclusão de PII ou segredos.

---

## 2. Procedimento Operacional: Arquivamento da Fixture `QA RETESTE 20261010`

### 2.1 Passo 1 — Inspeção Read-Only Prévia
Executar com conexão read-only autorizada apontada para o ambiente onde o registro foi identificado:
```sql
-- scripts/ops/inspect-qa-residual.sql
SELECT
  id,
  name,
  owner_id,
  created_at,
  archived_at,
  is_private
FROM public.user_clubs
WHERE name = 'QA RETESTE 20261010'
ORDER BY created_at DESC
LIMIT 10;
```
**Critérios de Verificação Obrigatórios:**
- Confirmar que o UUID retornado corresponde a uma fixture de teste criada por conta de QA interna.
- Verificar se o registro não possui membros reais ou atividades comunitárias legítimas vinculadas.

### 2.2 Passo 2 — Transação de Arquivamento Controlado
Executar manualmente após confirmação formal do operador:
```sql
BEGIN;

-- Trava a linha para atualização com verificação rigorosa
SELECT id, name, owner_id, created_at, archived_at
FROM public.user_clubs
WHERE id = '<UUID_CONFIRMADO>'
  AND name = 'QA RETESTE 20261010'
FOR UPDATE;

-- Aplica o arquivamento lógico preservando integridade referencial
UPDATE public.user_clubs
SET archived_at = now()
WHERE id = '<UUID_CONFIRMADO>'
  AND name = 'QA RETESTE 20261010'
  AND archived_at IS NULL;

-- Verifica o novo estado arquivado
SELECT id, name, owner_id, archived_at
FROM public.user_clubs
WHERE id = '<UUID_CONFIRMADO>';

COMMIT;
```

---

## 3. Protocolo de Testes de RLS Multiusuário em Staging

Ao validar novas migrations em staging:
1. Executar a suíte de segurança em memória PGlite:
   ```bash
   npm test --prefix scripts/security-smoke
   ```
2. Validar que:
   - `anon` não consegue ler PII de perfis nem corpos de comentários bloqueados;
   - `user_a` não pode editar notas de diário ou listas de `user_b`;
   - Leitores comuns não podem promover seus próprios papéis ou publicar capítulos.
