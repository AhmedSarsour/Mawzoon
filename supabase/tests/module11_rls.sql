-- Adversarial checks for the Module 11 schema. Plays guest A, guest B, staff S and a
-- no-session caller; every block raises 'FAIL: …' if a rule leaks. Always rolls back.
-- Run: psql "$(cat ~/.config/mawzoon/db_url)" -X -q -v ON_ERROR_STOP=1 -f supabase/tests/module11_rls.sql
begin;

-- ── Fixtures (as the owner) ──────────────────────────────────────────────────
insert into auth.users (id, aud, role, is_anonymous) values
  ('aaaaaaaa-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', true),
  ('bbbbbbbb-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', true),
  ('55555555-0000-0000-0000-000000000005', 'authenticated', 'authenticated', false);
update public.profiles set is_staff = true where id = '55555555-0000-0000-0000-000000000005';
update public.pricing set delivery_enabled = true, card_payment_enabled = true; -- shape tests below insert a delivery (rolled back)

insert into public.orders (id, idempotency_key, customer_id, order_type, payment_method,
  total_price_minor_units, total_calories, total_protein_g, total_carbs_g, total_fats_g)
values
  ('0a0a0a0a-0000-0000-0000-00000000000a', gen_random_uuid(),
   'aaaaaaaa-0000-0000-0000-00000000000a', 'PICKUP', 'counter', 6400, 550, 45, 50, 15),
  ('0b0b0b0b-0000-0000-0000-00000000000b', gen_random_uuid(),
   'bbbbbbbb-0000-0000-0000-00000000000b', 'PICKUP', 'counter', 6400, 550, 45, 50, 15);
-- New orders start unpaid (Module 12); these play paid ones already on the board.
select set_config('mawzoon.paying', 'on', true);
update public.orders set status = 'PENDING';
select set_config('mawzoon.paying', 'off', true);
insert into public.order_items (id, order_id, item_type, title, protein_id, protein_weight_g,
  carb_id, carb_weight_g, fiber_id, fiber_weight_g, volume_type, price_minor_units)
values
  ('1a1a1a1a-0000-0000-0000-00000000000a', '0a0a0a0a-0000-0000-0000-00000000000a',
   'CUSTOM_PLATE', 't', 'p', 150, 'c', 150, 'f', 80, 'STANDARD', 6400),
  ('1b1b1b1b-0000-0000-0000-00000000000b', '0b0b0b0b-0000-0000-0000-00000000000b',
   'CUSTOM_PLATE', 't', 'p', 150, 'c', 150, 'f', 80, 'STANDARD', 6400);
insert into public.raw_ingredients (id, name_ar, name_en, unit, storage_area, stock_minor_units)
values ('test.oil', 'زيت', 'Oil', 'millilitre', 'dryStore', 1000000);

-- Table constraints (owner bypasses RLS, so these test the shape, not the rules).
do $$ begin
  begin
    insert into public.orders (idempotency_key, customer_id, order_type, payment_method,
      total_price_minor_units, total_calories, total_protein_g, total_carbs_g, total_fats_g)
    values (gen_random_uuid(), 'aaaaaaaa-0000-0000-0000-00000000000a', 'DELIVERY', 'card',
      1, 1, 1, 1, 1);
    raise exception 'FAIL: delivery order without an address was accepted';
  exception when check_violation then null; end;
  begin
    update public.order_items set station_status = '{"oven": true}'
     where id = '1a1a1a1a-0000-0000-0000-00000000000a';
    raise exception 'FAIL: unknown station accepted';
  exception when check_violation then null; end;
  begin
    update public.order_items set source_signature_plate_id = 'sig.x'
     where id = '1a1a1a1a-0000-0000-0000-00000000000a';
    raise exception 'FAIL: custom plate with a chef-plate source accepted';
  exception when check_violation then null; end;
  if exists (select 1 from pg_class c where c.relnamespace = 'public'::regnamespace
             and c.relkind = 'r' and not c.relrowsecurity) then
    raise exception 'FAIL: a public table has RLS off';
  end if;
end $$;

-- ── Guest A ──────────────────────────────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a","role":"authenticated"}', true);

