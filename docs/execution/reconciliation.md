# Reconciliação de histórico e limites administrativos

## Estado confirmado nesta execução

O conector Supabase autorizou `execute_sql` no projeto xjhehhfhhoomblcggjpk. Isso substitui a limitação da sessão anterior descrita no anexo: o catálogo e histórico agora foram consultados de verdade. O histórico anterior às mudanças contém 38 migrations, conforme `remote/migration-history-data.json`.

As 24 primeiras entradas são os bundles/seeds `sdd_*` de 20261008211412 a 20261008212250. O baseline local permanece granular em `20260101…`. As 14 seguintes representam as correções de 20261008 e 20261009 presentes no repositório. Não existe correspondência 1:1 entre cada timestamp granular e cada bundle; a correspondência deve usar manifestos e definições, não a aparência do nome.

## Plano aplicado nesta rodada

1. Preservar migrations históricas, bundles, seeds e contrato original.
2. Consultar definições e grants reais antes das novas migrations incrementais.
3. Aplicar somente migrations novas já testadas, individualmente, pelo conector; não executar `db push`, `migration repair`, reset remoto ou replay de bundles.
4. Capturar as novas versões remotas e alinhar os nomes dos arquivos incrementais ao histórico efetivamente gerado, sem reescrever versões já aplicadas.
5. Replay descartável deve utilizar artefato controlado que registra as correções técnicas do baseline. Um sucesso com PGlite não substitui stack Supabase com Auth/Storage/Realtime.

## Evidência administrativa

- Cron existente: somente `refresh-mv-book-community-stats`, `0 */6 * * *`; não alterar.
- Vault: nenhum nome de secret registrado na consulta administrativa. Isso não prova ausência de secrets no runtime Edge, que é um inventário diferente.
- `pg_cron` 1.6.4, `supabase_vault` 0.3.1 e `pg_stat_statements` 1.11 instalados; `pg_net` e `pgtap` ainda não instalados na consulta inicial.
- Edge Functions: inventário inicial vazio; probes HTTP confirmaram NOT_FOUND para os dez nomes.
- GitHub Actions secrets: a listagem retornou HTTP 403 `Resource not accessible by integration`. Não tentar contornar esse limite nem afirmar ausência de secrets. Publicação por conector Supabase é uma autoridade distinta já habilitada e será usada se aceita.
- Sem ferramenta habilitada de configuração Auth, runtime secrets ou inventário de backups neste conector. Não declarar OAuth habilitado, secrets ausentes ou backup desligado sem evidência.

## Sem resets ou dados fabricados

Não foram criadas contas reais, pagamentos, disparos de newsletter, vídeos fictícios ou reuniões inventadas para simular êxito. Testes mutantes do harness atual bloqueiam explicitamente o ref de produção; respeitar esse bloqueio. Para evidência end-to-end, será necessário ambiente apropriado/autoridade adicional, não remover o guard de produção.

## Consultas de índices

EXPLAIN ANALYZE/BUFFERS do feed público utiliza `feed_posts_public_idx`; cache de matches utiliza `umc_user_sim_idx`; perguntas por capítulo utilizam `quiz_questions_chapter_id_position_key`. As consultas com UUID nulo de teste retornaram zero linhas. Estes planos comprovam acesso a índices no estado atual, não desempenho com volume representativo nem autorização multiusuário. Não remover índices com base em unused ou base pequena.

Volume confirmado em consulta administrativa: feed=0, quiz_questions=1, user_match_cache=0. Não há volume representativo para encerrar o aceite de performance.
