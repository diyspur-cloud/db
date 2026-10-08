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
