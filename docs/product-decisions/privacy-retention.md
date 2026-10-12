# Decisão de Produto: Retenção, Privacidade e Ciclo de Vida de Dados — DIYSPUR

**Data:** 11 de outubro de 2026  
**Status:** Decisão Formal de Produto e Engenharia

---

## 1. Princípios de Minimização de Dados (LGPD)

O DIYSPUR opera sob o princípio da necessidade e minimização estrita de dados:
1. **Dados de Autenticação**: Gerenciados pelo Supabase Auth com hashing seguro de senhas via Argon2/Bcrypt.
2. **Dados Pessoais (PII)**: Limitados a nome de exibição (`display_name`) e nome de usuário (`username`). E-mails permanecem em schema restrito e não são expostos em endpoints de leitura pública.
3. **Diário de Leitura**: Classificado como conteúdo estritamente privado do usuário, sujeito a controle de acesso por Row Level Security (`auth.uid() = user_id`).

---

## 2. Política de Retenção por Classe de Dados

| Classe de Dado | Período de Retenção Ativo | Tratamento após Solicitação de Exclusão |
|---|---|---|
| **Contas de Usuário** | Enquanto a conta estiver ativa | Anonimização ou exclusão definitiva em até 15 dias úteis |
| **Notas de Diário** | Enquanto mantidas pelo leitor | Exclusão física atômica (`DELETE CASCADE`) |
| **Comentários Comunitários** | Indefinido (vida útil da conversa) | Desassociação de autor (exibido como "Leitor Excluído") |
| **Confirmações de Presença (RSVP)** | Até o término da temporada do livro | Exclusão física |
| **Logs de Conexão / Auditoria** | 6 meses | Exclusão automática após expiração do prazo legal (MCI) |

---

## 3. Arquivamento Lógico vs. Exclusão Física

Para entidades comunitárias (como clubes em `public.user_clubs`), adota-se o **arquivamento lógico** (`archived_at TIMESTAMP WITH TIME ZONE`):
- O registro deixa de ser retornado em listagens públicas e na vitrine do aplicativo;
- URLs diretas deixam de exibir detalhes para visitantes comuns;
- O histórico referencial de interações passadas é preservado sem quebrar constraints de chave estrangeira existentes.
