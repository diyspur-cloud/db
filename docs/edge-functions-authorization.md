# Contrato de autorização das Edge Functions

**Status:** especificação preventiva. As dez Edge Functions estão versionadas, mas nenhuma está implantada no projeto remoto. Este documento não substitui revisão de produto, testes com usuários reais, configuração de secrets ou revisão de código. Cada função deve validar identidade e autorização antes de usar uma chave privilegiada.

| Função | Chamador permitido | Validações obrigatórias | Limites/controles |
|---|---|---|---|
| `quiz-validate` | Usuário autenticado | Derivar o usuário de `sub` do JWT; ignorar `user_id` fornecido no body; garantir que `chapter_id` pertence a uma temporada ativa. | Um envio/minuto por usuário e capítulo; validar payload e respostas. |
| `award-xp` | Somente backend `service_role` ou trigger | Não aceitar chamada de usuário final; validar source, quantidade e referência no servidor. A RPC do banco já teve `EXECUTE` restrito a `service_role`. | Idempotência/deduplicação por evento; auditar grants ao alterar a função. |
| `vote-next-book` | Usuário autenticado | Usar usuário de `sub`; poll precisa estar `open` e `closes_at > now()`; validar opção pertence ao poll. | Uma linha/voto por usuário e poll (constraint/upsert). |
| `scheduled-reminders` | Somente chamada serviço-a-serviço | Exigir credencial de serviço em header secreto ou mecanismo equivalente; não abrir endpoint anônimo. Validar cada destinatário e janela de lembrete. | Idempotência por usuário/meeting/janela; monitorar falhas e taxa de envio. |
| `ai-recommendations` | Usuário autenticado | Ignorar `user_id` do body e usar `sub`; limitar os dados de leitura retornados ao próprio usuário. | Uma chamada/hora por usuário, além de limites de custo do provedor. |
| `ai-user-embeddings` | Serviço ou usuário sobre o próprio embedding | Se JWT de usuário, exigir `sub = user_id`; se serviço, validar autenticação serviço-a-serviço; restringir o snapshot à identidade autorizada. | Uma recomputação/hora por usuário e deduplicação do job. |
| `match-readers` | Usuário autenticado | Calcular matches exclusivamente do usuário `sub`; não aceitar UUID alheio como dono do cálculo. | Uma chamada/hora por usuário e limite de resultados. |
| `newsletter-dispatch` | Admin autenticado | Checar role admin em fonte confiável; exigir issue existente e não enviada; enviar somente a inscritos confirmados e respeitar frequência/unsubscribe. | Uma execução por issue, `sent_at` idempotente e registro em `newsletter_deliveries`. |
| `stripe-webhook` | Stripe | Validar assinatura HMAC do corpo bruto com `STRIPE_WEBHOOK_SECRET`; validar timestamp/evento e atualizar estado com transação. | Unique `(provider,event_id)`; rejeitar replay e processar idempotentemente. JWT não substitui assinatura Stripe. |
| `social-render-card` | Usuário autenticado | Exigir `user_id` do body igual a `sub`; validar conteúdo e ownership de mídia. | No máximo 10 jobs/dia/usuário; limitar tamanho/frequência e custo. |

## Regras comuns de implementação

1. Por padrão, manter verificação JWT habilitada. Desabilitá-la somente quando o endpoint tiver autenticação alternativa validada criptograficamente (por exemplo, webhook Stripe) ou mecanismo serviço-a-serviço explícito; `verify_jwt=false` não é autorização.
2. Nunca confiar em `user_id`, `role`, `issue_id`, `poll_id` ou flags de admin do body sem confirmar vínculo, papel e estado no banco.
3. Manter `service_role` apenas em secret do runtime server-side. Nunca retornar a chave nem encaminhar requests privilegiadas sem validação.
4. Armazenar secrets do provedor no Supabase, não no repositório. Configurar timeouts, payload limits, rate limits, logs sem PII e alertas.
5. Fazer teste positivo e negativo para anônimo, usuário A, usuário B, admin, evento repetido e payload inválido. Validar side effects e idempotência antes de publicar.
6. Para newsletter e lembretes, provar consentimento, unsubscribe, fuso/horário e proteção contra envio duplicado antes do primeiro disparo.

## Estado atual e tarefas de deploy

`quiz-validate` foi ajustada no repositório para separar o cliente com JWT do cliente privilegiado que chama `award_xp`; isso é uma correção de camada de código, **não** uma validação completa das regras acima nem um deploy. O handler de reminders não está implantado. Portanto, não foi criado job HTTP de reminders: até que a função e autenticação estejam prontas, um cron periódico apenas geraria requisições falhas e ruído operacional.

Antes de deploy, compare cada fonte com a tabela, implemente as verificações faltantes, rode testes com pelo menos duas identidades em ambiente isolado, configure secrets e execute deploy individual controlado. Registre versão, smoke test, rollback e responsável pelo monitoramento.
