# Plano e registro de implementação do SDD — DIYSPUR

**Data:** 9 out. 2026 (UTC−03)
**Repositórios:** [app](https://github.com/diyspur-cloud/app) · [db](https://github.com/diyspur-cloud/db)
**Branches locais de trabalho:** `feat/sdd-melhorias-20261009` em ambos
**Preview temporário, somente leitura:** https://3311-ikdnhnwfvud69qx7ypx0a-1308eb0c.us1.manus.computer
**Fontes do escopo:** `sdd_melhorias.md`, `sdd_front.md`, `db/docs/implementation-plan.md`, `db/docs/implementation-blockers.md`.

## Objetivo e segurança operacional

Implementar mudanças incrementais de frontend/backend, testar com automação e integração pública read-only, publicar uma prévia verificável e preparar push das branches. Não editar migrations históricas, não executar DDL remoto, não implantar Edge Functions, não gravar comentários/votos/progresso/RSVP em produção, não enviar e-mail e não executar pagamentos.

A prévia usa o projeto Supabase fornecido somente para leitura pública. Variáveis `DIYSPUR_READ_ONLY_PREVIEW=1` e `NEXT_PUBLIC_READ_ONLY_PREVIEW=1` bloqueiam Server Actions de mutação e desativam cadastro/magic-link no preview; login de usuário existente continua útil para ler suas próprias páginas sob RLS. Não usar o link como ambiente de validação de writes.

## Registro por fase do SDD

| Fase | Trabalho realizado | Evidência/estado | Pendências que impedem aceite integral |
|---|---|---|---|
| 0 — Baseline/reconciliação | Clonagem, branches isoladas, leitura do histórico, plano e bloqueadores | Feito localmente; sem mutation/deploy remoto | Reconciliação das versões locais/remotas, backup/restore, ambiente staging e rollback continuam gates para `db push` |
| 1 — Autorização/RLS/onboarding | Migration aditiva `restrict_future_chapter_visibility`; filtra conteúdo de capítulos publicados em temporadas ativa/finalizada; contrato SQL; smoke PGlite | Parser `pglast` e suíte security-smoke passaram; arquivo não aplicado ao Supabase | Onboarding completo/OAuth providers e matriz com sessões reais não validados; gates documentados de staging/Auth permanecem abertos |
| 2 — Capítulo | Query e navegação por capítulos publicáveis; progresso; comentário criar/editar/soft-delete; spoiler; quiz via Edge Function; encontro; comentários temporizados com segundo informado manualmente e link YouTube seguro | Typecheck/lint/unit/build/E2E geral passam; contrato `quiz-validate` conferido localmente | Ainda falta Playwright autenticado com duas contas para CRUD/progresso/quiz; o preview bloqueia mutations; seek no player não foi ligado à IFrame API |
| 3 — Perfil/histórico | Overview, métricas presentes, XP/streak/conquistas e histórico real; estados vazios | Implementado no app; TypeScript/build passam | Falta comparar resultados com SQL de referência usando duas contas de teste/staging |
| 4 — Gamificação/ranking | Resumo de XP/streak/conquistas reais no perfil | Parte de perfil implementada; XP só é consumido do saldo do DB | Página/ranking, histórico de XP e opt-in/visibilidade pública ainda não implementados; dependem de política de privacidade e validação por Auth real |
| 5 — Agenda/lembretes/notificações | Notificações do titular e “marcar como lida”; RSVP aceitar/cancelar com `user_id` de claims; integração no calendário | Components/actions integrados; typecheck/lint/testes/build passam; Data API anônima nega tabela RSVP | Preferências/envio de reminder, provider/secrets, cancelamento de encontro e entrega deduplicada ainda não testados em staging |
| 6 — Enquetes/próximo livro | Página de votação, pergunta/opções, action Edge Function com apenas IDs autorizados, validação e estado/resultados conforme disponibilidade | Implementado e testes unitários de schema/action passam; handler local conferido; preview HTTP 200 | Falta voto autenticado e fechamento/resultados em integração multiusuário; Edge Function remota pode diferir do working tree |
| 7 — Desafios/listas/buddy reads | Página de desafios somente leitura; páginas `/listas` e `/leituras-compartilhadas` só consultam linhas autorizadas, com RLS e estados vazios | Implementado em leitura; typecheck/lint/build passam; smoke RLS PGlite prova acesso e nega IDOR/cross-owner | Participação, CRUD, convite/aceite e progresso calculado de desafios não foram liberados, pois exigem evidência de Auth real/sem RLS divergente e regras de conclusão definidas |
| 8 — Comentários sincronizados | Query RLS de comentários temporizados; formulário com segundos inteiros 0–86.400; action titular; link HTTPS canônico a YouTube; página integrada | Módulo integrado, lint/typecheck/build passam; nenhuma nova tabela | A API IFrame não permite seek/controle temporal nesta integração; falta E2E autenticado de publicação; writes bloqueados no preview |
| 9 — Recomendações/matching/metadados | Nenhuma chamada de provider exposta à interface | Mantido deliberadamente desativado; sem exposição de embeddings | Produto precisa definir opt-in, finalidade, retenção/exclusão, bloqueio/denúncia e credenciais/rate-limit de providers antes de integrar |
| 10 — Monetização/newsletter/conteúdo extra | Nenhuma mutation/billing exposta no preview | Nenhum preço/segredo incluído no cliente; sem checkout | Faltam `stripe_price_id`, secrets e testes Stripe/newsletter em staging; política de entitlements e conteúdo assinado precisa de validação |
| 11 — Administração editorial | Acesso existente permanece protegido por sessão/papel admin; nenhuma operação editorial nova | Build inclui rota `/admin`; nenhuma escrita editorial executada | Falta decidir e implementar ciclo de rascunho/publicação, regras de deleção e trilha de auditoria; o schema atual preserva capítulos legados com `published_at NULL`, não distingue um rascunho recém-criado sem rollout/migration |

## Validação executada

| Verificação | Resultado |
|---|---|
| `npm run typecheck` (app) | PASS |
| `npm test` (app) | PASS — 3 arquivos / 13 testes |
| `npm run lint` (app) | PASS |
| `npm run build` (app, variáveis de preview) | PASS — rotas dinâmicas compiladas |
| `npm run audit` (app) | PASS — zero vulnerabilidades de produção reportadas |
| `npm run test:e2e` (Playwright/Chromium, build local read-only) | PASS — 6 testes |
| `npm test` (`db/scripts/security-smoke`) | PASS — assertions de security, business rules, correções finais e publicação futura |
| `pglast` (migration + SQL contract) | PASS |
| `git diff --check` nos repos | PASS |
| Data API anônima read-only | PASS — view agregada e catálogo retornam HTTP 200; `meeting_rsvps`, `user_challenges`, `host_prompt_votes` retornam HTTP 401; nenhum payload pessoal lido |
| Preview HTTP público | PASS — `/`, `/livros`, `/calendario`, `/votacao`, `/listas`, `/leituras-compartilhadas`, `/notificacoes`, `/desafios` HTTP 200; `/perfil` e `/historico` redirecionam sem sessão; UUID aleatória de capítulo retorna 404; cadastro desabilitado |
| Writes no Supabase remoto | **Não executados**, intencionalmente |

Uma primeira chamada de diagnóstico selecionou colunas incorretas para três relações e retornou 400; ela foi descartada sem body ou linhas. A verificação corrigida usou `HEAD` com `limit=0`, validou HTTP 401 e não retornou dados pessoais.

## Critérios não atendidos — não apresentar como concluídos

1. **Teste real multiusuário/Auth/Storage/Realtime**: o harness existente e os smoke tests são locais/PGlite; não houve teste com dois JWTs reais. A documentação registra que uma branch Supabase isolada foi anteriormente recusada diante da cotação de **US$ 0,01344/h**; não criar outra nem alterar produção sem autorização renovada.
2. **Migrations/Edge Functions remotas**: migration nova não foi aplicada; as versões de Edge Functions no Supabase continuam potencialmente diferentes do código local. A reconciliação de histórico e backup continuam obrigatórios antes de deploy.
3. **Regras ainda dependentes do produto**: XP por evento/limites/timezone; critério de capítulo concluído e desbloqueio de spoiler; visibilidade/opt-out do ranking; publicação editorial; consentimento/retention de recomendações; regras e preços de assinatura.
4. **Configuração externa**: providers OAuth, secrets de OpenAI/Resend/Stripe/reminders, IDs reais de preço/callbacks e endereços de teste não foram obtidos nem alterados.
5. **Push/release**: mudanças estão em branches locais de feature e foram testadas; não foram mergeadas a `main`. Enviar os dois pushes depois do último double-check do usuário/branches e dos gates operacionais ainda abertos, em vez de dizer que a execução é produção-ready.

## Sequência para concluir os gates

1. Decidir se abre branch Supabase isolada (custo recorrente informado acima) ou se prefere outro projeto de staging já existente.
2. Disponibilizar secrets/provider IDs via secret store e configurar OAuth/callbacks somente no ambiente de teste.
3. Confirmar regras de domínio listadas acima e desenhar o ciclo draft/publish sem expor conteúdo legado.
4. Reconciliar migration history, restore point e plano de rollback; aplicar a migration somente no ambiente aprovado.
5. Executar integração Auth/RLS com anon, titular A, titular B, colaborador/admin; incluir mutations, upload/download Storage, Realtime e E2E da jornada do capítulo.
6. Implementar os módulos P2/P3 bloqueados e CRUD editorial, repetir a validação integral, double-check dos dois diffs e então publicar os pushes.

## Definição de pronto

Uma rota compilada ou smoke anônimo não comprova a integração write/auth. Marcar qualquer fase integralmente concluída apenas depois da jornada visual, validação server-side, autorização no banco, persistência após reload, idempotência e teste positivo/negativo no ambiente de staging designado.
