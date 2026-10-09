# Relatório de replay local — baseline da comunidade

**Data:** 2026-10-09
**Projeto:** `/home/ubuntu/diyspur`
**Escopo:** corrigir o caminho de replay local bloqueado por `42803` em `supabase/migrations/20261008214920_add_community_reading_views.sql:127/145`, sem editar a migration histórica aplicada; criar overlay/bootstrap descartável e contrato SQL executável.
**Fora do escopo:** remoto/produção, frontend, handlers Edge, quiz, newsletter, harness `scripts/security-smoke`, seeds remotos e qualquer `migration repair`.

## Veredito

**PASS — replay reduzido reproduz o defeito histórico e passa com overlay corretivo.** O arquivo histórico permanece intacto. O ambiente desta execução não possui Docker, portanto o resultado é **PGlite reduzido, não um reset/replay full do Supabase**.

A falha original é real e foi mantida como evidência: o SELECT do view projeta `s.title as current_season_title`, mas o `GROUP BY` usa `current_season.title`. PostgreSQL rejeita a definição com `42803` (`column "s.title" must appear in the GROUP BY clause or be used in an aggregate function`). A correção de replay usa `current_season.title` no SELECT; o alias `cs.title` da migration contratual posterior também é aceito pelo teste SQL.

## Artefatos

| Arquivo | Finalidade |
|---|---|
| [`scripts/replay-local.sh`](../../scripts/replay-local.sh) | Entrada executável local. Em `auto`, escolhe full somente com Docker alcançável; sem Docker chama PGlite. `--full` nunca usa remoto: opera em cópia temporária e `supabase db reset --local`. |
| [`scripts/replay-local.mjs`](../../scripts/replay-local.mjs) | Runner PGlite reduzido. Reproduz a migration original em uma instância descartável, espera `42803`, e depois aplica o overlay em outra instância. |
| [`scripts/replay-local.bootstrap.sql`](../../scripts/replay-local.bootstrap.sql) | Schema mínimo de scratch para as relações exigidas pelas migrations de reviews/contexto/view; não é migration de produto. |
| [`scripts/replay-local.overlay.sql`](../../scripts/replay-local.overlay.sql) | Definição corrigida de `v_club_progress_panel`, aplicada somente no pipeline scratch. |
| [`supabase/tests/sdd_contract.test.sql`](../../supabase/tests/sdd_contract.test.sql) | Asserções SQL executáveis por `psql` ou `supabase db query --local --file`; não cria fixtures nem altera schema. |

## Estratégia de ordenação, sem duplicar histórico

1. O runner cria uma base PGlite nova e aplica apenas o bootstrap scratch e as duas prerequisites reais (`20261008214832_add_book_reviews.sql` e `20261008214847_add_user_club_reading_context.sql`).
2. Em uma primeira instância, executa **o texto original completo**. Isso reproduz o bloqueio `42803`; a mensagem não é mascarada.
3. Em uma segunda instância, divide o texto original em três trechos por marcadores estáveis:
   - prefixo histórico, até antes do `CREATE VIEW` defeituoso;
   - overlay corretivo, no mesmo ponto lógico da sequência;
   - sufixo histórico, a partir da função de snapshot.
4. O bloco histórico defeituoso não é executado duas vezes. O overlay é a substituição explícita desse único bloco; o sufixo continua sendo o texto histórico. Nenhuma linha de `supabase_schema_migrations` é inserida, nenhum timestamp aplicado é reescrito e nenhum arquivo de migration é editado.
5. O runner insere somente dados sintéticos na instância descartável, atualiza a materialized view e executa o contrato SQL. O teste confirma título da temporada atual, contagens e percentual agregado.

No modo Docker, o wrapper copia `supabase/` para um diretório temporário, troca apenas a ocorrência conhecida de `s.title as current_season_title` nessa cópia e executa `supabase db reset --local --no-seed`. A migration rastreada não muda; o stack é local/descartável e o wrapper não aceita `--linked` nem `--db-url`.

## Execução desta sessão

Comando:

```bash
cd /home/ubuntu/diyspur
scripts/replay-local.sh --reduced
```

Resultado observado:

```text
PASS: untouched migration reproduces the known 42803 at the club view
PASS: replay overlay runs before the historical snapshot suffix
PASS: view returns the current season title and aggregated progress
PASS: supabase/tests/sdd_contract.test.sql
RESULT: REDUCED PGlite replay PASS (not a full Supabase/Docker reset)
```

Também foi verificado que o ambiente não tem `docker`/daemon alcançável; o PGlite existente em `scripts/security-smoke/node_modules` foi reutilizado. O teste não prova Auth, RLS efetivo sob JWT, Storage, Realtime, extensões/serviços Supabase ou comportamento do banco hospedado.

## Limitações e próximos passos

- O resultado reduzido não substitui `supabase db reset` com PostgreSQL/Supabase completo. Quando Docker estiver disponível, executar `scripts/replay-local.sh --full` e preservar o log inteiro; falhas posteriores devem ser reportadas separadamente, não atribuídas automaticamente ao `42803`.
- Não aplicar o overlay no remoto e não transformar `scripts/replay-local.overlay.sql` em migration de produção: o remoto já possui histórico aplicado e a correção aqui é uma adaptação de baseline/replay.
- O contrato SQL valida objetos e a forma corrigida do view; não é o harness de autorização A/B e não valida os handlers fora do escopo desta entrega.
