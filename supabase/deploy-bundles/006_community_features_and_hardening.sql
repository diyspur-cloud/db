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

-- >>> 20261008225152_harden_core_authorization.sql
-- Core authorization hardening based on live audit (2026-10-08).
-- Data-preserving except normalization of legacy NULL spoiler thresholds.
-- feed-media was verified empty before it is made private.

-- 1) Profiles: expose only an intentional public projection; role/consent/PII
-- are never directly selectable or updatable by anon/authenticated.
revoke all privileges on table public.profiles from public, anon, authenticated;
grant select (id, username, display_name, avatar_url, bio, level, created_at)
  on table public.profiles to anon, authenticated;
grant insert (id, username, display_name) on table public.profiles to authenticated;
grant update (username, display_name, avatar_url, bio, level)
  on table public.profiles to authenticated;

drop policy if exists profiles_select_all on public.profiles;
create policy profiles_select_public_fields on public.profiles
  for select to anon, authenticated using (true);
drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

create or replace view public.v_profiles_public
with (security_invoker = true, security_barrier = true) as
select id, username, display_name, avatar_url, bio, level, created_at
from public.profiles;
revoke all privileges on table public.v_profiles_public from public, anon, authenticated;
grant select on table public.v_profiles_public to anon, authenticated;

create or replace function public.get_my_profile_private()
returns table (whatsapp text, lgpd_consent boolean,
               lgpd_consent_at timestamptz, onboarding_done boolean)
language sql stable security definer set search_path = ''
as $$
  select p.whatsapp, p.lgpd_consent, p.lgpd_consent_at, p.onboarding_done
  from public.profiles p
  where p.id = (select auth.uid()) and (select auth.uid()) is not null;
$$;
revoke all on function public.get_my_profile_private() from public, anon;
grant execute on function public.get_my_profile_private() to authenticated;

create or replace function public.set_my_lgpd_consent(p_consent boolean)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  update public.profiles
     set lgpd_consent = p_consent,
         lgpd_consent_at = case when p_consent then statement_timestamp() else null end,
         updated_at = statement_timestamp()
   where id = (select auth.uid());
  if not found then raise exception 'profile not found' using errcode = 'P0002'; end if;
end;
$$;
revoke all on function public.set_my_lgpd_consent(boolean) from public, anon;
grant execute on function public.set_my_lgpd_consent(boolean) to authenticated;

-- 2) Chapter comments: direct access omits content; the guarded view returns
-- NULL text until the reader's self-reported progress reaches min_percent.
update public.comments set min_percent = case when is_spoiler then 100 else 0 end
where min_percent is null;
alter table public.comments alter column min_percent set default 0;
alter table public.comments alter column min_percent set not null;
do $$ begin
  if not exists (select 1 from pg_constraint where conrelid='public.comments'::regclass
                 and conname='comments_min_percent_range_check') then
    alter table public.comments add constraint comments_min_percent_range_check
      check (min_percent between 0 and 100) not valid;
  end if;
end $$;
alter table public.comments validate constraint comments_min_percent_range_check;
revoke all privileges on table public.comments from public, anon, authenticated;
grant select (id, chapter_id, user_id, parent_id, is_spoiler, min_percent,
              likes_count, replies_count, edited_at, deleted_at, created_at)
  on table public.comments to anon, authenticated;
grant insert (chapter_id, user_id, parent_id, content, is_spoiler, min_percent)
  on table public.comments to authenticated;
grant update (content, is_spoiler, min_percent, edited_at, deleted_at)
  on table public.comments to authenticated;
grant delete on table public.comments to authenticated;
drop policy if exists comments_read on public.comments;
create policy comments_read_active on public.comments
  for select to anon, authenticated using (deleted_at is null);
drop policy if exists comments_insert_auth on public.comments;
create policy comments_insert_own on public.comments
  for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists comments_update_own on public.comments;
create policy comments_update_own on public.comments
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
drop policy if exists comments_delete_own_or_admin on public.comments;
create policy comments_delete_own_or_admin on public.comments
  for delete to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));
create or replace function private.get_visible_comments()
returns table (id uuid, chapter_id uuid, user_id uuid, parent_id uuid,
               created_at timestamptz, likes_count integer, replies_count integer,
               is_spoiler boolean, content text, is_locked boolean)
