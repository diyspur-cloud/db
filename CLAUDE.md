# CLAUDE.md — DIYSPUR backend Supabase

Guia de implementação, arquitetura, segurança e convenções de banco de dados para o repositório `diyspur-cloud/db`. Antes de propor qualquer alteração, consulte as migrations existentes e os contratos em produção; em caso de divergência, os schemas versionados e as policies em produção prevalecem sobre esta documentação.

---

## 1. Visão Geral da Arquitetura

O backend do DIYSPUR é hospedado sobre a infraestrutura gerenciada do **Supabase (PostgreSQL 15)**, complementado por **Edge Functions em Deno** e extensões do ecossistema Supabase:

- **Projeto Supabase**: `xjhehhfhhoomblcggjpk`
- **Schemas PostgreSQL**:
  - `public`: tabelas relacionais, views públicas (`v_comments_visible`, etc.) e RPCs consumidas pela Data API / PostgREST.
  - `private`: funções auxiliares internas `SECURITY DEFINER`, predicados de autorização e procedimentos críticos com `SET search_path = ''`.
  - `auth`: gerenciado internamente pelo Supabase Auth (JWT, identidades, sessões).
  - `storage`: buckets gerenciados (`covers`, `avatars`, etc.) com policies RLS dedicadas.
- **Frontend Consumidor**: `diyspur-cloud/app` (Next.js 16 App Router com SSR).
- **Contrato Tipado**: `app/src/types/database.ts` é gerado via `supabase gen types typescript`.

---

## 2. Princípios de Segurança & RLS (Invariantes)

1. **Zero Trust no Cliente**:
   - Nunca confie em `user_id`, `role`, `is_admin`, `score` ou status passados pelo payload do cliente.
   - Toda identidade é derivada exclusivamente de `auth.uid()` ou claims validadas pelo JWT.
2. **Row Level Security (RLS) Obrigatório**:
   - Toda tabela contendo dados de usuários, conteúdo privado ou escopo de clubes DEVE ter RLS ativado (`ALTER TABLE ... ENABLE ROW LEVEL SECURITY;`).
   - Policies de escrita (`INSERT`, `UPDATE`, `DELETE`) devem possuir cláusulas `WITH CHECK` correspondentes.
3. **Prevenção de Recursão de Policies**:
   - Nunca crie uma policy que consulte a própria tabela sem isolamento através de funções auxiliares `private` ou predicados otimizados com `(SELECT auth.uid())`.
4. **Funções e Escopo de Execução**:
   - Funções públicas de API são preferencialmente wrappers `SECURITY INVOKER` ou funções `SECURITY DEFINER` com validação rígida de `auth.uid()`.
   - Todas as funções `SECURITY DEFINER` DEVEM declarar explicitamente `SET search_path = ''` para prevenir ataques de hijack de search path.
   - Permissões são concedidas de forma restritiva (`REVOKE ALL ON FUNCTION ... FROM PUBLIC, anon; GRANT EXECUTE ... TO authenticated, service_role;`).
5. **Segredos e Credenciais**:
   - NUNCA versione chaves `service_role`, senhas de banco ou chaves de webhook no repositório.
   - Seeds (`seed.sql`, `seed_complement.sql`) e migrations devem conter apenas dados fictícios de teste ou dados públicos editoriais.

---

## 3. Estrutura do Repositório

```text
supabase/
├── config.toml             # Configuração local do Supabase CLI
├── migrations/             # Migrations DDL imutáveis (timestamps YYYYMMDDHHMMSS_nome.sql)
├── functions/              # Edge Functions Deno (_shared, quiz-validate, award-xp, etc.)
├── seed.sql                # Seed principal ordenado de dados estruturais
├── seed_complement.sql     # Conteúdo complementar editorial (livros, temporadas, quizzes)
├── security-audit.sql      # Scripts de auditoria de segurança e verificação de RLS
└── tests/                  # Testes SQL e validações de contrato (pgTAP / custom)

docs/
├── openapi.yaml            # Especificação OpenAPI dos endpoints e RPCs
├── supabase-reference.md   # Referência de tabelas e relacionamentos
├── deployment-status.md    # Histórico de deploys remotos
└── execution/              # Registros de auditorias e verificações

scripts/
├── replay-local.sh         # Script para reprodução local determinística do banco
├── replay-local.mjs        # Executor Node.js com checagens de integridade
└── deploy-edge-functions.sh # Script de publicação das Edge Functions
```

---

## 4. Convenções de Migrations SQL

