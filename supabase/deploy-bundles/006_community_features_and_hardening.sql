-- >>> 20261008214832_add_book_reviews.sql
-- Avaliações comunitárias. A tabela é nova; não altera dados existentes.
-- RLS é habilitada antes de conceder acesso pela Data API.
create table public.book_reviews (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  rating numeric(3,2) check (rating is null or rating between 0 and 5),
  spice_level integer check (spice_level is null or spice_level between 0 and 5),
  review_text text check (review_text is null or length(review_text) <= 20000),
  contains_spoilers boolean not null default false,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint book_reviews_one_per_user_book unique (book_id, user_id)
);

create index book_reviews_book_created_idx
  on public.book_reviews (book_id, created_at desc);
create index book_reviews_user_created_idx
  on public.book_reviews (user_id, created_at desc);

alter table public.book_reviews enable row level security;

create policy book_reviews_read_active_or_owner
  on public.book_reviews for select to anon, authenticated
  using (
    deleted_at is null
    or user_id = (select auth.uid())
    or (select public.is_admin())
  );

create policy book_reviews_owner_write
  on public.book_reviews for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy book_reviews_admin_all
  on public.book_reviews for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

grant select on table public.book_reviews to anon;
grant select, insert, update, delete on table public.book_reviews to authenticated;
grant select, insert, update, delete on table public.book_reviews to service_role;

-- >>> 20261008214847_add_user_club_reading_context.sql
-- Contexto de leitura do clube; os campos são opcionais para preservar os clubes atuais.
alter table public.user_clubs
  add column current_book_id uuid references public.books(id) on delete set null,
  add column current_season_id uuid references public.seasons(id) on delete set null,
  add column current_started_at timestamptz,
  add column current_ends_at timestamptz;

create index user_clubs_current_book_idx
  on public.user_clubs (current_book_id)
  where current_book_id is not null;
create index user_clubs_current_season_idx
  on public.user_clubs (current_season_id)
  where current_season_id is not null;

-- >>> 20261008214859_restore_missing_rls_policies.sql
-- As três tabelas já tinham RLS habilitado, mas estavam sem policies.
-- A leitura de votos é restrita ao titular: permitir SELECT público na tabela
-- revelaria user_id e option_idx, e não apenas as contagens agregadas.

create policy meeting_rsvps_read_owner_or_admin
  on public.meeting_rsvps for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select public.is_admin())
  );
create policy meeting_rsvps_owner_write
  on public.meeting_rsvps for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy host_prompt_votes_read_owner
  on public.host_prompt_votes for select to authenticated
  using (user_id = (select auth.uid()));
create policy host_prompt_votes_owner_write
  on public.host_prompt_votes for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy user_challenges_read_owner_or_admin
  on public.user_challenges for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select public.is_admin())
  );
create policy user_challenges_owner_write
  on public.user_challenges for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- >>> 20261008214920_add_community_reading_views.sql
-- Funções internas de agregação. O schema private não deve ser incluído nas
-- schemas expostas pela Data API. Estas funções retornam apenas totais, nunca
-- IDs de leitores ou linhas de votos.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated, service_role;

create or replace function private.get_chapter_audience(p_chapter_id uuid)
returns table (
  finished_count bigint,
  reading_count bigint,
  not_started_count bigint,
  avg_percent numeric
)
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select
    count(*) filter (where p.status = 'read'),
    count(*) filter (where p.status = 'reading'),
    count(*) filter (where p.status = 'want_to_read'),
    round(avg(p.percent)::numeric, 2)
  from public.user_progress as p
  where p.chapter_id = p_chapter_id;
$$;

create or replace function private.get_host_prompt_aggregate(p_prompt_id uuid)
returns table (
  option_0_count bigint,
  option_1_count bigint,
  option_2_count bigint,
  total_votes bigint
)
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select
    count(*) filter (where v.option_idx = 0),
    count(*) filter (where v.option_idx = 1),
    count(*) filter (where v.option_idx = 2),
    count(*)
  from public.host_prompt_votes as v
  where v.prompt_id = p_prompt_id;
$$;

grant execute on function private.get_chapter_audience(uuid)
  to anon, authenticated, service_role;
grant execute on function private.get_host_prompt_aggregate(uuid)
  to anon, authenticated, service_role;