language sql stable security definer set search_path = ''
as $$
  select c.id, c.chapter_id, c.user_id, c.parent_id, c.created_at,
         c.likes_count, c.replies_count, c.is_spoiler,
         case when c.is_spoiler and coalesce(up.percent,0)<coalesce(c.min_percent,100)
              then null::text else c.content end,
         (c.is_spoiler and coalesce(up.percent,0)<coalesce(c.min_percent,100))
  from public.comments c
  left join public.user_progress up on up.chapter_id=c.chapter_id
    and up.user_id=(select auth.uid())
  where c.deleted_at is null;
$$;
revoke all on function private.get_visible_comments() from public;
grant usage on schema private to anon, authenticated;
grant execute on function private.get_visible_comments() to anon, authenticated;
create or replace view public.v_comments_visible
with (security_invoker = true, security_barrier = true) as
select * from private.get_visible_comments();
revoke all privileges on table public.v_comments_visible from public, anon, authenticated;
grant select on table public.v_comments_visible to anon, authenticated;

-- 3) Centralized private authorization predicates. SECURITY DEFINER is
-- intentional: policies/views need to inspect protected parent/membership rows.
create or replace function private.can_view_feed_post(p_post_id uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.feed_posts p
    where p.id=p_post_id and p.deleted_at is null
      and (p.visibility='public' or p.author_id=(select auth.uid())
        or (p.visibility='followers' and exists (
          select 1 from public.follows f where f.follower_id=(select auth.uid())
            and f.followed_id=p.author_id and f.status='accepted'))
        or (p.visibility='club' and exists (
          select 1 from public.user_club_members m where m.club_id=p.club_id
            and m.user_id=(select auth.uid())))
      )
  );
$$;
revoke all on function private.can_view_feed_post(uuid) from public;
grant usage on schema private to anon, authenticated;
grant execute on function private.can_view_feed_post(uuid) to anon, authenticated;