1. **Imutabilidade Absoluta**:
   - Migrations já aplicadas e versionadas no histórico NUNCA devem ser editadas, renomeadas ou apagadas.
   - Qualquer ajuste, correção de bug ou evolução de schema DEVE ser uma nova migration incremental com timestamp atual (`YYYYMMDDHHMMSS_descricao.sql`).
2. **Idempotência e Segurança**:
   - Utilize `IF NOT EXISTS` e `IF EXISTS` para criação e alteração de tabelas, índices e colunas.
   - Para functions e views, utilize `CREATE OR REPLACE`.
   - Adicione índices cobridores para todas as foreign keys criadas.
3. **Nomenclatura**:
   - Tabelas, colunas, views e enums: `snake_case` no plural para tabelas (`reading_lists`, `user_clubs`).
   - Índices: `<tabela>_<colunas>_idx` ou `<tabela>_<coluna>_unique`.
   - Triggers: `trg_<tabela>_<acao>`.

---

## 5. Principais RPCs e Contratos com o Frontend

- `public.add_to_up_next_atomic(p_book uuid)`: Inserção atômica e serializada na fila de leitura do usuário autenticado (`auth.uid()`), com lock transacional consultivo, alocação de posições 1..5, retorno idempotente se o livro já estiver na fila e erro `queue_full`.
- `public.create_editorial_book(p_title, p_slug, p_author, p_synopsis, p_cover, p_pages)`: Procedimento `SECURITY DEFINER` para cadastro editorial de livros com validação estrita de `public.is_admin()`, sanitização e auditoria transacional em `editorial_audit_log`.
- `private.can_view_chapter(p_chapter_id uuid, p_user uuid)`: Determina se um capítulo está liberado para leitura baseado no status da temporada e no quiz do capítulo anterior.
- `public.get_season_chapter_access(p_season_id uuid)`: Retorna a lista de capítulos de uma temporada com seus respectivos estados de bloqueio (`locked`, `unlocked`, `completed`).
- `private.milestone_is_complete(p_user uuid, p_milestone uuid)`: Avalia o progresso do leitor contra as metas do milestone (capítulos lidos, páginas ou porcentagem).
- `public.get_user_milestone_status(p_user uuid, p_season_id uuid)`: Consulta atômica do status de todos os milestones de uma temporada para o usuário autenticado.
- `private.add_book_to_reading_list(p_list_id uuid, p_book_id uuid)`: Insere livro em lista privada validando ownership e atualizando contadores de forma atômica.
- `private.reorder_reading_list(p_list_id uuid, p_item_ids uuid[])`: Reordena itens de lista em uma única transação atômica.

---

## 6. Fluxo de Trabalho e Comandos

### 6.1 Desenvolvimento Local via Supabase CLI

```bash
# Iniciar o ambiente local Supabase
supabase start

# Verificar status das migrations
supabase migration list

# Criar nova migration incremental
supabase migration new minha_nova_funcionalidade

# Aplicar migrations pendentes localmente
supabase db reset

# Testar seeds e integridade
psql -h localhost -p 54322 -U postgres -d postgres -f supabase/seed.sql
psql -h localhost -p 54322 -U postgres -d postgres -f supabase/seed_complement.sql
```

### 6.2 Sincronização com o Frontend (`diyspur-cloud/app`)

Após aplicar alterações remotas ou consolidar uma nova migration:
```bash
# Gerar os tipos TypeScript sincronizados para o app
supabase gen types typescript --project-id "$SUPABASE_PROJECT_REF" > ../app/src/types/database.ts

# No app, validar se os tipos não quebraram queries
cd ../app && npm run typecheck && npm test
```

### 6.3 Deploy Controlado no Supabase Remoto

```bash
export SUPABASE_PROJECT_REF=xjhehhfhhoomblcggjpk
supabase link --project-ref "$SUPABASE_PROJECT_REF"
supabase migration list --project-ref "$SUPABASE_PROJECT_REF"
supabase db push --project-ref "$SUPABASE_PROJECT_REF"
```

---

## 7. Critérios de Aceite para Commits

- [ ] Todas as novas tabelas possuem `ENABLE ROW LEVEL SECURITY`.
- [ ] Todas as novas foreign keys possuem índices cobridores correspondentes.
- [ ] Novas funções `SECURITY DEFINER` possuem `SET search_path = ''`.
- [ ] Zero secrets ou senhas em arquivos de migration ou seed.
- [ ] As mensagens de commit seguem o padrão **Conventional Commits** (`feat:`, `fix:`, `docs:`, `chore:`).