-- Recria a view de público por capítulo sem permitir acesso às linhas pessoais
-- de user_progress. A saída continua contendo somente métricas agregadas.
create or replace view public.v_chapter_audience
with (security_invoker = true)
as
select
  c.id as chapter_id,
  c.season_id,
  a.finished_count,
  a.reading_count,
  a.not_started_count,
  a.avg_percent
from public.chapters as c
cross join lateral private.get_chapter_audience(c.id) as a;

-- Mantém contagens públicas de enquetes, mas não expõe votos individualizados.
create or replace view public.v_host_prompt_results
with (security_invoker = true)
as
select
  hp.id as prompt_id,
  hp.chapter_id,
  hp.question,
  hp.options,
  a.option_0_count,
  a.option_1_count,
  a.option_2_count,
  a.total_votes
from public.host_prompts as hp
cross join lateral private.get_host_prompt_aggregate(hp.id) as a;

-- Resumo público, limitado a agregados por livro.
create materialized view public.mv_book_community_stats as
select
  b.id as book_id,
  b.title,
  coalesce(bms.mood_counts, '{}'::jsonb) as mood_counts,
  coalesce(bms.pace_percent, '{"slow":0,"medium":0,"fast":0}'::jsonb) as pace_percent,
  bms.plot_vs_character_avg,
  bms.sample_size as mood_sample_size,
  count(br.id) filter (where br.deleted_at is null) as review_count,
  round(avg(br.rating) filter (where br.deleted_at is null), 2) as avg_rating,
  round(avg(br.spice_level) filter (where br.deleted_at is null), 2) as avg_spice
from public.books as b
left join public.book_mood_stats as bms on bms.book_id = b.id
left join public.book_reviews as br on br.book_id = b.id
  and br.deleted_at is null
group by b.id, b.title, bms.mood_counts, bms.pace_percent,
         bms.plot_vs_character_avg, bms.sample_size;

create unique index mv_book_community_stats_book_id_idx
  on public.mv_book_community_stats (book_id);

grant select on public.mv_book_community_stats to anon, authenticated, service_role;

create or replace view public.v_book_community_stats
with (security_invoker = true)
as
select * from public.mv_book_community_stats;
grant select on public.v_book_community_stats to anon, authenticated, service_role;

-- O resumo do clube respeita RLS das tabelas subjacentes: cada membro só
-- contribui com as linhas de progresso que tem permissão de ler.
create or replace view public.v_club_progress_panel
with (security_invoker = true)
as
select
  uc.id as club_id,
  uc.name as club_name,
  uc.current_book_id,
  b.title as current_book_title,
  uc.current_season_id,
  s.title as current_season_title,
  uc.current_started_at,
  uc.current_ends_at,
  count(distinct up.user_id) filter (where s.id is not null) as distinct_readers,
  count(*) filter (where s.id is not null and up.status = 'read') as chapters_read,
  count(*) filter (where s.id is not null and up.status = 'reading') as chapters_in_progress,
  round(avg(up.percent) filter (where s.id is not null), 2) as avg_percent
from public.user_clubs as uc
join public.user_club_members as ucm on ucm.club_id = uc.id
left join public.books as b on b.id = uc.current_book_id
left join public.seasons as current_season on current_season.id = uc.current_season_id
left join public.user_progress as up on up.user_id = ucm.user_id
left join public.chapters as c on c.id = up.chapter_id
left join public.seasons as s on s.id = c.season_id
  and s.book_id = uc.current_book_id
  and (uc.current_season_id is null or s.id = uc.current_season_id)
where uc.current_book_id is not null
group by uc.id, uc.name, uc.current_book_id, b.title,
         uc.current_season_id, current_season.title,
         uc.current_started_at, uc.current_ends_at;

grant select on public.v_club_progress_panel to anon, authenticated, service_role;

-- Snapshot sempre passa pelo RLS do invocador, e um JWT de usuário não pode
-- solicitar o histórico de outro user_id. service_role/backend confiável pode
-- calcular embeddings sob seu próprio contrato.
create or replace function public.build_user_reading_snapshot(p_user uuid)
returns text
language sql
stable
security invoker
set search_path = pg_catalog, public
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'book_id', b.id,
        'book_title', b.title,
        'status', up.status,
        'percent', up.percent,
        'moods', bmv.moods,
        'pace', bmv.pace,
        'review', br.review_text,
        'rating', br.rating
      ) order by b.title
    )::text,
    '[]'
  )
  from public.user_progress as up
  join public.chapters as c on c.id = up.chapter_id
  join public.seasons as s on s.id = c.season_id
  join public.books as b on b.id = s.book_id
  left join public.book_mood_votes as bmv
    on bmv.book_id = b.id and bmv.user_id = up.user_id
  left join public.book_reviews as br
    on br.book_id = b.id and br.user_id = up.user_id and br.deleted_at is null
  where up.user_id = p_user
    and (auth.uid() is null or auth.uid() = p_user);
