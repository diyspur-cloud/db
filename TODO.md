# Execução do SDD

Critérios originais; só marcar concluído com evidência.

**Escopo atualizado pelo usuário:** backend/Supabase exclusivo. Itens 16–25 que exigem UI/frontend estão adiados por orientação explícita, não por falha de execução. Bônus de streak25 uma vez por dia com atividade; newsletter todos confirmados ignorando tags.

**Estado remoto:** nove migrations novas aplicadas, dez handlers ACTIVE (newsletterv2), cron reminders ativo e pg_netHTTP200. Resultados locais e bloqueios externos são detalhados em docs/execution/remote-observations.md; não confundir deploy com integração de provider.

- [ ] **1. Buddy reads: leitura interrompida por recursão de RLS**
  as três consultas deixam de retornar 42P17; buddy read privado continua invisível a terceiro; INSERT/DELETE seguem as condições do SDD. Ausência de erro com `limit=0` não encerra os testes de autorização.

- [ ] **2. Listas personalizadas: leitura interrompida por recursão de RLS**
  consulta das três relações sem 42P17; colaborador lê lista compartilhada; terceiro não lê privada; `can_edit=false` não permite edição; troca de `list_id` não permite escrever em outra lista. Conferir também INSERT/UPDATE/DELETE dos colaboradores, pois esses caminhos precisam ler o pai.

- [ ] **3. Helper `is_admin()` incompatível com os grants atuais de perfis**
  anon e leitor recebem false, admin true, sem 42501; dados privados e `profiles.role` continuam sem SELECT direto pelo cliente. Não houve teste remoto como admin nesta sessão.

- [ ] **4. Reações, respostas, feed e streak: triggers sem privilégios para manter contadores**
  A reage/responde ao conteúdo de B autorizado pelas policies, sem 42501; insert/delete mantém os contadores; UPDATE/UPSERT de progresso atualiza streak; usuário não altera contadores pelo REST. As policies e grants de cada tabela continuam sendo a porta de entrada. Esta correção não cria nova regra de pontos, likes ou streak além das existentes no SDD.

- [ ] **5. Onboarding não consegue gravar `level` e concluir `onboarding_done`**
  leitor conclui os quatro campos do anexo, reabre sessão e lê `onboarding_done=true`; leitor não altera outro perfil, `role` ou timestamp de consentimento.

- [ ] **6. Google e GitHub não habilitados no Supabase Auth**
  Google e GitHub habilitados e login completo demonstrado; Magic Link e senha testados sem inferir sucesso a partir de `external.email=true`.

- [ ] **7. Os dez handlers exigidos no SDD não estão publicados**
  nenhum dos dez endpoints permanece NOT_FOUND; não confundir OPTIONS/GET respondendo com fluxo de negócio completo. Integrações Resend/OpenAI/Stripe só ficam validadas após execução controlada.

- [ ] **8. Cron de reminders não implementado como arquivo executável e incompatível com header atual**
  um job por nome, primeira execução observada em `cron.job_run_details` e resposta do `pg_net`; payload de notificação contém reunião/título/horário; execução repetida não duplica o lembrete. Não foi criado cron nesta análise.

- [ ] **9. `streak_bonus: 25` do SDD rejeitado pelo endpoint de XP**
  25 pontos somente para a condição que for explicitada; retry da mesma referência sem crédito duplicado. A simples inclusão no mapa sem validação server-side não encerra este item.

- [ ] **10. Contrato de entrada do quiz mudou: exemplo do anexo não é aceito**
  consumidor e contrato de request documentados de forma coerente; submissão e retry aprovados; casos parcial/temporada/tamanho com resultados registrados. Não executados no remoto porque a função está ausente.

- [ ] **11. Contrato das estatísticas comunitárias de livros diferente do anexo**
  payload expõe todos os nomes/valores do anexo; sem votos/avaliações usa os mesmos defaults; fonte de cada número explícita. A estrutura segura em `private` é uma diferença intencional e pode ser mantida com API compatível; não anunciar igualdade do nome físico original.

- [ ] **12. Painel de clubes sem os nomes e a agregação previstos no anexo**
  A/B contribuem com números corretos no painel coletivo público/owner; terceiro não vê clube privado; nomes do anexo consultáveis; média zero sem progresso.

- [ ] **13. Contratos alterados de privacidade e agregação precisam de consumidores compatíveis**
  Executar conforme seção original; conflitos ou permissões pendentes permanecem explícitos.

- [ ] **14. Seed complementar não faz parte do reset local**
  base local reconstruída recebe os dois seeds uma vez; repetir seed não duplica; os dados demonstrativos ficam na temporada correta. O reset remoto não foi autorizado nem realizado.

- [ ] **15. Filtro da newsletter criado pelo seed é rejeitado pelo handler**
  a edição gerada pelo próprio seed não recebe 422; conjunto de destinatários esperado explicitado; reexecução sem duplicar entregas já enviadas. O envio real não foi executado nesta análise.

- [ ] **16. Aplicação Next executável e conexão do middleware ausentes neste repositório**
  aplicação compila, autenticação/refresh funcionam e chamadas de servidor usam sessão do mesmo usuário. Sem URL/repositório da aplicação, esta etapa é planejável mas não verificável como produto.

