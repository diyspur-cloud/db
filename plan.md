# Execução integral do SDD Diyspur

## Atualização de escopo pelo usuário — 09/10/2026 UTC
Foco exclusivo em backend/Supabase. Não implementar ou entregar alterações de frontend nesta rodada; §§16–25 permanecem fora do escopo de UI, mas os contratos e suportes de backend serão corrigidos. Bônus de streak: 25 XP uma vez por dia com atividade verificada no servidor, referência diária idempotente. Newsletter: todos os inscritos confirmados, ignorando tags conforme comportamento literal aprovado. Não continuar os módulos de aplicação previstos abaixo; o texto anterior é preservado como histórico de planejamento, não como autorização atual.

## Direção autorizada
Executar o anexo de pendências sobre o contrato original em `docs/execution/SDDBD2-original.md`, preservando tabelas, dados e proteções. Supabase externo xjhehhfhhoomblcggjpk; código existente diyspur-cloud/db. Criar a aplicação Next.js 15 no mesmo código, sem substituir banco ou Auth. O pedido de executar tudo autoriza implementação e validação; não permite inventar credenciais, regras expressamente indefinidas, conteúdo editorial ou resultados de testes.

## Implementação
Migrations incrementais geradas pela CLI, após inspecionar histórico e catálogo remotos. Helpers privados de visibilidade/admin; triggers internos sem RPC pública; grants próprios de onboarding; aliases compatíveis das views mantendo ordem. Sem reset remoto, seeds remotos ou replay cego do baseline. Corrigir replay local por artefato controlado, mantendo migrations históricas intactas.

Reaproveitar os dez handlers, autenticação por identidade validada, ledger e idempotência. Corrigir contrato newsletter sem decidir audiência silenciosamente; explicitar opções contratuais e bloquear despacho quando indefinido. Configurar cron apenas se endpoint, Vault e segredo coincidente forem verificáveis. OAuth depende das credenciais reais dos provedores.

Aplicação SSR Next 15 com React, clientes Supabase existentes e tipos. Auth email/senha, Magic Link, OAuth/callback; onboarding; fluxo de leitura completo e onze subscriptions com cleanup/releitura protegida. Módulos de perfil/gamificação, diário/listas/fila, estatísticas/metas/desafios, feed/clubes/matches, assinatura/newsletter e atividades/caderno/cards conforme entidades e payloads reais. Erros e estados vazios explícitos, não mocks de usuário ou integrações.

## Estrutura
- `supabase/migrations`: mudanças incrementais de banco.
- `supabase/functions`: handlers Deno e auxiliares existentes.
- `src/lib/supabase`: clientes, contratos e consumidores tipados.
- `src/app`: rotas SSR e callback; componentes client isolados.
- `src/components`: UI reutilizável de produto.
- `scripts/security-smoke`, `scripts/integration-smoke`, `supabase/tests`: testes no sistema existente.
- `docs/execution`: anexo preservado, evidências e impedimentos reais.
- `docs/openapi.yaml`: contratos efetivos dos dez handlers.

## Design
Movimento: editorial literário contemporâneo. Princípios: leitura primeiro, hierarquia clara, acessibilidade e honestidade dos estados. Paleta papel marfim, tinta carvão e verde biblioteca; verde profundo como cor proprietária. Layout de revista, navegação lateral e páginas de leitura em coluna, sem painel central genérico. Motivos: linhas editoriais, numeração de capítulos e selo monograma D. Interações diretas com confirmação de persistência; animações discretas de 120–180 ms, respeitando reduced-motion. Tipografia Georgia para títulos e system sans para controles. Essência: leitura compartilhada com contexto e privacidade; acolhedora, criteriosa, curiosa. Voz: “Seu próximo capítulo começa aqui.” e “Compartilhe sem revelar a história.” Wordmark editorial com inicial D marcada por uma linha de lombada. Sem ilustrações decorativas; capas reais do catálogo quando disponíveis.

## Ambiguidades que não podem ser fabricadas
Bônus streak de 25 sem condição/ref; concessão automática de badges/desafios sem motor definido; audiência newsletter tags vs todos; jogos sem payload; templates sociais; double opt-in; Discord/Calendar; vídeos e agenda operacionais. Preservar comportamento seguro existente, registrar item parcial e obter escolha antes de alterar regra material. SSR mantém browser client previsto, sem alegar cookies httpOnly; cookies HTTPS de preview SameSite=None/Secure e configuração explícita de HTTP local.

## Entrega
Código validado, PR GitHub, preview executável, migrations aplicadas somente com evidência de catálogo/histórico, relatório por item distinguindo implementado, testado local, testado remoto e bloqueado. Nenhum teste não executado é aprovado.
