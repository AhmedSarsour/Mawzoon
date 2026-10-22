-- place_order / cancel_order / menu_availability, one session. Uses its own zz_test.*
-- components so real stock is never touched. Raises 'FAIL: …' on any wrong answer.
-- Always rolls back. Needs the seed applied (pricing row + scale factors).
begin;

-- ── Helpers ──────────────────────────────────────────────────────────────────
create function pg_temp.expect_error(p_sql text, p_message text) returns void
language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FAIL: expected "%" from: %', p_message, p_sql;
exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if sqlerrm <> p_message then
    raise exception 'FAIL: expected "%", got "%" (%) from: %', p_message, sqlerrm, sqlstate, p_sql;
  end if;
end $$;

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

-- A valid pickup of the test plate. Tests override fields with ||.
create function pg_temp.plate() returns jsonb language sql as $$
  select jsonb_build_object(
    'order_type', 'PICKUP', 'payment_method', 'cash', 'volume', 'STANDARD',
    'protein_id', 'zz_test.protein', 'carb_id', 'zz_test.carb', 'fiber_id', 'zz_test.fiber',
    'title', 'طبقي', 'nutrition',
    jsonb_build_object('calories', 550, 'protein_g', 45, 'carbs_g', 50, 'fats_g', 15.5));
$$;

-- Guests can't read pricing or stock (by design), so these read as the owner.
create function pg_temp.fp() returns text language sql security definer as $$
  select catalogue_fingerprint from public.pricing;
$$;

create function pg_temp.stock(p_id text) returns bigint language sql security definer as $$
  select stock_minor_units from public.raw_ingredients where id = p_id;
$$;

-- ── Fixtures (as owner) ──────────────────────────────────────────────────────
insert into auth.users (id, aud, role, is_anonymous) values
  ('aaaaaaaa-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', true),
  ('bbbbbbbb-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', true),
  ('55555555-0000-0000-0000-000000000005', 'authenticated', 'authenticated', false);
update public.profiles set is_staff = true where id = '55555555-0000-0000-0000-000000000005';

insert into public.menu_components (component_id, segment, surcharge_minor_units, base_portion_grams)
values ('zz_test.protein', 'protein', 0, 100), ('zz_test.carb', 'smartCarb', 0, 100),
       ('zz_test.fiber', 'vitalFiber', 0, 100);
-- 6 standard portions of meat: buffer is 5, so two orders sell and the third is sold out.
insert into public.raw_ingredients (id, name_ar, name_en, unit, storage_area, stock_minor_units)
values ('zz_test.meat', 'لحم', 'Meat', 'gram', 'chiller', 600000),
       ('zz_test.grain', 'حب', 'Grain', 'gram', 'dryStore', 10000000),
       ('zz_test.leaf', 'ورق', 'Leaf', 'gram', 'produce', 10000000),
       ('zz_test.oil', 'زيت', 'Oil', 'millilitre', 'dryStore', 1000000);
insert into public.recipe_lines (component_id, ingredient_id, amount_minor_units) values
  ('zz_test.protein', 'zz_test.meat', 100000), ('zz_test.protein', 'zz_test.oil', 1000),
  ('zz_test.carb', 'zz_test.grain', 50000), ('zz_test.carb', 'zz_test.oil', 1000),
  ('zz_test.fiber', 'zz_test.leaf', 10000), ('zz_test.fiber', 'zz_test.oil', 1000);

-- ── No session ───────────────────────────────────────────────────────────────
set local role authenticated;
select pg_temp.expect_error(
  $q$select public.place_order(pg_temp.plate(), gen_random_uuid(), pg_temp.fp())$q$,
  'not_signed_in');

