-- Coin shop purchase. Run once in Supabase: SQL Editor -> New query -> paste -> Run.
-- Does not grant the client a price. Prices live in public.coin_shop.
--
-- ASSUMED SCHEMA (already used by my_wallet / stake_deposit / my_gear; not created here):
--   public.wallets (
--     user_id uuid primary key,          -- matches auth.uid()
--     coins integer not null default 0,
--     boxes integer not null default 0,
--     rounds_at_grant integer not null default 0
--   )
--   public.wallet_items (
--     user_id uuid not null,
--     item text not null,
--     qty integer not null default 0,    -- my_wallet.owned is { item: qty }
--     primary key (user_id, item)
--   )
--   my_wallet() returns jsonb:
--     { coins, boxes, rounds_at_grant, owned }
--     owned = jsonb_object_agg(wallet_items.item, wallet_items.qty) for qty > 0
--   public.user_gear (
--     user_id uuid not null,
--     item text not null,
--     equipped boolean not null default false,
--     source text,
--     primary key (user_id, item)
--   )
--   my_gear() returns rows (item text, equipped boolean, source text) from user_gear
--   public.gear_catalog (id text, slot text, ...)  -- already read by the client
--
-- If user_gear is absent, the coin debit and wallet_items grant still commit.
-- If wallets or wallet_items is absent, the function errors (42P01) and the client
-- shows COIN SHOP COMING SOON without spending anything.

create table if not exists public.coin_shop (
  item text primary key,
  price integer not null check (price > 0),
  slot text not null
);

insert into public.coin_shop (item, price, slot) values
  ('practice_tee', 100, 'held'),
  ('range_ball', 150, 'ball'),
  ('cream_belt', 200, 'waist')
on conflict (item) do update set price = excluded.price, slot = excluded.slot;

alter table public.coin_shop enable row level security;

create or replace function public.buy_gear(p_item text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_price integer;
  v_slot text;
  v_coins integer;
  v_owned jsonb;
begin
  if v_uid is null then
    raise exception 'NOT SIGNED IN';
  end if;

  select price, slot into v_price, v_slot
  from public.coin_shop
  where item = p_item;

  if v_price is null then
    raise exception 'UNKNOWN ITEM';
  end if;

  -- Lock the wallet row, then debit only when the balance covers the server price.
  select coins into v_coins
  from public.wallets
  where user_id = v_uid
  for update;

  if v_coins is null or v_coins < v_price then
    raise exception 'NOT ENOUGH COINS';
  end if;

  update public.wallets
  set coins = coins - v_price
  where user_id = v_uid
  returning coins into v_coins;

  insert into public.wallet_items (user_id, item, qty)
  values (v_uid, p_item, 1)
  on conflict (user_id, item) do update
  set qty = public.wallet_items.qty + 1;

  -- Best-effort equip row so my_gear / equip_gear see the piece. Missing table does not refund.
  begin
    update public.user_gear ug
    set equipped = false
    where ug.user_id = v_uid
      and ug.equipped
      and exists (
        select 1 from public.gear_catalog g
        where g.id = ug.item and g.slot = v_slot
      );
    insert into public.user_gear (user_id, item, equipped, source)
    values (v_uid, p_item, true, 'coin')
    on conflict (user_id, item) do update
    set equipped = true, source = 'coin';
  exception
    when undefined_table then
      null;
  end;

  select coalesce(jsonb_object_agg(item, qty), '{}'::jsonb)
  into v_owned
  from public.wallet_items
  where user_id = v_uid and qty > 0;

  return jsonb_build_object('ok', true, 'item', p_item, 'coins', v_coins, 'owned', v_owned);
end;
$$;

revoke all on function public.buy_gear(text) from public;
grant execute on function public.buy_gear(text) to authenticated;
