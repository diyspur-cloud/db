-- Triggers internos de contadores e streak.
-- Os corpos preservam os algoritmos existentes; apenas o contexto de execução
-- e a qualificação de nomes mudam para atravessar grants de cliente.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated, service_role;

create or replace function private.bump_comment_likes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.comments
       set likes_count = likes_count + 1
     where id = new.comment_id;
  elsif tg_op = 'DELETE' then
    update public.comments
       set likes_count = likes_count - 1
     where id = old.comment_id;
  end if;
  return null;
end;
$$;

create or replace function private.bump_comment_replies()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and new.parent_id is not null then
    update public.comments
       set replies_count = replies_count + 1
     where id = new.parent_id;
  elsif tg_op = 'DELETE' and old.parent_id is not null then
    update public.comments
       set replies_count = replies_count - 1
     where id = old.parent_id;
  end if;
  return null;
end;
$$;

create or replace function private.touch_streak()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
  v_last date;
  v_today date := current_date;
  v_curr int;
  v_long int;
begin
  if tg_table_name = 'user_progress' then
    v_user := new.user_id;
  elsif tg_table_name = 'xp_events' then
    v_user := new.user_id;
  else
    return null;
  end if;

  select us.last_activity_at, us.current_streak, us.longest_streak
    into v_last, v_curr, v_long
    from public.user_streaks as us
   where us.user_id = v_user
   for update;

  if v_last = v_today then
    return null;
  end if;

  if v_last = v_today - 1 then
    v_curr := coalesce(v_curr, 0) + 1;
  else
    v_curr := 1;
  end if;
  v_long := greatest(coalesce(v_long, 0), v_curr);

  update public.user_streaks
     set current_streak = v_curr,
         longest_streak = v_long,
         last_activity_at = v_today,
         updated_at = now()
   where user_id = v_user;

  return null;
end;
$$;

create or replace function private.bump_feed_post_counters()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_table_name = 'feed_post_likes' then
    if tg_op = 'INSERT' then
      update public.feed_posts
         set likes_count = likes_count + 1
       where id = new.post_id;
    elsif tg_op = 'DELETE' then
      update public.feed_posts
         set likes_count = greatest(likes_count - 1, 0)
       where id = old.post_id;
    end if;
  elsif tg_table_name = 'feed_post_comments' then
    if tg_op = 'INSERT' then
      update public.feed_posts
         set comments_count = comments_count + 1
       where id = new.post_id;
    elsif tg_op = 'DELETE' then
      update public.feed_posts
         set comments_count = greatest(comments_count - 1, 0)
       where id = old.post_id;
    end if;
  end if;
  return null;
end;
$$;

-- Trigger functions are internal implementation details, never RPC entry points.
revoke all on function private.bump_comment_likes(),
  private.bump_comment_replies(), private.touch_streak(),
  private.bump_feed_post_counters()
  from public, anon, authenticated, service_role;
revoke all on function public.bump_comment_likes(),
  public.bump_comment_replies(), public.touch_streak(),
  public.bump_feed_post_counters()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_comment_likes on public.reactions;
create trigger trg_comment_likes
  after insert or delete on public.reactions
  for each row execute function private.bump_comment_likes();

drop trigger if exists trg_comment_replies on public.comments;
create trigger trg_comment_replies
  after insert or delete on public.comments
  for each row execute function private.bump_comment_replies();

drop trigger if exists trg_streak_progress on public.user_progress;
create trigger trg_streak_progress
  after insert or update on public.user_progress
  for each row execute function private.touch_streak();

drop trigger if exists trg_streak_xp on public.xp_events;
create trigger trg_streak_xp
  after insert on public.xp_events
  for each row execute function private.touch_streak();

drop trigger if exists trg_feed_likes_counters on public.feed_post_likes;
create trigger trg_feed_likes_counters
  after insert or delete on public.feed_post_likes
  for each row execute function private.bump_feed_post_counters();

drop trigger if exists trg_feed_comments_counters on public.feed_post_comments;
create trigger trg_feed_comments_counters
  after insert or delete on public.feed_post_comments
  for each row execute function private.bump_feed_post_counters();
