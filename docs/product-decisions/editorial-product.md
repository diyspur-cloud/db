# Decisões de produto — clubes, diário e listas

## ADR-01 — Clubes

- Clube público permite entrada direta; clube privado exige convite.
- `user_clubs.owner_id` é a única autoridade. O papel `owner` na membership é reflexo.
- O owner não pode sair; deve transferir autoridade em uma evolução posterior ou arquivar o clube.
- Convites são direcionados a usuários já cadastrados por UUID validado no servidor; não há busca de e-mail nem envio automático nesta entrega.
- A criação usa UUID de requisição como chave de idempotência e RPC transacional.

## ADR-02 — Diário

- Todo registro nasce privado, mesmo quando contém spoiler.
- A primeira entrega não habilita compartilhamento editorial por clube: o banco remove a exposição de `club` sem `shared_club_id` válido.
- Páginas, percentual e minutos são opcionais; o sistema não inventa valores nem deduz conclusão/XP do texto.
- Anexos continuam dependentes do bucket privado já existente e de validação Storage em staging.

## ADR-07 — Listas

- A versão da lista funciona como controle otimista de concorrência.
- Reordenação deve ocorrer por RPC, bloqueando a linha da lista pai e validando o conjunto completo de itens.
- `unlisted` não é tratado como senha nem como compartilhamento seguro por slug.

## Gates antes de produção

- Aplicar a migration apenas em staging após reconciliar o histórico remoto.
- Regenerar `src/types/database.ts` depois do apply e substituir as fronteiras temporárias `as any` em actions/queries.
- Executar Auth/RLS com titular A, titular B, membro de clube privado, owner e usuário anônimo.
- Validar Storage, Realtime, concorrência e rollback; esta alteração não faz `db push` nem altera o Supabase remoto.
