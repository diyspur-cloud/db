# Plano de Deploy em Produção — Supabase & Vercel

> **AVISO OBRIGATÓRIO: ESTE PLANO REQUER INTERAÇÃO NO NAVEGADOR WEB**
>
> Várias etapas deste deploy **não podem ser concluídas exclusivamente pelo terminal ou por scripts autônomos sem intervenção humana**. Elas exigem autenticação interativa com login social/MFA, aprovação de permissões no GitHub, visualização segura de credenciais criptografadas no dashboard do Supabase e configuração manual de variáveis de ambiente e domínios no dashboard da Vercel.
>
> Mantenha um navegador web aberto com as sessões autenticadas no [Supabase Dashboard](https://supabase.com/dashboard) e na [Vercel](https://vercel.com/dashboard).

---

## 1. Visão Geral da Arquitetura de Produção

```text
                                 [ LEITOR / NAVEGADOR ]
                                           │
                                           │ HTTPS (diyspur.vercel.app ou domínio próprio)
                                           ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                 VERCEL (Frontend Edge)                                 │
│                                                                                        │
│  Next.js 16 App Router · React 19 · SSR Server Components · Static Generation · CSS    │
│  Variáveis: NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, etc.       │
└──────────────────────────────────────────┬─────────────────────────────────────────────┘
                                           │
                                           │ PostgREST / Auth / Storage (HTTPS)
                                           ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              SUPABASE (Backend Gerenciado)                             │
│                                                                                        │
│  PostgreSQL 15 (85 migrations DDL) · Row Level Security (RLS) · Supabase Auth          │
│  RPCs Atômicas: add_to_up_next_atomic, create_editorial_book, etc.                      │
│  Edge Functions Deno · Storage Buckets (covers, avatars)                               │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Pré-requisitos & Checklist Inicial

Antes de iniciar o processo de deploy:

- [ ] **Acesso ao Navegador**: Sessão ativa no [Supabase](https://supabase.com/dashboard) e [Vercel](https://vercel.com/dashboard).
- [ ] **Acesso ao Repositório Git**: Permissões de escrita nos repositórios do projeto (GitHub).
- [ ] **Ambiente Local**: Node.js 20+ ou 22+, npm 10+, Supabase CLI (opcional para terminal, mas recomendável).
- [ ] **Testes Locais Verificados**:
  - `npm run typecheck` executado sem erros no `app`.
  - `npm run lint` executado sem erros ou advertências no `app`.
  - `npm test` executado com todos os 26 arquivos de teste passando (94 testes).
- [ ] **Migrations Prontas**: As 85 migrations em `db/supabase/migrations/` estão completas e validadas.

---

## 3. Etapa 1: Deploy & Configuração no Supabase (Navegador)

### 3.1. Acessar o Projeto no Supabase Dashboard
1. Abra o navegador e navegue até: `https://supabase.com/dashboard/project/xjhehhfhhoomblcggjpk` (ou selecione seu projeto de produção na lista de organizações).
2. Se estiver criando um novo ambiente do zero:
   - Clique em **"New Project"**.
   - Defina o nome do projeto (ex.: `diyspur-production`).
   - Gere e salve com segurança a senha do banco de dados (Database Password).
   - Selecione a região mais próxima ao público brasileiro (ex.: `sa-east-1` São Paulo).

### 3.2. Copiar as Chaves de API (Segurança)
1. No menu lateral esquerdo, clique no ícone de engrenagem **"Project Settings"** > **"API"**.
2. Copie os seguintes valores para um gerenciador seguro de senhas:
   - **Project URL**: `https://<project-ref>.supabase.co`
   - **anon / public key (Publishable Key)**: `eyJhbGciOi...`
   - **service_role key (Secret Key)**: `eyJhbGciOi...` *(NUNCA compartilhar ou colocar no código client-side!)*
   - **JWT Secret**: Usado para validação server-side de tokens.

### 3.3. Execução das Novas Migrations (SQL Editor)
Caso não esteja utilizando o `supabase db push` autenticado via CLI:
1. No menu lateral, acerte no ícone **"SQL Editor"**.
2. Clique em **"New query"**.
3. Aplique as migrations mais recentes de remediação da auditoria:
   - **Migration 1 (`add_to_up_next_atomic`):** Copie o conteúdo de `db/supabase/migrations/20261012160000_add_to_up_next_atomic.sql` e execute clicando em **Run** (Ctrl+Enter). Verifique a mensagem `Success. No rows returned`.
   - **Migration 2 (`create_editorial_book`):** Copie o conteúdo de `db/supabase/migrations/20261012161000_create_editorial_book.sql` e execute clicando em **Run**. Verifique a mensagem `Success. No rows returned`.
4. *Validação Rápida*: No menu lateral, acerte em **"Database"** > **"Functions"** e confirme a presença de `add_to_up_next_atomic` e `create_editorial_book`.

### 3.4. Configuração de Autenticação (Auth & Redirects)
1. No menu lateral, clique em **"Authentication"** > **"URL Configuration"**.
2. No campo **Site URL**, preencha a URL canônica de produção:
   - `https://diyspur.vercel.app` (ou seu domínio customizado `https://diyspur.com`).
3. No campo **Redirect URLs**, clique em **"Add URL"** e cadastre:
   - `https://diyspur.vercel.app/**`
   - `https://diyspur.vercel.app/auth/callback`
   - `http://localhost:3000/**` *(para testes locais do time de desenvolvimento)*
4. Clique em **Save**.

### 3.5. Configuração de Storage (Buckets de Mídia)
1. No menu lateral, clique em **"Storage"**.
2. Confirme a existência dos buckets:
   - `covers` (Público, para capas de livros).
   - `avatars` (Público, para avatares de perfis).
   - `feed-media` (Privado, com acesso controlado via URLs assinadas e RLS).
3. Caso algum bucket não exista, crie-o pelo botão **"New bucket"** respeitando a privacidade indicada.

---

## 4. Etapa 2: Deploy do Frontend na Vercel (Navegador)

### 4.1. Conectar o Repositório no Vercel Dashboard
1. Abra o navegador e navegue até [Vercel Dashboard](https://vercel.com/dashboard).
2. Se o projeto já estiver importado:
   - Selecione o projeto `diyspur` (ou `diyspur-app`).
3. Se for uma primeira configuração:
   - Clique em **"Add New..."** > **"Project"**.
   - Conecte a conta do GitHub / GitLab e localize o repositório `diyspur-cloud/app` (ou o monorepo `diyspur`).
   - Se for o monorepo, configure **Root Directory** como `app`.
   - Verifique o **Framework Preset**: Deve detectar automaticamente `Next.js`.
   - **Build Command**: `next build` (padrão).
   - **Output Directory**: `.next` (padrão).
   - **Install Command**: `npm ci` (recomendado).

### 4.2. Configurar Variáveis de Ambiente na Vercel
1. Dentro do projeto na Vercel, acesse a aba **"Settings"** > **"Environment Variables"**.
2. Adicione as seguintes variáveis com escopo **Production**, **Preview** e **Development**:

| Nome da Variável | Valor Exemplo / Origem | Obrigatória? |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | `https://xjhehhfhhoomblcggjpk.supabase.co` | **Sim** |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | `eyJhbGciOi...` (Chave `anon` do Supabase) | **Sim** |
| `NEXT_PUBLIC_SITE_URL` | `https://diyspur.vercel.app` (Canônica sem barra final) | **Sim (pré-build)** |
| `NEXT_PUBLIC_POSTHOG_KEY` | Chave de projeto do PostHog | Opcional |
| `NEXT_PUBLIC_POSTHOG_HOST` | `https://us.i.posthog.com` ou proxy | Opcional |
| `NEXT_PUBLIC_SENTRY_DSN` | DSN do projeto Sentry | Opcional |
| `SENTRY_AUTH_TOKEN` | Token para upload de source maps no build | Opcional |

> **IMPORTANTE**: A variável `NEXT_PUBLIC_SITE_URL` DEVE ser definida **antes do build**, pois o Next.js utiliza essa URL para compilar o `metadataBase` estático e o arquivo `robots.txt`.

### 4.3. Disparar Build e Deploy
1. Acesse a aba **"Deployments"**.
2. Clique nos três pontinhos no canto superior direito do último deployment ou envie um novo push na branch `main`:
   - No terminal: `git push origin main`
   - Ou no dashboard da Vercel: **"Redeploy"** marcando **"Use existing Build Cache: false"** para garantir compilação limpa.
3. Acompanhe a esteira de build nos logs em tempo real:
   - Verifique a execução de `next build`.
   - Confirme a geração estática de rotas (`/`, `/livros`, `/comunidade`, etc.).
   - Certifique-se de que o deployment finalize com status **"Ready"**.

---

## 5. Etapa 3: Verificação Pós-Deploy e Smoke Tests (Navegador)

Após o status **Ready** na Vercel, realize a seguinte rodada de testes no navegador acessando a URL publicada (`https://diyspur.vercel.app`):

### 5.1. Teste de Acessibilidade & Interface Inicial
- [ ] Acesse a Home (`/`):
  - O cabeçalho fixa com blur e exibe os links principais sem desalinhamento.
  - O alternador de tema Light/Dark funciona suavemente sem flashes brancos (Zero FOUC).
  - O mockup ilustrativo exibe "Livro do seu clube" sem referências quebradas.
  - O CTA exibe "Entrar no clube gratuitamente" para visitantes anônimos.
  - A agenda de encontros exibe datas futuras formatadas no horário de Brasília (`getUpcomingMeetings`).

### 5.2. Teste de Autenticação e Redirecionamentos (QA-08 & QA-09)
- [ ] Teste a página `/cadastro` e `/entrar`:
  - Formulário carrega com campos acessíveis e foco visível.
  - Faça login com uma conta de teste.
  - Tente acessar `/entrar` ou `/cadastro` estando autenticado: a aplicação deve redirecionar imediatamente para `/perfil`.
  - Na Home, o CTA principal deve alternar para "Continuar minha leitura" apontando para `/perfil`.

### 5.3. Teste de Fila Atômica na Ficha do Livro (QA-01 & QA-02)
- [ ] Acesse `/livros` e clique em um livro publicado (ex.: `/livros/o-massacre-da-familia-hope`):
  - O título da página exibe `<title>Nome da Obra — Clube de Leitura e Discussão · DIYSPUR</title>` (sem duplicar `| DIYSPUR`).
  - O botão **"Ler a seguir (+ Fila)"** está visível.
  - Clique no botão: a RPC atômica deve reservar a posição e alterar o botão para "✓ Na sua fila (#X)".
  - Teste o botão de compartilhamento: clique em "Convidar amigo para ler junto" e verifique a mensagem única "✓ Link copiado para a área de transferência!".

### 5.4. Teste de Gestão de Clubes por @usuário (QA-05)
- [ ] Acesse um clube administrado pela conta de teste (`/clubes/[slug]`):
  - A lista de membros exibe os papéis traduzidos ("Criador", "Moderador", "Leitor").
  - Membros e convites pendentes são identificados por `@usuario` e nome legível, sem exibir UUIDs brutos na tela.
  - O formulário de convite solicita `@usuario` em vez de ID técnico.

### 5.5. Teste de Metas de Leitura (QA-04)
- [ ] Acesse `/metas`:
  - Se a conta não tiver meta anual cadastrada, a interface exibe um card acolhedor convidando a definir o objetivo, sem mostrar o falso "0 páginas lidas de 0".

### 5.6. Teste de Capítulos e Landmark Acessível (QA-10 & QA-11)
- [ ] Acesse `/comunidade` e `/historico`:
  - Títulos de capítulos na timeline aparecem sem duplicação de prefixo (ex.: `Capítulo 1 · Início`).
  - Em `/historico`, inspecione o DOM no DevTools (F12) e confirme que existe estritamente um elemento `<main id="conteudo">` (sem `<main>` aninhado no card de histórico).

### 5.7. Teste de Editor Administrativo e Fuso Horário (QA-13)
- [ ] Acesse `/admin/books` com conta admin:
  - O formulário "Cadastrar novo livro" está presente e funcional.
- [ ] No editor de capítulos (`ChapterEditor`):
  - O campo `<input type="datetime-local">` abre com a data e hora local do navegador (sem atraso ou avanço de 3 horas).
  - Ao salvar o capítulo sem alterar a hora, a data permanece inalterada sem drift de fuso.

### 5.8. Teste de Privacidade e Contato (QA-07 & QA-17)
- [ ] No rodapé de qualquer página:
  - O botão "Preferências de privacidade" abre o modal/banner de consentimento.
  - O link de "Suporte" direciona para `mailto:oi@diyspur.com`.
  - As páginas `/termos` e `/privacidade` mencionam de forma uniforme o email `oi@diyspur.com`.

---

## 6. Procedimento de Rollback e Contingência

Em caso de falha crítica durante ou após o deploy:

1. **Rollback Imediato do Frontend no Vercel**:
   - Abra o [Vercel Dashboard](https://vercel.com/dashboard) no navegador.
   - Navegue até **"Deployments"**.
   - Localize o deployment anterior que estava estável.
   - Clique no menu de três pontos e selecione **"Instant Rollback"** (ou **"Promote to Production"**).
   - O tráfego de borda é comutado instantaneamente para o build anterior em menos de 5 segundos.

2. **Rollback de Banco de Dados no Supabase**:
   - Nossas migrations são exclusivamente incrementais e retrocompatíveis (não removem colunas de produção).
   - As novas funções (`add_to_up_next_atomic` e `create_editorial_book`) coexistem com o schema anterior sem quebrar rotas legadas.
   - Caso necessário, você pode revogar execução de funções pelo SQL Editor:
     ```sql
     REVOKE EXECUTE ON FUNCTION public.add_to_up_next_atomic(uuid) FROM authenticated;
     ```

---

## 7. Contatos e Responsabilidades Operacionais

- **Suporte Técnico do Clube:** `oi@diyspur.com`
- **Dashboard Supabase:** `https://supabase.com/dashboard/project/xjhehhfhhoomblcggjpk`
- **Dashboard Vercel:** `https://vercel.com/dashboard`
- **Repositórios Oficiais:**
  - Frontend: `https://github.com/diyspur-cloud/app`
  - Backend: `https://github.com/diyspur-cloud/db`