- [ ] **17. Fluxo P0 da aplicação: livro, calendário, vídeo, discussão, quiz e progresso**
  executar a cadeia inteira com usuário de teste; comentário protegido conforme percent, quiz persistido e XP único, progresso reaberto sem perda, próximo capítulo na mesma temporada, link Amazon correto. Não criar outro progresso por livro para suprir o painel.

- [ ] **18. Canais frontend de Realtime não implementados**
  insert/update/delete refletidos nas telas, desconexão tratada, sem PII/gabarito/texto bloqueado no payload mostrado; testes autenticados A/B. Estado da publicação remota não foi catalogado nesta sessão.

- [ ] **19. Perfil, XP, streak, badges, enquetes e ranking sem integração de produto**
  UI exibe dados persistidos corretos; voto atualizado via server, ranking por temporada, perfil não expõe campos pessoais; badges sem fabricar concessão que o SDD não especifica.

- [ ] **20. Metadados, curadoria e comentários no player sem consumidores**
  contagem de 0/1/2 representa opções literais, marcações do vídeo saltam para o segundo correto, curadoria não continua exibindo seleção expirada. Não foi executada UI do YouTube nesta análise.

- [ ] **21. Diário, listas e Up Next sem interfaces do roadmap**
  entrada/arquivo/mood persistidos, compartilhamento de body conforme visibilidade, colaboração não altera lista alheia, sexto livro/posição é recusado pelo banco, mudança de fila não perde linhas. A publicação de likes de diário é extensão do repo; não é requisito novo deste documento.

- [ ] **22. Milestones, médias de quiz, metas e desafios sem interface**
  médias mudam após tentativa; metas e overview exibem o significado adotado na divergência §13; leitor só modifica própria meta/desafio; marcos na ordem da temporada. O SDD não fornece verificação automática completa de cada regra JSON de challenge, portanto não inventar regras de conclusão.

- [ ] **23. Feed, clubes, follow e match sem telas do roadmap**
  filtros exibem somente posts autorizados, terceiros não veem clube/post privado, match não calcula outro usuário e cache fica pessoal. Sem deploy, integração real ainda não funciona.

- [ ] **24. Assinaturas, newsletter e clique de afiliado sem integração de produto**
  cliques registrados, falha de logging não bloqueia link; eventos Stripe autenticados atualizam assinatura certa e replays não duplicam; newsletter aplica a audiência decidida e registra entregas. Checkout, criação de payment link e entitlement automático não têm implementação especificada no anexo: não acrescentar código arbitrário para esses serviços.

- [ ] **25. Atividades, caderno interativo e cards sem interfaces**
  atividade publicada correta, tentativa persistida, resposta própria relida com visibilidade, job/card sem perda de payload. Renderização PNG, export para redes específicas e desenho de novas templates não são especificações do anexo e não foram inventadas.

- [ ] **26. Reconciliar histórico antes do replay e completar validação final**
  todos os itens acima têm evidência do ambiente certo; testes locais sem falsos stubs; OpenAPI atualizado; nenhum resultado não executado apresentado como aprovado.

- [ ] **27. Inconsistências do anexo que impedem igualdade literal sem uma decisão**
  Executar conforme seção original; conflitos ou permissões pendentes permanecem explícitos.


## Fechamento por camada — 09/10/2026

Os critérios originais acima misturam implementação, aplicação remota e validação de produto. Mantêm-se abertos onde integração real/UI não foi demonstrada. As frases originais sobre função ausente/cron não criado são o diagnóstico inicial, não o estado atual.

| Itens | Implementação/aplicação | Evidência e limite |
|---|---|---|
| 1–5 | Correções RLS/admin/triggers/onboarding aplicadas | PGlite PASS; probes remotos sem recursão; matriz Auth real staging pendente |
| 6 | Google Cloud OAuth Testing criado, titular test user | Supabase Google não salvo por autocomplete; GitHub/Magic Link/login completo pendentes |
| 7 | Dez handlers publicados ACTIVE | Probes de método/ausência de sessão; integrações reais parciais |
| 8 | Cron horário/Vault/pg_net configurados | Chamada manual HTTP 200; primeira execução agendada ainda não observada |
| 9 | 25 XP/dia com atividade implementado/aplicado | PGlite idempotência PASS; não criar dados fictícios em produção |
| 10 | Entrada/retry/conflito de quiz corrigidos e documentados | Deno/SQL/PGlite; POST com sessão real staging pendente |
| 11–13 | Aliases/projeções protegidas restaurados | Contrato reduzido PASS; diferenças de snapshot/level/temporada explícitas |
| 14 | Seeds ordenados/guards; runner full descartável | Full Docker não executado; replay reduzido não valida todos os seeds |
| 15 | Tags aceitas e audiência todos confirmados | Nenhum envio; Gmail não é domínio Resend verificável |
| 16–25 | Frontend/UI adiados pelo titular | Somente partes backend subjacentes incluídas; nenhum aceite visual |
| 26 | OpenAPI 3.1, SQL, Deno e PGlite validados | Baseline remoto/granular não convertido em db push seguro; staging/backup/carga pendentes |
| 27 | Decisões registradas sem inventar engines | Motores de badges/games/cards/Discord/Calendar não especificados |

Fechamento técnico adicional: ler `docs/execution/REPORT-final-fixes.md`. README atual detalha todas as alterações e separa evidências locais/remotas. Stripe teste recebeu probe assinado técnico (200/replay duplicate); assinatura ausente/inválida retorna 400, sem efeito financeiro.