-- ── Guest A: validation ──────────────────────────────────────────────────────
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-00000000000a');
do $$ begin
  perform pg_temp.expect_error(
    $q$select public.place_order(pg_temp.plate(), gen_random_uuid(), 'stale')$q$, 'menu_changed');
  perform pg_temp.expect_error(
    $q$select public.place_order(pg_temp.plate() || '{"volume":"HUGE"}', gen_random_uuid(), pg_temp.fp())$q$,
    'invalid_payload');
  perform pg_temp.expect_error(
    $q$select public.place_order(pg_temp.plate() || '{"nutrition":{"calories":99999,"protein_g":1,"carbs_g":1,"fats_g":1}}', gen_random_uuid(), pg_temp.fp())$q$,
    'invalid_payload');
  perform pg_temp.expect_error(
    $q$select public.place_order(pg_temp.plate() - 'title', gen_random_uuid(), pg_temp.fp())$q$,
    'invalid_payload');
  perform pg_temp.expect_error(
    $q$select public.place_order(pg_temp.plate() || '{"protein_id":"zz_test.carb"}', gen_random_uuid(), pg_temp.fp())$q$,
    'invalid_plate');
  perform pg_temp.expect_error(
    $q$select public.place_order(pg_temp.plate() || '{"protein_id":"nope"}', gen_random_uuid(), pg_temp.fp())$q$,
    'invalid_plate');
  perform pg_temp.expect_error(
    $q$select public.place_order(pg_temp.plate() || '{"signature_plate_id":"signature.ember_standard"}', gen_random_uuid(), pg_temp.fp())$q$,
    'invalid_plate');
  perform pg_temp.expect_error(
    $q$select public.place_order(pg_temp.plate() || '{"order_type":"DELIVERY","customer_phone":"0500000000"}', gen_random_uuid(), pg_temp.fp())$q$,
    'needs_address');
  perform pg_temp.expect_error(
    $q$select public.place_order(pg_temp.plate() || '{"order_type":"DELIVERY","delivery_address":"الرياض"}', gen_random_uuid(), pg_temp.fp())$q$,
    'needs_phone');
  perform pg_temp.expect_error(
    $q$select public.place_order(pg_temp.plate() || '{"order_type":"DELIVERY","delivery_address":"الرياض","customer_phone":"call me"}', gen_random_uuid(), pg_temp.fp())$q$,
    'needs_phone');
  if pg_temp.stock('zz_test.meat') <> 600000 then
    raise exception 'FAIL: a refused order still took stock';
  end if;
end $$;

-- ── Guest A: a real order, then a replay ─────────────────────────────────────
create temp table t (k text primary key, v jsonb);
do $$
declare r jsonb;
begin
  r := public.place_order(pg_temp.plate(), '00000000-0000-0000-0000-0000000000a1', pg_temp.fp());
  insert into t values ('a1', r);
  if (r ->> 'total_minor_units')::int <> 5635 or (r ->> 'replayed')::boolean then
    raise exception 'FAIL: pickup total %, expected 5635 (4900 + 15%% VAT)', r;
  end if;
  if pg_temp.stock('zz_test.meat') <> 500000 or pg_temp.stock('zz_test.oil') <> 997000 then
    raise exception 'FAIL: draw wrong: meat %, oil %',
      pg_temp.stock('zz_test.meat'), pg_temp.stock('zz_test.oil');
  end if;

  r := public.place_order(pg_temp.plate() || '{"volume":"ATHLETIC"}',
    '00000000-0000-0000-0000-0000000000a1', pg_temp.fp());
  if not (r ->> 'replayed')::boolean or r ->> 'order_id' <> (select v ->> 'order_id' from t where k = 'a1') then
    raise exception 'FAIL: replay did not return the first order: %', r;
  end if;
  if pg_temp.stock('zz_test.meat') <> 500000 then
    raise exception 'FAIL: replay took stock again';
  end if;

  r := public.place_order(pg_temp.plate() || '{"order_type":"DELIVERY","delivery_address":"حي العليا","customer_phone":"+966 50-000-0000"}',
    '00000000-0000-0000-0000-0000000000a2', pg_temp.fp());
  insert into t values ('a2', r);
  if (r ->> 'total_minor_units')::int <> 7015 then
    raise exception 'FAIL: delivery total %, expected 7015', r;
  end if;
  if (select customer_phone from public.orders where id = (r ->> 'order_id')::uuid) <> '+966500000000' then
    raise exception 'FAIL: phone not normalised';
  end if;
  if (select count(*) from public.orders) <> 2 or (select count(*) from public.order_items) <> 2 then
    raise exception 'FAIL: guest should see exactly their 2 orders';
  end if;
  if (select protein_weight_g from public.order_items
       where order_id = (r ->> 'order_id')::uuid) <> 100.0 then
    raise exception 'FAIL: kitchen weight not computed server-side';
  end if;
end $$;

-- Meat is now at 4 portions, under the buffer of 5: sold out, named, nothing taken.
select pg_temp.expect_error(
  $q$select public.place_order(pg_temp.plate(), gen_random_uuid(), pg_temp.fp())$q$, 'sold_out');
do $$ begin
  if pg_temp.stock('zz_test.meat') <> 400000 then
    raise exception 'FAIL: sold-out order took stock';
  end if;
  if (select status from public.menu_availability() where component_id = 'zz_test.protein') <> 'soldOut' then
    raise exception 'FAIL: availability does not say sold out';
  end if;
  if (select status from public.menu_availability() where component_id = 'zz_test.carb') <> 'inStock' then
    raise exception 'FAIL: availability wrong for an untouched component';
  end if;
