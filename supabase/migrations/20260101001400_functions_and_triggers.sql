-- Source: SDDBD2.md sections 6.1-6.2.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, username, display_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email,'@',1)),
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email,'@',1)),
    new.raw_user_meta_data->>'avatar_url'
  )
  on conflict (id) do nothing;

  insert into public.user_xp (user_id) values (new.id)
    on conflict do nothing;
  insert into public.user_streaks (user_id) values (new.id)
    on conflict do nothing;
  return new;
end $$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created after insert ON auth.users
for each row execute function public.handle_new_user();

create or replace function public.award_xp(
  p_user uuid,
  p_source xp_source,
  p_amount int,
  p_ref uuid default null
) returns void language plpgsql security definer as $$
begin
  insert into public.xp_events (user_id, source, amount, ref_id)
  values (p_user, p_source, p_amount, p_ref);

  insert into public.user_xp (user_id, total_xp, updated_at)
  values (p_user, p_amount, now())
  on conflict (user_id) do update
    set total_xp = public.user_xp.total_xp + excluded.total_xp,
        updated_at = now();
end $$;

create or replace function public.bump_comment_likes()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    update public.comments set likes_count = likes_count + 1 where id = new.comment_id;
  elsif tg_op = 'DELETE' then
    update public.comments set likes_count = likes_count - 1 where id = old.comment_id;
  end if;
  return null;
end $$;

DROP TRIGGER IF EXISTS trg_comment_likes ON public.reactions;
CREATE TRIGGER trg_comment_likes after insert or delete ON public.reactions
for each row execute function public.bump_comment_likes();

create or replace function public.bump_comment_replies()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' and new.parent_id is not null then
    update public.comments set replies_count = replies_count + 1 where id = new.parent_id;
  elsif tg_op = 'DELETE' and old.parent_id is not null then
    update public.comments set replies_count = replies_count - 1 where id = old.parent_id;
  end if;
  return null;
end $$;

DROP TRIGGER IF EXISTS trg_comment_replies ON public.comments;
CREATE TRIGGER trg_comment_replies after insert or delete ON public.comments
for each row execute function public.bump_comment_replies();

create or replace function public.touch_streak()
returns trigger language plpgsql as $$
declare
  v_user uuid;
  v_last date;
  v_today date := current_date;
  v_curr int;
  v_long int;
begin
  -- quem gerou atividade?
  if tg_table_name = 'user_progress' then v_user := new.user_id;
  elsif tg_table_name = 'xp_events'   then v_user := new.user_id;
  else return null; end if;

  select last_activity_at, current_streak, longest_streak
    into v_last, v_curr, v_long
  from public.user_streaks where user_id = v_user for update;

  if v_last = v_today then return null; end if;

  if v_last = v_today - 1 then
    v_curr := coalesce(v_curr,0) + 1;
  else
    v_curr := 1;
  end if;
  v_long := greatest(coalesce(v_long,0), v_curr);

  update public.user_streaks
     set current_streak = v_curr,
         longest_streak = v_long,
         last_activity_at = v_today,
         updated_at = now()
   where user_id = v_user;

  return null;
end $$;

DROP TRIGGER IF EXISTS trg_streak_progress ON public.user_progress;
CREATE TRIGGER trg_streak_progress after insert or update ON public.user_progress
for each row execute function public.touch_streak();

DROP TRIGGER IF EXISTS trg_streak_xp ON public.xp_events;
CREATE TRIGGER trg_streak_xp after insert ON public.xp_events
for each row execute function public.touch_streak();

create or replace function public.match_books(
  query_embedding vector(1536),
  match_threshold float,
  match_count int
) returns table (id uuid, title text, similarity float)
language sql stable as $$
  select b.id, b.title, 1 - (b.embedding <=> query_embedding) as similarity
  from public.books b
  where b.embedding is not null
    and 1 - (b.embedding <=> query_embedding) > match_threshold
  order by b.embedding <=> query_embedding
  limit match_count;
$$;

create or replace view public.v_chapter_audience as
select
  c.id                                  as chapter_id,
  c.season_id,
  count(*) filter (where p.status = 'read')             as finished_count,
  count(*) filter (where p.status = 'reading')          as reading_count,
  count(*) filter (where p.status = 'want_to_read')     as not_started_count,
  round(avg(p.percent)::numeric, 2)                     as avg_percent
from public.chapters c
left join public.user_progress p on p.chapter_id = c.id
group by c.id, c.season_id;

create or replace view public.v_season_ranking as
select
  ux.season_id,
  ux.user_id,
  p.username,
  p.display_name,
  p.avatar_url,
  ux.season_xp,
  row_number() over (partition by ux.season_id order by ux.season_xp desc) as position
from public.user_xp ux
join public.profiles p on p.id = ux.user_id
where ux.season_id is not null;

create or replace view public.v_comments_visible as
select
  c.id, c.chapter_id, c.user_id, c.parent_id, c.created_at, c.likes_count,
  c.replies_count, c.is_spoiler,
  case
    when c.is_spoiler and coalesce(up.percent,0) < c.min_percent then null
    else c.content
  end as content,
  case
    when c.is_spoiler and coalesce(up.percent,0) < c.min_percent then true
    else false
  end as is_locked
from public.comments c
left join public.user_progress up
  on up.chapter_id = c.chapter_id and up.user_id = auth.uid()
where c.deleted_at is null;