create or replace function private.can_edit_reading_list(p_list_id uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null and exists (
    select 1 from public.reading_lists l where l.id=p_list_id
      and (l.owner_id=(select auth.uid()) or (l.is_collaborative and exists (
        select 1 from public.reading_list_collaborators c
        where c.list_id=l.id and c.user_id=(select auth.uid()) and c.can_edit)))
  );
$$;
revoke all on function private.can_edit_reading_list(uuid) from public, anon;
grant execute on function private.can_edit_reading_list(uuid) to authenticated;

-- Feed post spoiler payload is available only from this security-barrier view.
revoke all privileges on table public.feed_posts from public, anon, authenticated;
grant select (id, author_id, kind, visibility, club_id, book_id, chapter_id,
              season_id, is_spoiler, min_percent, likes_count, comments_count,
              shares_count, deleted_at, created_at, updated_at)
  on table public.feed_posts to anon, authenticated;
grant insert (author_id, kind, visibility, club_id, book_id, chapter_id, season_id,
              body, quote_text, link_url, cover_url, metadata, is_spoiler, min_percent)
  on table public.feed_posts to authenticated;
grant update (kind, visibility, club_id, book_id, chapter_id, season_id, body,
              quote_text, link_url, cover_url, metadata, is_spoiler, min_percent,
              deleted_at, updated_at) on table public.feed_posts to authenticated;
grant delete on table public.feed_posts to authenticated;
do $$ begin
  if not exists (select 1 from pg_constraint where conrelid='public.feed_posts'::regclass
                 and conname='feed_posts_min_percent_range_check') then
    alter table public.feed_posts add constraint feed_posts_min_percent_range_check
      check (min_percent between 0 and 100) not valid;
  end if;
end $$;
alter table public.feed_posts validate constraint feed_posts_min_percent_range_check;
drop policy if exists feed_posts_read on public.feed_posts;
create policy feed_posts_read_visible on public.feed_posts
  for select to anon, authenticated
  using (deleted_at is null and (visibility='public' or author_id=(select auth.uid())
    or (visibility='followers' and exists (
      select 1 from public.follows f where f.follower_id=(select auth.uid())
        and f.followed_id=feed_posts.author_id and f.status='accepted'))
    or (visibility='club' and exists (
      select 1 from public.user_club_members m where m.club_id=feed_posts.club_id
        and m.user_id=(select auth.uid())))));
drop policy if exists feed_posts_author_write on public.feed_posts;
create policy feed_posts_insert_own on public.feed_posts
  for insert to authenticated with check (author_id=(select auth.uid()));
create policy feed_posts_update_own on public.feed_posts
  for update to authenticated using (author_id=(select auth.uid()))
  with check (author_id=(select auth.uid()));
create policy feed_posts_delete_own on public.feed_posts
  for delete to authenticated using (author_id=(select auth.uid()));
create or replace function private.get_visible_feed_posts()
returns table (id uuid, author_id uuid, kind public.feed_post_kind,
               visibility public.feed_visibility, club_id uuid, book_id uuid,
               chapter_id uuid, season_id uuid, body text, quote_text text,
               link_url text, cover_url text, metadata jsonb, is_spoiler boolean,
               is_locked boolean, min_percent numeric, likes_count integer,
               comments_count integer, shares_count integer,
               created_at timestamptz, updated_at timestamptz)
language sql stable security definer set search_path = ''
as $$
  select p.id,p.author_id,p.kind,p.visibility,p.club_id,p.book_id,p.chapter_id,p.season_id,
         case when p.is_spoiler and coalesce(up.percent,0)<p.min_percent then null::text else p.body end,
         case when p.is_spoiler and coalesce(up.percent,0)<p.min_percent then null::text else p.quote_text end,
         case when p.is_spoiler and coalesce(up.percent,0)<p.min_percent then null::text else p.link_url end,
         p.cover_url,
         case when p.is_spoiler and coalesce(up.percent,0)<p.min_percent then '{}'::jsonb else p.metadata end,
         p.is_spoiler,(p.is_spoiler and coalesce(up.percent,0)<p.min_percent),
         p.min_percent,p.likes_count,p.comments_count,p.shares_count,p.created_at,p.updated_at
  from public.feed_posts p
  left join public.user_progress up on up.user_id=(select auth.uid()) and up.chapter_id=p.chapter_id
  where private.can_view_feed_post(p.id);
$$;
revoke all on function private.get_visible_feed_posts() from public;
grant execute on function private.get_visible_feed_posts() to anon, authenticated;
create or replace view public.v_feed_posts_visible
with (security_invoker = true, security_barrier = true) as
select * from private.get_visible_feed_posts();
revoke all privileges on table public.v_feed_posts_visible from public, anon, authenticated;
grant select on table public.v_feed_posts_visible to anon, authenticated;

-- 4) Quiz answers and scored attempts cannot be fabricated by a browser client.
create or replace view public.v_quiz_questions_public
with (security_invoker = true, security_barrier = true) as
select id,chapter_id,position,question,options from public.quiz_questions;
revoke all privileges on table public.v_quiz_questions_public from public, anon, authenticated;
grant select on table public.v_quiz_questions_public to authenticated;
revoke all privileges on table public.quiz_questions from public, anon, authenticated;
grant select (id, chapter_id, position, question, options)
  on table public.quiz_questions to authenticated;
revoke all privileges on table public.quiz_attempts from public, anon, authenticated;
revoke all privileges on table public.quiz_answers from public, anon, authenticated;
grant select on table public.quiz_attempts, public.quiz_answers to authenticated;
do $$ begin
  if not exists (select 1 from pg_constraint where conrelid='public.quiz_attempts'::regclass and conname='quiz_attempts_score_total_check') then
    alter table public.quiz_attempts add constraint quiz_attempts_score_total_check check (total>0 and score>=0 and score<=total) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conrelid='public.quiz_attempts'::regclass and conname='quiz_attempts_duration_nonnegative_check') then
    alter table public.quiz_attempts add constraint quiz_attempts_duration_nonnegative_check check (duration_ms is null or duration_ms>=0) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conrelid='public.quiz_answers'::regclass and conname='quiz_answers_chosen_idx_nonnegative_check') then
    alter table public.quiz_answers add constraint quiz_answers_chosen_idx_nonnegative_check check (chosen_idx>=0) not valid;
  end if;
