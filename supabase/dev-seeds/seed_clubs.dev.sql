-- DEV ONLY. Não aplicar no projeto remoto de produção.
-- Requer os seeds do livro/temporada e um perfil role='admin'.
-- Sem esses dados, os INSERTs afetam zero linhas.
with owner_profile as (
  select p.id
  from public.profiles p
  where p.role = 'admin'
  order by p.id
  limit 1
), valid_book as (
  select b.id as book_id, s.id as season_id
  from public.books b
  join public.seasons s on s.book_id = b.id
  where b.id = '22222222-2222-2222-2222-222222222222'::uuid
    and s.id = '33333333-3333-3333-3333-333333333333'::uuid
)
insert into public.user_clubs (
  id, owner_id, name, slug, description, is_private,
  current_book_id, current_season_id, current_started_at
)
select
  '44444444-4444-4444-4444-444444444444'::uuid,
  owner_profile.id,
  'Clube Dom Casmurro',
  'clube-dom-casmurro',
  'Clube demonstrativo para validar o painel de progresso em desenvolvimento.',
  false,
  valid_book.book_id,
  valid_book.season_id,
  now()
from owner_profile
cross join valid_book
on conflict (slug) do update
set current_book_id = excluded.current_book_id,
    current_season_id = excluded.current_season_id,
    current_started_at = excluded.current_started_at;

insert into public.user_club_members (club_id, user_id, role)
select
  uc.id,
  uc.owner_id,
  'owner'
from public.user_clubs uc
where uc.slug = 'clube-dom-casmurro'
on conflict (club_id, user_id) do update
set role = excluded.role;