do $$
declare n int;
begin
  if (select count(*) from public.orders) <> 1 then
    raise exception 'FAIL: A sees % orders, expected only their own', (select count(*) from public.orders);
  end if;
  if exists (select 1 from public.orders where id = '0b0b0b0b-0000-0000-0000-00000000000b') then
    raise exception 'FAIL: A can read B''s order';
  end if;
  if exists (select 1 from public.order_items where order_id = '0b0b0b0b-0000-0000-0000-00000000000b') then
    raise exception 'FAIL: A can read B''s order items';
  end if;
  if (select count(*) from public.profiles) <> 1 then
    raise exception 'FAIL: A can read other profiles';
  end if;
  if exists (select 1 from public.raw_ingredients) then
    raise exception 'FAIL: guest can read stock counts';
  end if;

  update public.orders set status = 'ACCEPTED' where id = '0b0b0b0b-0000-0000-0000-00000000000b';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: A moved B''s order status'; end if;
  update public.orders set status = 'CANCELLED' where id = '0a0a0a0a-0000-0000-0000-00000000000a';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: a guest moved their own order status'; end if;

  begin
    update public.orders set total_price_minor_units = 1
     where id = '0a0a0a0a-0000-0000-0000-00000000000a';
    raise exception 'FAIL: guest rewrote a price';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.orders (idempotency_key, customer_id, order_type, payment_method,
      total_price_minor_units, total_calories, total_protein_g, total_carbs_g, total_fats_g)
    values (gen_random_uuid(), 'aaaaaaaa-0000-0000-0000-00000000000a', 'PICKUP', 'counter', 1, 1, 1, 1, 1);
    raise exception 'FAIL: guest inserted an order directly (price unchecked)';
  exception when insufficient_privilege then null; end;
  begin
    delete from public.orders where id = '0a0a0a0a-0000-0000-0000-00000000000a';
    raise exception 'FAIL: guest deleted an order';
  exception when insufficient_privilege then null; end;
  begin
    update public.profiles set is_staff = true where id = 'aaaaaaaa-0000-0000-0000-00000000000a';
    raise exception 'FAIL: guest promoted themselves to staff';
  exception when insufficient_privilege then null; end;
  begin
    perform public.set_station_status('1a1a1a1a-0000-0000-0000-00000000000a', 'grill', true);
    raise exception 'FAIL: guest marked a kitchen station';
  exception when insufficient_privilege then null; end;

  update public.profiles set phone = '+966500000000' where id = 'aaaaaaaa-0000-0000-0000-00000000000a';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FAIL: A cannot edit their own phone'; end if;
  update public.profiles set phone = 'x' where id = 'bbbbbbbb-0000-0000-0000-00000000000b';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL: A edited B''s profile'; end if;

  begin
    insert into public.raw_ingredients (id, name_ar, name_en, unit, storage_area)
    values ('test.hack', 'x', 'x', 'gram', 'chiller');
    raise exception 'FAIL: guest wrote stock';
  exception when insufficient_privilege then null; end;  -- RLS refusal on insert
  begin
    perform public.adjust_stock('test.oil', 1000);
    raise exception 'FAIL: guest adjusted stock';
  exception when insufficient_privilege then null; end;
  begin
    perform public.set_stock_count('test.oil', 1);
    raise exception 'FAIL: guest set a stock count';
  exception when insufficient_privilege then null; end;
end $$;

-- ── Staff S ──────────────────────────────────────────────────────────────────
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"55555555-0000-0000-0000-000000000005","role":"authenticated"}', true);

do $$
declare n int; s jsonb;
begin
  if (select count(*) from public.orders) <> 2 then
    raise exception 'FAIL: staff should see every order';
  end if;
  if not exists (select 1 from public.raw_ingredients where id = 'test.oil') then
    raise exception 'FAIL: staff cannot read stock';
  end if;

  update public.orders set status = 'ACCEPTED' where id = '0b0b0b0b-0000-0000-0000-00000000000b';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FAIL: staff cannot accept an order'; end if;
  begin
    update public.orders set status = 'PENDING' where id = '0b0b0b0b-0000-0000-0000-00000000000b';
    raise exception 'FAIL: status went backwards';
  exception when check_violation then null; end;
  begin
    update public.orders set status = 'COMPLETED' where id = '0a0a0a0a-0000-0000-0000-00000000000a';
    raise exception 'FAIL: status skipped from PENDING to COMPLETED';
  exception when check_violation then null; end;
  begin
    update public.orders set total_price_minor_units = 1
     where id = '0a0a0a0a-0000-0000-0000-00000000000a';
    raise exception 'FAIL: staff rewrote a price through the API';
  exception when insufficient_privilege then null; end;

  perform public.set_station_status('1a1a1a1a-0000-0000-0000-00000000000a', 'grill', true);
  perform public.set_station_status('1a1a1a1a-0000-0000-0000-00000000000a', 'prep', true);
  s := public.set_station_status('1a1a1a1a-0000-0000-0000-00000000000a', 'grill', true);
  if s <> '{"grill": true, "prep": true}'::jsonb then
    raise exception 'FAIL: station merge/replay gave %', s;
  end if;
  begin
    perform public.set_station_status('1a1a1a1a-0000-0000-0000-00000000000a', 'oven', true);
    raise exception 'FAIL: unknown station accepted via function';
  exception when check_violation then null; end;

  if public.set_stock_count('test.oil', 500000) <> 500000
     or public.adjust_stock('test.oil', 250000) <> 750000
     or public.adjust_stock('test.oil', -1000000) <> -250000 then
    raise exception 'FAIL: staff count / delivery / write-off arithmetic';
  end if;
  begin
    perform public.adjust_stock('test.nothing', 1);
    raise exception 'FAIL: adjusting a missing ingredient succeeded';
  exception when no_data_found then null; end;
end $$;

-- ── No session at all (anon key, not signed in) ──────────────────────────────
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
do $$ begin
  begin
    perform 1 from public.orders;
    raise exception 'FAIL: no-session caller can query orders';
  exception when insufficient_privilege then null; end;
  begin
    perform public.is_staff();
    raise exception 'FAIL: no-session caller can call functions';
  exception when insufficient_privilege then null; end;
end $$;

reset role;
select 'ALL MODULE 11 RLS CHECKS PASSED' as result;
rollback;
