# Reconciliação de histórico e limites administrativos

## Estado confirmado nesta execução

O conector Supabase autorizou consultas read-only no projeto xjhehhfhhoomblcggjpk. O histórico consultado em 2026-10-09 contém **51 migrations**: 24 bundles/seeds `sdd_*`, 26 incrementais de 2026-10-08/09 e a migration posterior `20261009162640_close_sdd_backend_contract_gaps`, que não existe no commit local auditado.

As 24 primeiras entradas são os bundles/seeds `sdd_*` de 20261008211412 a 20261008212250. O baseline local permanece granular em `20260101…`; as correções incrementais locais têm timestamps diferentes dos remotos e a versão `close_sdd_backend_contract_gaps` não tem fonte correspondente no clone. Não existe correspondência 1:1 entre timestamps; a correspondência deve usar manifestos, definições e hashes locais, nunca a aparência do nome.

## Estado desta execução de arquivos

O clone está na branch `main`, commit `ce0355e19e9c45e915cb8d376efa3e0ced1da773`, com migrations novas geradas por `supabase migration new` e alterações de handlers/adapters ainda locais. Nenhuma migration foi aplicada ao projeto remoto, nenhuma função foi redeployada e nenhuma tabela/linha remota foi alterada nesta execução. O remoto permanece a autoridade para o que já está aplicado; o conjunto novo só pode entrar após comparar o conteúdo com `close_sdd_backend_contract_gaps` em ambiente descartável.

## Plano aplicado nesta rodada

1. Preservar migrations históricas, bundles, seeds e contrato original.
2. Consultar definições e grants reais antes das novas migrations incrementais.
3. Não executar `db push`, `migration repair`, reset remoto ou replay de bundles nesta rodada; o histórico remoto tem versões que não estão no clone.
4. Registrar as versões remotas e os hashes dos arquivos locais, sem reescrever versões já aplicadas.
5. Replay descartável deve utilizar artefato controlado que registra as correções técnicas do baseline. Um sucesso com PGlite não substitui stack Supabase com Auth/Storage/Realtime.

## Evidência das migrations e manifests

Os hashes SHA-256 das 12 migrations incrementais locais divergentes e dos seis manifests/bundles estão registrados no terminal de auditoria desta execução; os arquivos remotos expõem versão/nome, mas não o SQL-fonte via `list_migrations`. Portanto, a correspondência abaixo é de identidade documental, não uma alegação de igualdade byte a byte:

| Local | Remoto | Evidência atual |
|---|---|---|
| `20261009025153_fix_buddy_read_policy_recursion.sql` | `20261009030146` | Mesmo nome lógico; hash local `979457d949ff37518dc1607bae946410c1bfef7d4afc8eba709d712f5d4e243a`; comparar SQL antes de repair. |
| `20261009025203_restore_community_stats_contract.sql` | `20261009030211` | Mesmo nome lógico; hash local `b19bb751f73d4f39b67d6ac56f69ee2edb0c1822bc818c418af3d47e02331278`; a nova migration de snapshot é posterior e local. |
| `20261009032120_fix_quiz_idempotency_conflict.sql` | `20261009033340` | Mesmo nome lógico; hash local `55b67c14b1f25ea99aa32a8dcfc580e831d8eca6aa3447bb1309d851b15f3dad`; comparar antes de aplicar nova parcial. |
| `20261009034508_fix_atomic_rate_limits_and_club_season.sql` | `20261009035042` | Mesmo nome lógico; hash local `605ba88b7481bacc8c5e0766b88b8b03e9fc405adfbecb83664ebdb1173c155d`; sem repair automático. |
| `20261009170633_align_community_stats_snapshot.sql` | `—` | Nova local; hash `097cfb3631a4279812022e3ca16c36bc5dbc613f0b3dbeac46c7b17a19232e66`; comparar com `close_sdd_backend_contract_gaps`. |
| `20261009170637_align_user_reading_overview_contract.sql` | `—` | Nova local; hash `075a474c0185e2e8560e587b61c8b6446549f981c19eb49913664b5c24d1e2e6`; não aplicada remotamente nesta execução. |
| `20261009170642_align_reading_goal_calculation.sql` | `—` | Nova local; hash `1430e24fac94558a4c0ba962c4908f99547d3d313c9c054c153b565f161bf871`; não aplicada remotamente nesta execução. |
| `20261009170647_align_reading_snapshot_keys.sql` | `—` | Nova local; hash `70ee9f2832881f31d4cbffc453afbf5412ed84e2237443961500574690f51980`; não aplicada remotamente nesta execução. |
| `20261009170651_allow_partial_quiz_answers.sql` | `—` | Nova local; hash `3f5eed0a37a88442707838cee743cc1ab67fe887ef02f129aa6bd66a333cccf2`; depende da comparação com a versão remota de quiz. |
| `supabase/deploy-bundles/001..006` | `sdd_001..sdd_010c` | Bundles/manifests locais são evidência de conteúdo; hashes dos SQL/manifests estão versionados e não devem ser reaplicados sobre o remoto. |
| `—` | `20261009162640_close_sdd_backend_contract_gaps` | Existe no remoto, sem arquivo fonte no clone; tratar como dependência externa até obter SQL/manifesto autorizado. |

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
