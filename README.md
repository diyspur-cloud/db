

## Release de hardening da auditoria — 2026-10-10

A branch `fix/auditoria-20261010` contém as correções de banco e Edge Function correspondentes aos achados A01, A02, A03, A39, A40, A41 e A42 do relatório de auditoria.

### Migrations desta release

| Arquivo | Responsabilidade |
|---|---|
| `20261011000100_harden_chapter_writes_and_comments.sql` | Policies de disponibilidade, RPCs de edição/remoção própria, trigger monotônico de progresso, spoiler de comentários temporizados, metadata pública de temporada e revogação de DML direto em clubes. |
| `20261011000200_fix_reading_list_item_counts.sql` | Backfill de `reading_lists.items_count` e trigger atômico para insert/update/delete/movimentação de itens. |

### Regras de autorização

- `private.can_view_chapter(chapter_id)` é a regra comum de publicação e gate de quiz.
- `user_progress`, `comments` e `video_timed_comments` só aceitam novas escritas em capítulos disponíveis.
- `auth.uid()` é a única fonte de identidade; nenhum `user_id` enviado pelo frontend é autoridade.
- `remove_own_chapter_comment` só altera comentário do autor e retorna `false` quando não há correspondência.
- `get_own_chapter_comment_for_edit` não expõe conteúdo mascarado nem conteúdo de outro usuário.
- `get_visible_video_timed_comments` retorna `NULL` para conteúdo de spoiler abaixo do percentual mínimo.
- `user_clubs` e `user_club_members` não aceitam DML direto de `anon`/`authenticated`; criação, entrada, saída e edição usam RPCs com invariantes.

### Aplicação controlada

Antes de aplicar em produção:

```bash
export SUPABASE_PROJECT_REF=xjhehhfhhoomblcggjpk
supabase link --project-ref "$SUPABASE_PROJECT_REF"
supabase migration list --project-ref "$SUPABASE_PROJECT_REF"
supabase db push --project-ref "$SUPABASE_PROJECT_REF"
```

A aplicação deve ser feita após:

1. revisão do SQL e `git diff --check`;
2. replay em staging ou banco descartável;
3. verificação de que não existe migration remota equivalente com outro nome;
4. inspeção de policies, grants, triggers e funções existentes;
5. backup/ponto de restauração aprovado para o ambiente;
6. aplicação em janela controlada;
7. verificação da migration no histórico remoto;
8. smoke test das RPCs e da Edge Function.

Não use `db reset --linked`, `migration repair` ou edição retroativa de migrations aplicadas.

### Edge Function `quiz-validate`

A função agora diferencia:

- `invalid_payload` — JSON, UUID ou estrutura inválida;
- `incomplete_answers` — quantidade de respostas diferente da quantidade publicada;
- `unexpected_answers` — questão de outro capítulo ou ID inesperado;
- `invalid_quiz_configuration_or_answer` — alternativa fora do conjunto publicado ou configuração editorial inválida.

O servidor continua preenchendo respostas ausentes apenas para o contrato interno legado; o endpoint público não aceita mais o payload incompleto. A chave de idempotência continua obrigatória para retries confiáveis e o score/gabarito não é confiado ao cliente.

### Verificação SQL mínima pós-apply

Execute somente em ambiente autorizado e com limite explícito quando aplicável:

```sql
select version, name
from supabase_migrations.schema_migrations
order by version desc
limit 20;

select proname
from pg_proc
where proname in (
  'remove_own_chapter_comment',
  'get_own_chapter_comment_for_edit',
  'get_visible_video_timed_comments',
  'get_season_chapter_access'
)
limit 20;
```

Em seguida valide com identidades separadas:

- visitante sem sessão;
- autor do comentário/progresso;
- outra conta autenticada;
- administrador.

Não inclua JWT, senha, conteúdo privado ou payload completo nos logs de evidência.

### Rollback e recuperação

As migrations são incrementais e não devem ser apagadas. Se uma migration falhar antes do commit, corrija o SQL e aplique uma nova versão. Se o apply terminar e houver comportamento incorreto:

1. interrompa o rollout do frontend;
2. preserve o erro/correlation ID e o estado remoto;
3. crie migration corretiva explícita;
4. restaure o alias Vercel anterior se necessário;
5. repita o smoke test com contas isoladas.

A remoção de uma policy ou função em produção não deve ser usada como rollback improvisado, pois pode ampliar acesso ou quebrar consumidores.

### Estado da release

- Migration e Edge Function: versionadas na branch de hardening.
- Frontend: contrato TypeScript e consumidores atualizados na branch correspondente.
- Validação local do frontend: typecheck, lint, 13 testes unitários e build aprovados.
- Aplicação remota: registrar aqui o timestamp/versão retornado pelo projeto Supabase após o apply.
- Aceite end-to-end: registrar aqui data, deployment Vercel, rotas verificadas e matriz de identidades utilizada.