end $$;
alter table public.quiz_attempts validate constraint quiz_attempts_score_total_check;
alter table public.quiz_attempts validate constraint quiz_attempts_duration_nonnegative_check;
alter table public.quiz_answers validate constraint quiz_answers_chosen_idx_nonnegative_check;
create index if not exists quiz_attempts_user_created_idx
  on public.quiz_attempts (user_id, created_at desc);

-- 5) Ownership must hold both before and after a list/media/club mutation.
drop policy if exists list_items_write on public.reading_list_items;
create policy list_items_insert_authorized on public.reading_list_items
  for insert to authenticated with check ((added_by is null or added_by=(select auth.uid()))
    and private.can_edit_reading_list(list_id));
create policy list_items_update_authorized on public.reading_list_items
  for update to authenticated using (private.can_edit_reading_list(list_id))
  with check (private.can_edit_reading_list(list_id));
create policy list_items_delete_authorized on public.reading_list_items
  for delete to authenticated using (private.can_edit_reading_list(list_id));
drop policy if exists list_collab_owner on public.reading_list_collaborators;
create policy list_collab_insert_owner on public.reading_list_collaborators
  for insert to authenticated with check (exists (select 1 from public.reading_lists l
    where l.id=list_id and l.owner_id=(select auth.uid())));
create policy list_collab_update_owner on public.reading_list_collaborators
  for update to authenticated using (exists (select 1 from public.reading_lists l
    where l.id=list_id and l.owner_id=(select auth.uid())))
  with check (exists (select 1 from public.reading_lists l
    where l.id=list_id and l.owner_id=(select auth.uid())));
create policy list_collab_delete_owner on public.reading_list_collaborators
  for delete to authenticated using (exists (select 1 from public.reading_lists l
    where l.id=list_id and l.owner_id=(select auth.uid())));

drop policy if exists feed_media_read on public.feed_post_media;
create policy feed_media_read_visible_post on public.feed_post_media
  for select to anon, authenticated using (private.can_view_feed_post(post_id));
drop policy if exists feed_media_author on public.feed_post_media;
create policy feed_media_insert_own_post on public.feed_post_media
  for insert to authenticated with check (exists (select 1 from public.feed_posts p
    where p.id=post_id and p.author_id=(select auth.uid())));
create policy feed_media_update_own_post on public.feed_post_media
  for update to authenticated using (exists (select 1 from public.feed_posts p
    where p.id=post_id and p.author_id=(select auth.uid())))
  with check (exists (select 1 from public.feed_posts p
    where p.id=post_id and p.author_id=(select auth.uid())));
create policy feed_media_delete_own_post on public.feed_post_media
  for delete to authenticated using (exists (select 1 from public.feed_posts p
    where p.id=post_id and p.author_id=(select auth.uid())));

drop policy if exists uclub_members_read on public.user_club_members;
create policy uclub_members_read_visible on public.user_club_members
  for select to anon, authenticated using (user_id=(select auth.uid()) or exists (
    select 1 from public.user_clubs c where c.id=club_id
      and (not c.is_private or c.owner_id=(select auth.uid()))));
drop policy if exists uclub_members_self on public.user_club_members;
create policy uclub_members_insert_authorized on public.user_club_members
  for insert to authenticated with check (
    (user_id=(select auth.uid()) and exists (select 1 from public.user_clubs c
      where c.id=club_id and (not c.is_private or c.owner_id=(select auth.uid()))))
    or exists (select 1 from public.user_clubs c where c.id=club_id and c.owner_id=(select auth.uid())));
create policy uclub_members_update_authorized on public.user_club_members
  for update to authenticated using (user_id=(select auth.uid()) or exists (
    select 1 from public.user_clubs c where c.id=club_id and c.owner_id=(select auth.uid())))
  with check ((user_id=(select auth.uid()) and exists (select 1 from public.user_clubs c
      where c.id=club_id and (not c.is_private or c.owner_id=(select auth.uid()))))
    or exists (select 1 from public.user_clubs c where c.id=club_id and c.owner_id=(select auth.uid())));
create policy uclub_members_delete_authorized on public.user_club_members
  for delete to authenticated using (user_id=(select auth.uid()) or exists (
    select 1 from public.user_clubs c where c.id=club_id and c.owner_id=(select auth.uid())));

