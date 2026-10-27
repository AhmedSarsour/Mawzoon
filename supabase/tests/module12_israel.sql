-- Module 12 part L: launch switches, payment rules, VAT-inclusive quote. Always rolls back.
-- Run: psql "$(cat ~/.config/mawzoon/db_url)" -X -q -v ON_ERROR_STOP=1 -f supabase/tests/module12_israel.sql
begin;

create function pg_temp.expect_error(p_sql text, p_message text) returns void
language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FAIL: expected "%" from: %', p_message, p_sql;
exception when others then
  if sqlerrm like 'FAIL:%' then raise; end if;
  if sqlerrm <> p_message then
    raise exception 'FAIL: expected "%", got "%" from: %', p_message, sqlerrm, p_sql;
  end if;
end $$;

-- One order row straight into the table (as owner): the trigger guards every path.
create function pg_temp.insert_order(p_type text, p_payment text) returns void
language plpgsql as $$
begin
  execute format($f$insert into public.orders (idempotency_key, customer_id, order_type,
    payment_method, delivery_address, customer_phone, total_price_minor_units,
    total_calories, total_protein_g, total_carbs_g, total_fats_g)
    values (gen_random_uuid(), 'aaaaaaaa-0000-0000-0000-00000000000a', %L, %L,
      'شارع الجبل', '+972500000000', 4900, 550, 45, 50, 15)$f$, p_type, p_payment);
end $$;

insert into auth.users (id, aud, role, is_anonymous) values
  ('aaaaaaaa-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', true);

do $$
declare q record;
begin
  -- Switches off, as live today.
  update public.pricing set delivery_enabled = false, card_payment_enabled = false;
  perform pg_temp.insert_order('PICKUP', 'counter');
  perform pg_temp.expect_error($q$select pg_temp.insert_order('DELIVERY', 'card')$q$, 'delivery_unavailable');
  perform pg_temp.expect_error($q$select pg_temp.insert_order('PICKUP', 'card')$q$, 'card_unavailable');
  perform pg_temp.expect_error($q$select pg_temp.insert_order('PICKUP', 'cash')$q$, 'invalid_payload');
  perform pg_temp.expect_error($q$select pg_temp.insert_order('PICKUP', 'wallet')$q$, 'invalid_payload');

  -- Switches on: card works, delivery works by card only.
  update public.pricing set delivery_enabled = true, card_payment_enabled = true;
  perform pg_temp.insert_order('PICKUP', 'card');
  perform pg_temp.insert_order('DELIVERY', 'card');
  perform pg_temp.expect_error($q$select pg_temp.insert_order('DELIVERY', 'counter')$q$, 'card_required');

  -- VAT is inside the price: 49.00 holds 7.47; 61.00 holds 9.31.
  select * into q from private.quote_plate('protein.herb_grilled_breast', 'carb.steamed_basmati',
    'fiber.charred_garden_veggies', 'STANDARD', 'PICKUP');
  if q.total_minor_units <> 4900 or q.tax_minor_units <> 747 then
    raise exception 'FAIL: pickup quote %/%, expected 4900/747', q.total_minor_units, q.tax_minor_units;
  end if;
  select * into q from private.quote_plate('protein.herb_grilled_breast', 'carb.steamed_basmati',
    'fiber.charred_garden_veggies', 'STANDARD', 'DELIVERY');
  if q.total_minor_units <> 6100 or q.tax_minor_units <> 931 then
    raise exception 'FAIL: delivery quote %/%, expected 6100/931', q.total_minor_units, q.tax_minor_units;
  end if;
end $$;

select 'ALL MODULE 12 ISRAEL CHECKS PASSED' as result;
rollback;
