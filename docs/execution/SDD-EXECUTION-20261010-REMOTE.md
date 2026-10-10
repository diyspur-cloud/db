# Evidência de execução remota — 2026-10-10

## Supabase

- Projeto: `xjhehhfhhoomblcggjpk`
- Estado antes: migration editorial ausente no histórico remoto.
- Ação: apply da migration `editorial_product_lifecycle`.
- Estado depois: migration registrada remotamente como `20261010030848_editorial_product_lifecycle`.
- Resultado: sucesso.
- Auditorias pós-apply: security e performance executadas; advisories registrados no README, sem alteração silenciosa.

## GitHub

- Frontend: PR #2 integrado em `main`.
- Backend: PR #4 integrado em `main`.
- Documentação de release e o contrato TypeScript sincronizado foram preparados para commit direto em `main`, conforme autorização do proprietário.

## Vercel

- Projeto conectado: `diyspur`.
- O deploy é Git-based e é acionado pelo push do frontend em `main`.
- A API MCP de inspeção/deploy retornou 403 para o escopo da equipe nesta sessão; a publicação seguirá pelo trigger Git já configurado e será verificada pelo domínio público.
