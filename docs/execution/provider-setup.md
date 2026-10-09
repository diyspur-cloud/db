# Integrações externas — fechamento em 9 de outubro de 2026

## Stripe — modo teste

- `STRIPE_SECRET_KEY` de teste recebido foi cadastrado no armazenamento Edge Supabase.
- Webhook `we_1UOUMhC64GfThfP320iScmRi` criado, `livemode=false`, `enabled`, URL `https://xjhehhfhhoomblcggjpk.supabase.co/functions/v1/stripe-webhook`, eventos checkout.session.completed e customer.subscription.created/updated/deleted/paused/resumed.
- `STRIPE_WEBHOOK_SECRET` cadastrado e confirmado em 03:32 UTC.
- Probe assinado de evento técnico respondeu HTTP 200 `processed`. Pode registrar evento técnico em `payment_events`, sem customer/assinatura/efeito financeiro. Não houve pagamento, compra, checkout, customer de negócio ou assinatura criada.
- Ausência de assinatura inicialmente retornava 503. O handler foi corrigido para distinguir secret ausente (503) de assinatura ausente/inválida (400).
- Teste real de mapeamento de price/assinatura de produção não realizado. Chave de teste não habilita operações live.

## Resend

- `RESEND_API_KEY` recebido cadastrado e confirmado no painel.
- Consulta read-only à API de domínios retornou HTTP 401 `restricted_api_key`: chave restrita somente a enviar e-mails; não permite listar domínios. Não prova invalidade para envio.
- Titular escolheu `diyspur@gmail.com`; cadastrado como `RESEND_FROM_EMAIL`, confirmado no painel em 03:34 UTC.
- **Remetente não validado para envio:** Gmail não é domínio próprio verificável pelo titular no Resend. Usar remetente de domínio verificado antes de envio real. Não foi inventado um domínio, nem enviado e-mail/newsletter.
- Audiência aprovada: todos os confirmados não cancelados; filtros de tags aceitos e ignorados na seleção.

## Google OAuth

- Conta: `diyspur@gmail.com`. Termos Cloud e política de dados API aceitos após confirmações explícitas.
- Projeto `diyspur-clube-de-leitura` criado sem cobrança, vínculo de billing ou trial.
- App External/Testing, sem publicação ampla.
- Cliente `Diyspur Supabase Web — Testing` criado como Web application; único callback: `https://xjhehhfhhoomblcggjpk.supabase.co/auth/v1/callback`. Não adicionadas origens arbitrárias.
- Titular é o único test user; painel confirmou `1 user (1 test, 0 other)`.
- Client ID/Secret preservados temporariamente fora do Git.
- **Provedor Google ainda não salvo/habilitado no Supabase:** autocomplete do navegador substituiu repetidamente valores OAuth pelas credenciais do painel. Foi solicitada ajuda; titular depois pediu finalizar e fazer push.
- Não foram alteradas opções Skip nonce checks, permitir sem e-mail, MFA, linking manual ou anonymous sign-ins.
- Não houve login OAuth completo. Site URL e allowlist da aplicação dependem da aplicação real; frontend excluído do escopo.

## GitHub OAuth e OpenAI

GitHub OAuth Supabase pendente de OAuth App/Client ID/Secret e habilitação. O token de Git não foi reutilizado como credencial OAuth. OpenAI Edge pendente de credencial própria; credencial Manus não foi transferida para outro serviço. Handlers IA publicados, sem inferência real confirmada.

## Fontes

- [Supabase secrets](https://supabase.com/dashboard/project/xjhehhfhhoomblcggjpk/functions/secrets)
- [Supabase providers](https://supabase.com/dashboard/project/xjhehhfhhoomblcggjpk/auth/providers)
- [Google clients](https://console.cloud.google.com/auth/clients?project=diyspur-clube-de-leitura)
- [Google Testing audience](https://console.cloud.google.com/auth/audience?project=diyspur-clube-de-leitura)
- [Stripe webhook API](https://docs.stripe.com/api/webhook_endpoints/create)
- [Resend domains API](https://resend.com/docs/api-reference/domains/list-domains)

Nenhum valor privado consta neste documento. Recomenda-se ao titular rotacionar as credenciais que enviou no chat, atualizando os stores protegidos. Não houve rotação automática.