-- 6) Social replies/reactions inherit their parent post visibility.
drop policy if exists feed_comments_read on public.feed_post_comments;
create policy feed_comments_read_visible_post on public.feed_post_comments
  for select to anon, authenticated using (deleted_at is null and private.can_view_feed_post(post_id));
drop policy if exists feed_comments_write_own on public.feed_post_comments;
create policy feed_comments_insert_visible_post on public.feed_post_comments
  for insert to authenticated with check (user_id=(select auth.uid()) and private.can_view_feed_post(post_id));
create policy feed_comments_update_own on public.feed_post_comments
  for update to authenticated using (user_id=(select auth.uid()))
  with check (user_id=(select auth.uid()) and private.can_view_feed_post(post_id));
create policy feed_comments_delete_own on public.feed_post_comments
  for delete to authenticated using (user_id=(select auth.uid()));
drop policy if exists feed_likes_read on public.feed_post_likes;
create policy feed_likes_read_visible_post on public.feed_post_likes
  for select to anon, authenticated using (private.can_view_feed_post(post_id));
drop policy if exists feed_likes_own on public.feed_post_likes;
create policy feed_likes_insert_own on public.feed_post_likes
  for insert to authenticated with check (user_id=(select auth.uid()) and private.can_view_feed_post(post_id));
create policy feed_likes_update_own on public.feed_post_likes
  for update to authenticated using (user_id=(select auth.uid()))
  with check (user_id=(select auth.uid()) and private.can_view_feed_post(post_id));
create policy feed_likes_delete_own on public.feed_post_likes
  for delete to authenticated using (user_id=(select auth.uid()));

drop policy if exists bmv_read on public.book_mood_votes;
drop policy if exists bmv_own on public.book_mood_votes;
create policy bmv_select_own on public.book_mood_votes for select to authenticated using (user_id=(select auth.uid()));
create policy bmv_insert_own on public.book_mood_votes for insert to authenticated with check (user_id=(select auth.uid()));
create policy bmv_update_own on public.book_mood_votes for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy bmv_delete_own on public.book_mood_votes for delete to authenticated using (user_id=(select auth.uid()));

-- Friends-only journal entries require accepted follows in both directions.
drop policy if exists journal_read_own on public.reading_journal_entries;
create or replace function private.can_view_club_journal(p_author_id uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null and exists (
    select 1 from public.user_clubs uc
    where ((uc.owner_id=(select auth.uid()) or exists (
             select 1 from public.user_club_members m
             where m.club_id=uc.id and m.user_id=(select auth.uid())))
       and (uc.owner_id=p_author_id or exists (
             select 1 from public.user_club_members m
             where m.club_id=uc.id and m.user_id=p_author_id)))
  );
$$;
revoke all on function private.can_view_club_journal(uuid) from public, anon;
grant execute on function private.can_view_club_journal(uuid) to authenticated;
create policy journal_read_own on public.reading_journal_entries
  for select to authenticated using (user_id=(select auth.uid()) or visibility='public'
    or (visibility='friends' and exists (select 1 from public.follows f1
      where f1.follower_id=(select auth.uid()) and f1.followed_id=user_id and f1.status='accepted'
        and exists (select 1 from public.follows f2 where f2.follower_id=user_id
          and f2.followed_id=(select auth.uid()) and f2.status='accepted')))
    or (visibility='club' and (select private.can_view_club_journal(user_id))));

create or replace function private.can_view_club_prompt_response(p_prompt_id uuid,p_author_id uuid)
returns boolean language sql stable security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null and exists (
    select 1 from public.chapter_prompts cp
    join public.chapters ch on ch.id=cp.chapter_id
    join public.seasons s on s.id=ch.season_id
    join public.user_clubs uc on uc.current_book_id=s.book_id
      and (uc.current_season_id is null or uc.current_season_id=s.id)
    where cp.id=p_prompt_id
      and (uc.owner_id=(select auth.uid()) or exists (select 1 from public.user_club_members m
        where m.club_id=uc.id and m.user_id=(select auth.uid())))
      and (uc.owner_id=p_author_id or exists (select 1 from public.user_club_members m
        where m.club_id=uc.id and m.user_id=p_author_id))
  );
$$;
revoke all on function private.can_view_club_prompt_response(uuid,uuid) from public, anon;
grant execute on function private.can_view_club_prompt_response(uuid,uuid) to authenticated;
drop policy if exists cpr_read on public.chapter_prompt_responses;
create policy cpr_read on public.chapter_prompt_responses for select to authenticated
  using (user_id=(select auth.uid()) or visibility='public'
    or (visibility='friends' and exists (select 1 from public.follows f1
      where f1.follower_id=(select auth.uid()) and f1.followed_id=user_id and f1.status='accepted'
        and exists (select 1 from public.follows f2 where f2.follower_id=user_id
          and f2.followed_id=(select auth.uid()) and f2.status='accepted')))
    or (visibility='club' and (select private.can_view_club_prompt_response(prompt_id,user_id))));

-- 7) Storage: feed-media is empty; privatize it and bind object reads to posts.
do $$ begin
  if exists (select 1 from storage.objects where bucket_id='feed-media' limit 1) then
    raise exception 'feed-media is no longer empty; review existing objects before privatizing';
  end if;
