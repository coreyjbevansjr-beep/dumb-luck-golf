-- Admin Players: one tap makes the signed-in admin friends with a player.
-- Live schema this matches (read from the project, not assumed):
--   public.friendships(id uuid, requester uuid, addressee uuid, status text, created_at, responded_at)
--   public.profiles(id uuid, username)
--   public.request_friend(p_username) exists and is the request/accept path. It does not
--   accept on the admin's behalf, and public.admin_add_friend did not exist.
-- The admin gate is the existing public.admin_whoami() (the same one the ADMIN page calls).
-- Run once in the Supabase SQL editor.

create or replace function public.admin_add_friend(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  them uuid;
  v_ret text;
  v_admin boolean := false;
  v_json jsonb;
  v_name text := btrim(coalesce(p_username, ''));
begin
  if me is null then
    raise exception 'admin only' using errcode = '42501';
  end if;
  select pg_catalog.format_type(p.prorettype, null) into v_ret
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'admin_whoami'
    and pg_catalog.pg_get_function_identity_arguments(p.oid) = ''
  limit 1;
  if v_ret in ('jsonb', 'json') then
    v_json := public.admin_whoami()::jsonb;
    v_admin := coalesce((v_json ->> 'admin')::boolean, false);
  else
    execute 'select admin from public.admin_whoami()' into v_admin;
  end if;
  if coalesce(v_admin, false) is not true then
    raise exception 'admin only' using errcode = '42501';
  end if;
  if v_name = '' then
    raise exception 'no such player' using errcode = '22023';
  end if;
  select p.id into them from public.profiles p where lower(p.username) = lower(v_name) limit 1;
  if them is null then
    raise exception 'no such player' using errcode = '22023';
  end if;
  if them = me then
    raise exception 'that is you' using errcode = '22023';
  end if;
  update public.friendships f
     set status = 'accepted', responded_at = pg_catalog.now()
   where (f.requester = me and f.addressee = them)
      or (f.requester = them and f.addressee = me);
  if not found then
    insert into public.friendships (requester, addressee, status, responded_at)
    values (me, them, 'accepted', pg_catalog.now());
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.admin_add_friend(text) from public, anon;
grant execute on function public.admin_add_friend(text) to authenticated;
