-- Coin shop purchase. Matches live schema (player_wallet / player_cosmetics / private.cosmetics_add).
create table if not exists private.coin_shop (
  item text primary key,
  price integer not null check (price > 0),
  slot text not null
);
insert into private.coin_shop (item, price, slot) values
  ('practice_tee', 100, 'held'),
  ('range_ball', 150, 'ball'),
  ('cream_belt', 200, 'waist')
on conflict (item) do update set price = excluded.price, slot = excluded.slot;
alter table private.coin_shop enable row level security;

create or replace function public.buy_gear(p_item text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_price integer;
  v_coins integer;
  v_owned jsonb;
  v_have integer;
begin
  if me is null then raise exception 'denied' using errcode = '42501'; end if;
  if private.is_banned(me) then raise exception 'banned' using errcode = '42501'; end if;
  select s.price into v_price from private.coin_shop s where s.item = p_item;
  if v_price is null then raise exception 'unknown item' using errcode = '22023'; end if;
  perform private.wallet_ensure(me);
  select c.qty into v_have from public.player_cosmetics c where c.user_id = me and c.item_id = p_item;
  if coalesce(v_have, 0) > 0 then
    select w.coins into v_coins from public.player_wallet w where w.user_id = me;
    select coalesce(jsonb_object_agg(c.item_id, c.qty), '{}'::jsonb) into v_owned from public.player_cosmetics c where c.user_id = me;
    return jsonb_build_object('ok', true, 'item', p_item, 'coins', v_coins, 'owned', v_owned);
  end if;
  update public.player_wallet w set coins = w.coins - v_price, updated_at = now()
    where w.user_id = me and w.coins >= v_price returning w.coins into v_coins;
  if not found then raise exception 'not enough coins' using errcode = 'P0001'; end if;
  perform private.cosmetics_add(me, p_item, 1, 'coin');
  select coalesce(jsonb_object_agg(c.item_id, c.qty), '{}'::jsonb) into v_owned from public.player_cosmetics c where c.user_id = me;
  return jsonb_build_object('ok', true, 'item', p_item, 'coins', v_coins, 'owned', v_owned);
end;
$$;
revoke all on function public.buy_gear(text) from public;
grant execute on function public.buy_gear(text) to authenticated;
grant execute on function public.buy_gear(text) to service_role;