end $$;
update storage.buckets set public=false where id='feed-media';
drop policy if exists feed_media_read on storage.objects;
create policy feed_media_read_visible_post on storage.objects
  for select to anon, authenticated using (bucket_id='feed-media' and (
    auth.uid()::text=(storage.foldername(name))[1]
    or exists (select 1 from public.feed_post_media fm
      where fm.storage_path=storage.objects.name and private.can_view_feed_post(fm.post_id))));
drop policy if exists feed_media_author_write on storage.objects;
create policy feed_media_author_insert on storage.objects
  for insert to authenticated with check (bucket_id='feed-media'
    and auth.uid()::text=(storage.foldername(name))[1]);
drop policy if exists feed_media_author_update on storage.objects;
create policy feed_media_author_update on storage.objects
  for update to authenticated using (bucket_id='feed-media'
    and auth.uid()::text=(storage.foldername(name))[1])
  with check (bucket_id='feed-media' and auth.uid()::text=(storage.foldername(name))[1]);
create policy feed_media_author_delete on storage.objects
  for delete to authenticated using (bucket_id='feed-media'
    and auth.uid()::text=(storage.foldername(name))[1]);

drop policy if exists chapter_extras_read_auth on storage.objects;
create policy chapter_extras_read_public_or_admin on storage.objects
  for select to authenticated using (bucket_id='chapter-extras' and (
    (select public.is_admin()) or exists (select 1 from public.chapter_extra_content cec
      where cec.storage_path=storage.objects.name and cec.is_public)));
drop policy if exists manuscripts_admin_only on storage.objects;
create policy manuscripts_admin_only on storage.objects for all to authenticated
  using (bucket_id='manuscripts' and (select public.is_admin()))
  with check (bucket_id='manuscripts' and (select public.is_admin()));

-- >>> 20261008225535_prevent_client_privilege_escalation.sql
-- Prevent self-assigned club privileges, client-edited levels, and redundant
-- FOR ALL policies on journal and prompt response tables.

-- `level` is a server-derived progression attribute, never user-editable.
revoke update (level) on table public.profiles from anon, authenticated;

-- The only supported membership roles are explicit. Existing rows were audited
-- before adding this constraint; the table currently contains no memberships.
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.user_club_members'::regclass
      and conname='user_club_members_role_check'
  ) then
    alter table public.user_club_members
      add constraint user_club_members_role_check
      check (role in ('owner','moderator','member')) not valid;
  end if;
end $$;
alter table public.user_club_members
  validate constraint user_club_members_role_check;

-- A reader may self-join a public club only as an ordinary member. Only the
-- owning account may assign a privileged membership role or manage others.
drop policy if exists uclub_members_insert_authorized on public.user_club_members;
create policy uclub_members_insert_authorized on public.user_club_members
  for insert to authenticated with check (
    (user_id=(select auth.uid()) and role='member' and exists (
      select 1 from public.user_clubs c
      where c.id=club_id and (not c.is_private or c.owner_id=(select auth.uid()))))
    or (role in ('owner','moderator','member') and exists (
      select 1 from public.user_clubs c
      where c.id=club_id and c.owner_id=(select auth.uid())))
  );