$$;
revoke all on function public.build_user_reading_snapshot(uuid) from public, anon;
grant execute on function public.build_user_reading_snapshot(uuid)
  to authenticated, service_role;

-- >>> 20261008215009_harden_views_and_functions.sql
-- Views passam a respeitar os privilégios e RLS do chamador.
-- v_chapter_audience e v_host_prompt_results usam agregadores estreitos em
-- private, definidos na migration imediatamente anterior.
alter view public.v_chapter_audience set (security_invoker = true);
alter view public.v_season_ranking set (security_invoker = true);
alter view public.v_comments_visible set (security_invoker = true);
alter view public.v_host_prompt_results set (security_invoker = true);
alter view public.v_video_timed_comment_stats set (security_invoker = true);
alter view public.v_user_reading_overview set (security_invoker = true);
alter view public.v_feed_post_counters set (security_invoker = true);
alter view public.v_book_community_stats set (security_invoker = true);
alter view public.v_club_progress_panel set (security_invoker = true);

-- Reduzir ACL de tabelas privadas. RLS permanece como segunda camada de controle.
revoke all on table public.meeting_rsvps, public.host_prompt_votes,
  public.user_challenges from anon;
revoke insert, update, delete on table public.book_reviews from anon;
grant select on table public.book_reviews to anon;

-- Fixar search_path das funções de aplicação encontradas na auditoria.
alter function public.is_admin() set search_path = pg_catalog, public;
alter function public.handle_new_user() set search_path = pg_catalog, public;
alter function public.award_xp(uuid, public.xp_source, integer, uuid)
  set search_path = pg_catalog, public;
alter function public.bump_comment_likes() set search_path = pg_catalog, public;
alter function public.bump_comment_replies() set search_path = pg_catalog, public;
alter function public.touch_streak() set search_path = pg_catalog, public;
alter function public.match_books(public.vector, double precision, integer)
  set search_path = pg_catalog, public;
alter function public.get_reader_matches(uuid, integer)
  set search_path = pg_catalog, public;
alter function public.refresh_user_quiz_averages()
  set search_path = pg_catalog, public;
alter function public.refresh_chapter_quiz_averages()
  set search_path = pg_catalog, public;
alter function public.refresh_book_mood_stats(uuid)
  set search_path = pg_catalog, public;
alter function public.trg_refresh_book_mood_stats()
  set search_path = pg_catalog, public;
alter function public.refresh_content_warning_votes()
  set search_path = pg_catalog, public;
alter function public.bump_feed_post_counters()
  set search_path = pg_catalog, public;
alter function public.bump_journal_likes()
  set search_path = pg_catalog, public;
alter function public.generate_milestones_for_season(uuid)
  set search_path = pg_catalog, public;
alter function public.refresh_reading_goal_progress()
  set search_path = pg_catalog, public;
alter function public.match_readers(public.vector, double precision, integer, uuid)
  set search_path = pg_catalog, public;

-- O trigger wrapper executa com o owner confiável para poder invocar o helper
-- de agregação que deixa de ser exposto ao cliente.
create or replace function public.trg_refresh_book_mood_stats()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform public.refresh_book_mood_stats(coalesce(new.book_id, old.book_id));
  return null;
end;
$$;

-- Nenhuma role de cliente pode conceder XP ou acionar helpers SECURITY DEFINER.
-- Edge Functions devem invocar award_xp com uma sessão service_role separada.
revoke execute on function public.award_xp(uuid, public.xp_source, integer, uuid)
  from public, anon, authenticated;
grant execute on function public.award_xp(uuid, public.xp_source, integer, uuid)
  to service_role;

revoke execute on function public.generate_milestones_for_season(uuid)
  from public, anon, authenticated;
grant execute on function public.generate_milestones_for_season(uuid)
  to service_role;