end $$;

-- Guests can't reach the helpers, the draw ledger or prices.
select pg_temp.expect_error($q$select * from private.quote_plate('a','b','c','STANDARD','PICKUP')$q$,
  'permission denied for schema private');
do $$ begin
  if exists (select 1 from public.order_draws) or exists (select 1 from public.pricing) then
    raise exception 'FAIL: guest can read draws or pricing';
  end if;
end $$;

-- ── Guest B ──────────────────────────────────────────────────────────────────
select pg_temp.act_as('bbbbbbbb-0000-0000-0000-00000000000b');
select pg_temp.expect_error(
  $q$select public.place_order(pg_temp.plate(), '00000000-0000-0000-0000-0000000000a1', pg_temp.fp())$q$,
  'idempotency_conflict');
select pg_temp.expect_error(
  format($q$select public.cancel_order(%L)$q$, (select v ->> 'order_id' from t where k = 'a1')),
  'not_found');
select pg_temp.expect_error(
  $q$select public.cancel_order(gen_random_uuid())$q$, 'not_found');

-- ── Guest A cancels a PENDING order: stock back once ─────────────────────────
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-00000000000a');
do $$
declare r jsonb;
begin
  r := public.cancel_order((select v ->> 'order_id' from t where k = 'a1')::uuid);
  if not (r ->> 'restored')::boolean or pg_temp.stock('zz_test.meat') <> 500000
     or pg_temp.stock('zz_test.oil') <> 994000 + 3000 then
    raise exception 'FAIL: cancel did not restore exactly the draw: % meat % oil %',
      r, pg_temp.stock('zz_test.meat'), pg_temp.stock('zz_test.oil');
  end if;
  r := public.cancel_order((select v ->> 'order_id' from t where k = 'a1')::uuid);
  if (r ->> 'restored')::boolean or pg_temp.stock('zz_test.meat') <> 500000 then
    raise exception 'FAIL: second cancel restored again';
  end if;
end $$;

-- ── Staff ────────────────────────────────────────────────────────────────────
select pg_temp.act_as('55555555-0000-0000-0000-000000000005');
select pg_temp.expect_error(
  format($q$update public.orders set status = 'CANCELLED' where id = %L$q$,
    (select v ->> 'order_id' from t where k = 'a2')),
  format('cancel order %s with cancel_order(), so its stock is put back',
    (select v ->> 'order_number' from t where k = 'a2')));
update public.orders set status = 'ACCEPTED' where id = (select (v ->> 'order_id')::uuid from t where k = 'a2');

select pg_temp.act_as('aaaaaaaa-0000-0000-0000-00000000000a');
select pg_temp.expect_error(
  format($q$select public.cancel_order(%L)$q$, (select v ->> 'order_id' from t where k = 'a2')),
  'too_late_to_cancel');

select pg_temp.act_as('55555555-0000-0000-0000-000000000005');
do $$
declare r jsonb;
begin
  update public.orders set status = 'ASSEMBLING' where id = (select (v ->> 'order_id')::uuid from t where k = 'a2');
  r := public.cancel_order((select v ->> 'order_id' from t where k = 'a2')::uuid);
  if (r ->> 'restored')::boolean or pg_temp.stock('zz_test.meat') <> 500000 then
    raise exception 'FAIL: an order already being cooked gave its stock back';
  end if;
end $$;

-- Taken off by hand wins over stock.
reset role;
insert into public.component_settings (component_id, forced_off) values ('zz_test.carb', true);
set local role authenticated;
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-00000000000a');
do $$
declare v_detail text; v_hint text;
begin
  -- Meat is back at exactly 5 portions (the buffer), so protein sells; carb is the blocker.
  begin
    perform public.place_order(pg_temp.plate(), gen_random_uuid(), pg_temp.fp());
    raise exception 'FAIL: forced-off component sold';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
    get stacked diagnostics v_detail = pg_exception_detail, v_hint = pg_exception_hint;
    if sqlerrm <> 'sold_out' or v_detail <> 'zz_test.carb' or v_hint <> 'takenOff' then
      raise exception 'FAIL: got % / % / %', sqlerrm, v_detail, v_hint;
    end if;
  end;
  if (select sold_out_reason from public.menu_availability() where component_id = 'zz_test.carb') <> 'takenOff' then
    raise exception 'FAIL: reason should be takenOff';
  end if;
end $$;

reset role;
select 'ALL PLACE_ORDER CHECKS PASSED' as result;
rollback;