drop policy if exists uclub_members_update_authorized on public.user_club_members;
create policy uclub_members_update_authorized on public.user_club_members
  for update to authenticated
  using (user_id=(select auth.uid()) or exists (
    select 1 from public.user_clubs c
    where c.id=club_id and c.owner_id=(select auth.uid())))
  with check (
    (user_id=(select auth.uid()) and role='member' and exists (
      select 1 from public.user_clubs c
      where c.id=club_id and (not c.is_private or c.owner_id=(select auth.uid()))))
    or (role in ('owner','moderator','member') and exists (
      select 1 from public.user_clubs c
      where c.id=club_id and c.owner_id=(select auth.uid())))
  );

-- Keep read-sharing rules separate from write ownership to avoid two
-- permissive SELECT policies where an ALL policy overlaps with SELECT.
drop policy if exists journal_write_own on public.reading_journal_entries;
create policy journal_insert_own on public.reading_journal_entries
  for insert to authenticated with check (user_id=(select auth.uid()));
create policy journal_update_own on public.reading_journal_entries
  for update to authenticated using (user_id=(select auth.uid()))
  with check (user_id=(select auth.uid()));
create policy journal_delete_own on public.reading_journal_entries
  for delete to authenticated using (user_id=(select auth.uid()));

drop policy if exists cpr_own on public.chapter_prompt_responses;
create policy cpr_insert_own on public.chapter_prompt_responses
  for insert to authenticated with check (user_id=(select auth.uid()));
create policy cpr_update_own on public.chapter_prompt_responses
  for update to authenticated using (user_id=(select auth.uid()))
  with check (user_id=(select auth.uid()));
create policy cpr_delete_own on public.chapter_prompt_responses
  for delete to authenticated using (user_id=(select auth.uid()));

-- >>> 20261008225856_encapsulate_profile_consent_privilege.sql
-- Keep the existing profile RPC contract while moving the only privileged
-- read into the non-exposed `private` schema. Public RPCs run as invoker.
create or replace function private.get_my_profile_private()
returns table (whatsapp text, lgpd_consent boolean,
               lgpd_consent_at timestamptz, onboarding_done boolean)
language sql stable security definer set search_path = ''
as $$
  select p.whatsapp, p.lgpd_consent, p.lgpd_consent_at, p.onboarding_done
  from public.profiles p
  where p.id = (select auth.uid()) and (select auth.uid()) is not null;
$$;
revoke all on function private.get_my_profile_private() from public, anon;
grant execute on function private.get_my_profile_private() to authenticated;

create or replace function public.get_my_profile_private()
returns table (whatsapp text, lgpd_consent boolean,
               lgpd_consent_at timestamptz, onboarding_done boolean)
language sql stable security invoker set search_path = ''
as $$
  select * from private.get_my_profile_private();
$$;
revoke all on function public.get_my_profile_private() from public, anon;
grant execute on function public.get_my_profile_private() to authenticated;

-- The consent RPC remains callable, but now uses the caller's own UPDATE
-- privilege and RLS policy instead of elevating privileges.
grant update (lgpd_consent) on table public.profiles to authenticated;

create or replace function private.sync_lgpd_consent_timestamp()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  if new.lgpd_consent is distinct from old.lgpd_consent then
    new.lgpd_consent_at := case
      when new.lgpd_consent then statement_timestamp()
      else null
    end;
    new.updated_at := statement_timestamp();
  end if;
  return new;
end;
$$;
revoke all on function private.sync_lgpd_consent_timestamp() from public, anon, authenticated;
drop trigger if exists profiles_lgpd_consent_timestamp on public.profiles;
create trigger profiles_lgpd_consent_timestamp
before update of lgpd_consent on public.profiles
for each row execute function private.sync_lgpd_consent_timestamp();

create or replace function public.set_my_lgpd_consent(p_consent boolean)
returns void language plpgsql security invoker set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_consent is null then
    raise exception 'consent value is required' using errcode = '22004';
  end if;
  update public.profiles
     set lgpd_consent = p_consent
   where id = (select auth.uid());
  if not found then raise exception 'profile not found' using errcode = 'P0002'; end if;
end;
$$;
revoke all on function public.set_my_lgpd_consent(boolean) from public, anon;
grant execute on function public.set_my_lgpd_consent(boolean) to authenticated;
