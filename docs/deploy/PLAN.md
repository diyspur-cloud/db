# Plano Executivo de Deploy — Supabase & Vercel

Este documento é um atalho para o guia oficial detalhado de implantação em produção.

Consulte o documento completo em:
👉 [Guia Oficial de Deploy (Navegador + CLI)](./README.md)

### Resumo Rápido dos Requisitos

1. **Navegador Web Obrigatório**:
   - Acesso ao [Supabase Dashboard](https://supabase.com/dashboard) para execução de SQL Editor, cópia de chaves e configuração de URL de Auth.
   - Acesso ao [Vercel Dashboard](https://vercel.com/dashboard) para configuração de Environment Variables, Root Directory e disparo de builds.
2. **Novas Migrations no Supabase**:
   - `db/supabase/migrations/20261012160000_add_to_up_next_atomic.sql`
   - `db/supabase/migrations/20261012161000_create_editorial_book.sql`
3. **Variáveis Obrigatórias no Vercel**:
   - `NEXT_PUBLIC_SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
   - `NEXT_PUBLIC_SITE_URL` (definir antes do build!)
4. **Smoke Tests em Produção**:
   - Seguir o checklist completo de 8 itens descrito em [`README.md`](./README.md#5-etapa-3-verificação-pós-deploy-e-smoke-tests-navegador).