revoke execute on function public.refresh_book_mood_stats(uuid)
  from public, anon, authenticated;
grant execute on function public.refresh_book_mood_stats(uuid)
  to service_role;

revoke execute on function public.handle_new_user()
  from public, anon, authenticated;
revoke execute on function public.refresh_user_quiz_averages()
  from public, anon, authenticated;
revoke execute on function public.refresh_chapter_quiz_averages()
  from public, anon, authenticated;
revoke execute on function public.refresh_content_warning_votes()
  from public, anon, authenticated;
revoke execute on function public.refresh_reading_goal_progress()
  from public, anon, authenticated;
revoke execute on function public.rls_auto_enable()
  from public, anon, authenticated;
revoke execute on function public.trg_refresh_book_mood_stats()
  from public, anon, authenticated;

-- >>> 20261008215045_index_uncovered_foreign_keys.sql
-- Gera índice B-tree quando os atributos da FK não são cobertos pelo prefixo
-- de nenhuma chave de índice completa e válida. O catálogo auditado apontou
-- 63 FKs sem índice no estado anterior a esta migration.
-- São índices aditivos: não alteram linhas nem constraints.
do $$
declare
  fk record;
begin
  for fk in
    select
      c.conrelid,
      c.conname,
      c.conkey,
      string_agg(format('%I', a.attname), ', ' order by k.ord) as columns_sql
    from pg_constraint as c
    join pg_namespace as n on n.oid = c.connamespace
    cross join lateral unnest(c.conkey) with ordinality as k(attnum, ord)
    join pg_attribute as a
      on a.attrelid = c.conrelid and a.attnum = k.attnum
    where c.contype = 'f'
      and n.nspname = 'public'
      and not exists (
        select 1
        from pg_index as i
        where i.indrelid = c.conrelid
          and i.indisvalid
          and i.indisready
          and i.indpred is null
          and i.indnkeyatts >= cardinality(c.conkey)
          and (
            select array_agg(x.attnum::smallint order by x.ord)
            from unnest(i.indkey::smallint[]) with ordinality as x(attnum, ord)
            where x.ord <= cardinality(c.conkey)
          ) = c.conkey
      )
    group by c.conrelid, c.conname, c.conkey
    order by c.conrelid::regclass::text, c.conname
  loop
    execute format(
      'create index if not exists %I on %s (%s)',
      'idx_fk_' || substr(md5(fk.conrelid::regclass::text || ':' || fk.conname), 1, 24),
      fk.conrelid::regclass,
      fk.columns_sql
    );
  end loop;
end;
$$;

-- >>> 20261008215117_optimize_rls_auth_initplans.sql
-- Captura auth.uid() em um initplan por statement, evitando reavaliação por
-- linha. A expressão lógica das policies é preservada; a única policy baseada
-- em auth.role() é normalizada para TO authenticated, com o mesmo público-alvo.
do $$
declare
  p record;
  role_sql text;
  using_sql text;
  check_sql text;
  ddl text;
begin
  for p in
    select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
    from pg_policies
    where schemaname = 'public'
      and (
        (coalesce(qual, '') ~ 'auth\.uid\(\)'
          and coalesce(qual, '') !~ '\(select auth\.uid\(\)\)')
        or
        (coalesce(with_check, '') ~ 'auth\.uid\(\)'
          and coalesce(with_check, '') !~ '\(select auth\.uid\(\)\)')
        or (tablename = 'quiz_questions' and policyname = 'quiz_q_read_auth')
      )
    order by schemaname, tablename, policyname
  loop
    select string_agg(quote_ident(r), ', ' order by r)
      into role_sql
      from unnest(p.roles) as roles(r);

    using_sql := p.qual;
    check_sql := p.with_check;

    if p.tablename = 'quiz_questions' and p.policyname = 'quiz_q_read_auth' then
      role_sql := 'authenticated';
      using_sql := 'true';
      check_sql := null;
    else
      using_sql := case when using_sql is null then null else
        regexp_replace(using_sql, 'auth\.uid\(\)', '(select auth.uid())', 'g') end;
      check_sql := case when check_sql is null then null else
        regexp_replace(check_sql, 'auth\.uid\(\)', '(select auth.uid())', 'g') end;
    end if;

    execute format('drop policy %I on %I.%I', p.policyname, p.schemaname, p.tablename);

    ddl := format(
      'create policy %I on %I.%I as %s for %s to %s',
      p.policyname, p.schemaname, p.tablename,
      lower(p.permissive), lower(p.cmd), role_sql
    );
    if using_sql is not null then
      ddl := ddl || format(' using (%s)', using_sql);
    end if;
    if check_sql is not null then
      ddl := ddl || format(' with check (%s)', check_sql);
    end if;
    execute ddl;
  end loop;
end;
$$;

-- >>> 20261008215324_harden_community_data_access.sql
-- O materialized view é detalhe de implementação. A API pública usa apenas a
-- view v_book_community_stats; mover o MV para private evita exposição direta.
alter materialized view public.mv_book_community_stats set schema private;
revoke all on table private.mv_book_community_stats from public, anon, authenticated, service_role;
grant select on table private.mv_book_community_stats to anon, authenticated, service_role;

-- RSVP e progresso: leitura própria/admin; escrita própria. Comandos separados
-- evitam que policy FOR ALL sobreponha a policy SELECT e preservam o limite de
-- privilégio administrativo definido anteriormente.
drop policy if exists meeting_rsvps_read_owner_or_admin on public.meeting_rsvps;
drop policy if exists meeting_rsvps_owner_write on public.meeting_rsvps;
create policy meeting_rsvps_read_owner_or_admin
  on public.meeting_rsvps for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy meeting_rsvps_insert_owner
  on public.meeting_rsvps for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy meeting_rsvps_update_owner
  on public.meeting_rsvps for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy meeting_rsvps_delete_owner
  on public.meeting_rsvps for delete to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists host_prompt_votes_read_owner on public.host_prompt_votes;
-- Esta policy única cobre leitura e escrita do próprio usuário, sem duplicidade.
drop policy if exists host_prompt_votes_owner_write on public.host_prompt_votes;
create policy host_prompt_votes_owner_all
  on public.host_prompt_votes for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists user_challenges_read_owner_or_admin on public.user_challenges;
drop policy if exists user_challenges_owner_write on public.user_challenges;
create policy user_challenges_read_owner_or_admin
  on public.user_challenges for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy user_challenges_insert_owner
  on public.user_challenges for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy user_challenges_update_owner
  on public.user_challenges for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy user_challenges_delete_owner
  on public.user_challenges for delete to authenticated
  using (user_id = (select auth.uid()));

-- Avaliações: uma policy de leitura pública para conteúdo ativo e policies de
-- escrita próprias/admin, sem sobrepor as quatro ações no papel authenticated.
drop policy if exists book_reviews_read_active_or_owner on public.book_reviews;
drop policy if exists book_reviews_owner_write on public.book_reviews;
drop policy if exists book_reviews_admin_all on public.book_reviews;
create policy book_reviews_read_active_or_owner
  on public.book_reviews for select to anon, authenticated
  using (
    deleted_at is null
    or user_id = (select auth.uid())
    or (select public.is_admin())
  );
create policy book_reviews_insert_owner_or_admin
  on public.book_reviews for insert to authenticated
  with check (
    user_id = (select auth.uid())
    or (select public.is_admin())
  );
create policy book_reviews_update_owner_or_admin
  on public.book_reviews for update to authenticated
  using (
    user_id = (select auth.uid())
    or (select public.is_admin())
  )
  with check (
    user_id = (select auth.uid())
    or (select public.is_admin())
  );
create policy book_reviews_delete_owner_or_admin
  on public.book_reviews for delete to authenticated
  using (
    user_id = (select auth.uid())
    or (select public.is_admin())
  );

-- >>> 20261008215751_drop_duplicate_video_timed_comments_index.sql
-- vtc_sec_idx era estruturalmente idêntico a vtc_chapter_sec_idx.
-- Mantém-se o índice com nome de domínio explícito e remove-se a cópia exata.
drop index if exists public.vtc_sec_idx;

-- >>> 20261008220410_schedule_book_stats_refresh.sql
-- A extensão cria seu schema cron; não a force para extensions.
create extension if not exists pg_cron;

-- Mantém o cache de estatísticas atualizado sem bloquear leituras da view.
-- O índice único em book_id permite REFRESH ... CONCURRENTLY.
select cron.schedule(
  'refresh-mv-book-community-stats',
  '0 */6 * * *',
  'refresh materialized view concurrently private.mv_book_community_stats;'
);
