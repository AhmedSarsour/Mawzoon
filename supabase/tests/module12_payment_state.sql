-- Module 12 part S: unpaid orders, cashier and card payment, expiry, refunds, strikes.
-- Plays guest A, guest B, staff S and the webhook (service_role). Always rolls back.
-- Run: psql "$(cat ~/.config/mawzoon/db_url)" -X -q -v ON_ERROR_STOP=1 -f supabase/tests/module12_payment_state.sql
begin;

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

create function pg_temp.plate() returns jsonb language sql as $$
  select jsonb_build_object(
    'order_type', 'PICKUP', 'payment_method', 'counter', 'volume', 'STANDARD',
    'protein_id', 'zz_test.protein', 'carb_id', 'zz_test.carb', 'fiber_id', 'zz_test.fiber',
    'title', 'طبقي', 'nutrition',
    jsonb_build_object('calories', 550, 'protein_g', 45, 'carbs_g', 50, 'fats_g', 15.5));
$$;

-- Owner-side reads and clock tricks (guests can't touch these, by design).
create function pg_temp.fp() returns text language sql security definer as $$
  select catalogue_fingerprint from public.pricing;
$$;
create function pg_temp.meat() returns bigint language sql security definer as $$
  select stock_minor_units from public.raw_ingredients where id = 'zz_test.meat';
$$;
create function pg_temp.o(p_id text) returns public.orders language sql security definer as $$
  select * from public.orders where id = p_id::uuid;
$$;
create function pg_temp.overdue(p_id text) returns void language sql security definer as $$
  update public.orders set payment_due_at = now() - interval '1 second' where id = p_id::uuid;
$$;
create function pg_temp.expire() returns integer language sql security definer as $$
  select private.expire_unpaid_orders();
$$;
create function pg_temp.pay_card(p_id text, p_txn text, p_amount integer, p_currency text default 'ILS')
returns text language plpgsql as $$
declare r jsonb;
begin
  set local role service_role;
  r := public.mark_paid_card(p_id::uuid, 'cardcom', p_txn, p_amount, p_currency, '{}'::jsonb);
  set local role authenticated;
  return r ->> 'result';
end $$;
create function pg_temp.payments(p_id text) returns text language sql security definer as $$
  select coalesce(string_agg(status, ',' order by created_at, status), '')
    from public.payments where order_id = p_id::uuid;
$$;
create function pg_temp.place(p_extra jsonb default '{}') returns text language sql as $$
  select public.place_order(pg_temp.plate() || p_extra, gen_random_uuid(), pg_temp.fp()) ->> 'order_id';
$$;

-- ── Fixtures ─────────────────────────────────────────────────────────────────
insert into auth.users (id, aud, role, is_anonymous) values
  ('aaaaaaaa-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', true),
  ('bbbbbbbb-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', true),
  ('55555555-0000-0000-0000-000000000005', 'authenticated', 'authenticated', false);
update public.profiles set is_staff = true where id = '55555555-0000-0000-0000-000000000005';
update public.pricing set delivery_enabled = true, card_payment_enabled = true;
insert into public.menu_components (component_id, segment, surcharge_minor_units, base_portion_grams)
values ('zz_test.protein', 'protein', 0, 100), ('zz_test.carb', 'smartCarb', 0, 100),
       ('zz_test.fiber', 'vitalFiber', 0, 100);
insert into public.raw_ingredients (id, name_ar, name_en, unit, storage_area, stock_minor_units)
values ('zz_test.meat', 'لحم', 'Meat', 'gram', 'chiller', 100000000);
insert into public.recipe_lines (component_id, ingredient_id, amount_minor_units) values
  ('zz_test.protein', 'zz_test.meat', 100000), ('zz_test.carb', 'zz_test.meat', 1000),
  ('zz_test.fiber', 'zz_test.meat', 1000);
create temp table t (k text primary key, v text);
grant all on t to authenticated;

set local role authenticated;

-- ── New orders start unpaid, with the right deadline ─────────────────────────
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-00000000000a');
do $$
declare v_id text; o public.orders;
begin
  v_id := pg_temp.place();
  insert into t values ('counter', v_id);
  o := pg_temp.o(v_id);
  if o.status <> 'AWAITING_PAYMENT' or o.paid_at is not null
     or o.payment_due_at not between now() + interval '44 minutes 59 seconds'
                                 and now() + interval '45 minutes 1 second' then
    raise exception 'FAIL: counter order should wait 45 min unpaid: % %', o.status, o.payment_due_at;
  end if;
  if pg_temp.meat() <> 100000000 - 102000 then
    raise exception 'FAIL: an unpaid order must hold its portions';
  end if;
end $$;

-- ── Staff can't skip the till ────────────────────────────────────────────────
select pg_temp.act_as('55555555-0000-0000-0000-000000000005');
do $$
declare n int;
begin
  -- The kitchen board's query (kitchenActiveStatuses) doesn't see it.
  select count(*) into n from public.orders
   where id = (select v::uuid from t where k = 'counter')
     and status in ('PENDING', 'ACCEPTED', 'ASSEMBLING', 'READY');
  if n <> 0 then raise exception 'FAIL: kitchen board sees an unpaid order'; end if;

  begin
    update public.orders set status = 'PENDING' where id = (select v::uuid from t where k = 'counter');
    raise exception 'FAIL: staff marked an order paid by hand';
  exception when check_violation then null; end;
  begin
    update public.orders set status = 'ACCEPTED' where id = (select v::uuid from t where k = 'counter');
    raise exception 'FAIL: kitchen accepted an unpaid order';
  exception when check_violation then null; end;
end $$;
select pg_temp.expect_error(
  format($q$select public.mark_paid_card(%L, 'cardcom', 'x', 4900, 'ILS')$q$,
    (select v from t where k = 'counter')),
  'permission denied for function mark_paid_card');

-- ── Guests can't pay themselves or read payments ─────────────────────────────
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-00000000000a');
select pg_temp.expect_error(
  format($q$select public.mark_paid_counter(%L)$q$, (select v from t where k = 'counter')),
  'staff only');
select pg_temp.expect_error(
  format($q$select public.mark_paid_card(%L, 'cardcom', 'x', 4900, 'ILS')$q$,
    (select v from t where k = 'counter')),
  'permission denied for function mark_paid_card');
select pg_temp.expect_error(
  $q$select pg_temp.place('{"payment_method":"card"}')$q$, 'unpaid_order_open');

-- ── The cashier takes the money ──────────────────────────────────────────────
select pg_temp.act_as('55555555-0000-0000-0000-000000000005');
do $$
declare r jsonb; v_id text := (select v from t where k = 'counter');
begin
  r := public.mark_paid_counter(v_id::uuid);
  if (r ->> 'already_paid')::boolean or r ->> 'status' <> 'PENDING' then
    raise exception 'FAIL: first tap should pay: %', r;
  end if;
  r := public.mark_paid_counter(v_id::uuid);
  if not (r ->> 'already_paid')::boolean then
    raise exception 'FAIL: second tap should be a no-op: %', r;
  end if;
  if (select count(*) from public.payments
       where order_id = v_id::uuid and status = 'paid' and method = 'counter'
         and amount_minor_units = 4900 and currency = 'ILS'
         and staff_id = '55555555-0000-0000-0000-000000000005') <> 1 then
    raise exception 'FAIL: counter payment not recorded once with the cashier';
  end if;
  if (pg_temp.o(v_id)).paid_at is null then raise exception 'FAIL: paid_at not set'; end if;
end $$;

-- ── Card: webhook pays, duplicates are harmless, wrong money is a refund ─────
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-00000000000a');
do $$
declare v_id text; res text;
begin
  v_id := pg_temp.place('{"payment_method":"card"}');
  insert into t values ('card', v_id);
  if (pg_temp.o(v_id)).payment_due_at > now() + interval '15 minutes 1 second' then
    raise exception 'FAIL: card hold should be 15 min';
  end if;
  res := pg_temp.pay_card(v_id, 'txn-wrong', 4800);
  if res <> 'amount_mismatch' or (pg_temp.o(v_id)).status <> 'AWAITING_PAYMENT' then
    raise exception 'FAIL: short payment must not pay the order: %', res;
  end if;
  res := pg_temp.pay_card(v_id, 'txn-usd', 4900, 'USD');
  if res <> 'amount_mismatch' then raise exception 'FAIL: wrong currency accepted: %', res; end if;
  -- Past its deadline but not swept yet: the money moved, the stock is still held → paid.
  perform pg_temp.overdue(v_id);
  res := pg_temp.pay_card(v_id, 'txn-1', 4900);
  if res <> 'paid' or (pg_temp.o(v_id)).status <> 'PENDING' then
    raise exception 'FAIL: good card payment did not pay: %', res;
  end if;
  res := pg_temp.pay_card(v_id, 'txn-1', 4900);
  if res <> 'duplicate' then raise exception 'FAIL: replayed webhook: %', res; end if;
  res := pg_temp.pay_card(v_id, 'txn-2', 4900);
  if res <> 'already_paid' then raise exception 'FAIL: second charge: %', res; end if;
  if pg_temp.payments(v_id) <> 'needs_refund,needs_refund,needs_refund,paid' then
    raise exception 'FAIL: payments %', pg_temp.payments(v_id);
  end if;
end $$;

-- ── Expiry: stock back, late card money becomes a refund ─────────────────────
-- Guest B has no history, so the strike count below starts clean.
select pg_temp.act_as('bbbbbbbb-0000-0000-0000-00000000000b');
do $$
declare v_id text; before bigint; n int;
begin
  before := pg_temp.meat();
  v_id := pg_temp.place();
  insert into t values ('late', v_id);
  perform pg_temp.overdue(v_id);
  -- Past due: no longer blocks a new order...
  insert into t values ('fresh', pg_temp.place('{"payment_method":"card"}'));
end $$;

select pg_temp.act_as('55555555-0000-0000-0000-000000000005');
-- ...and the counter won't take it, even before the timer runs.
select pg_temp.expect_error(
  format($q$select public.mark_paid_counter(%L)$q$, (select v from t where k = 'late')),
  'order_expired');
do $$
declare n int; before bigint := pg_temp.meat();
begin
  n := pg_temp.expire();
  if n < 1 or (pg_temp.o((select v from t where k = 'late'))).status <> 'CANCELLED'
     or (pg_temp.o((select v from t where k = 'late'))).cancel_reason <> 'expired' then
    raise exception 'FAIL: overdue order not expired (%)', n;
  end if;
  if pg_temp.meat() <> before + 102000 then
    raise exception 'FAIL: expiry did not give the stock back: % → %', before, pg_temp.meat();
  end if;
  if (pg_temp.o((select v from t where k = 'fresh'))).status <> 'AWAITING_PAYMENT' then
    raise exception 'FAIL: expiry took an order that still had time';
  end if;
  if pg_temp.expire() <> 0 or pg_temp.meat() <> before + 102000 then
    raise exception 'FAIL: second sweep did something';
  end if;
end $$;
select pg_temp.expect_error(
  format($q$select public.mark_paid_counter(%L)$q$, (select v from t where k = 'late')),
  'order_expired');
do $$ begin
  if pg_temp.pay_card((select v from t where k = 'late'), 'txn-late', 4900) <> 'order_cancelled'
     or (pg_temp.o((select v from t where k = 'late'))).status <> 'CANCELLED' then
    raise exception 'FAIL: late card payment revived an expired order';
  end if;
end $$;

-- ── Guest cancels unpaid; staff cancelling a paid order flags a refund ────────
select pg_temp.act_as('bbbbbbbb-0000-0000-0000-00000000000b');
do $$
declare r jsonb;
begin
  r := public.cancel_order((select v from t where k = 'fresh')::uuid);
  if not (r ->> 'restored')::boolean
     or (pg_temp.o((select v from t where k = 'fresh'))).cancel_reason <> 'guest' then
    raise exception 'FAIL: guest cancel of unpaid order: %', r;
  end if;
end $$;
select pg_temp.act_as('55555555-0000-0000-0000-000000000005');
select pg_temp.expect_error(
  format($q$select public.mark_paid_counter(%L)$q$, (select v from t where k = 'fresh')),
  'order_cancelled');
do $$
declare v_id text := (select v from t where k = 'counter');
begin
  perform public.cancel_order(v_id::uuid);
  if pg_temp.payments(v_id) <> 'needs_refund' or (pg_temp.o(v_id)).cancel_reason <> 'staff' then
    raise exception 'FAIL: cancelling a paid order should flag its payment: %', pg_temp.payments(v_id);
  end if;
  if (select count(*) from public.payments where status = 'needs_refund') < 1 then
    raise exception 'FAIL: staff cannot read the refund list';
  end if;
end $$;

-- ── Delivery is never paid at the counter ────────────────────────────────────
select pg_temp.act_as('aaaaaaaa-0000-0000-0000-00000000000a');
insert into t values ('delivery', pg_temp.place(
  '{"order_type":"DELIVERY","payment_method":"card","delivery_address":"شارع الجبل","customer_phone":"0501234567"}'));
select pg_temp.act_as('55555555-0000-0000-0000-000000000005');
select pg_temp.expect_error(
  format($q$select public.mark_paid_counter(%L)$q$, (select v from t where k = 'delivery')),
  'card_required');

-- ── C4: three walk-aways in 7 days → card only ───────────────────────────────
select pg_temp.act_as('bbbbbbbb-0000-0000-0000-00000000000b');
do $$
declare v_id text; i int;
begin
  -- 'late' already expired once; two more makes three.
  for i in 1..2 loop
    v_id := pg_temp.place();
    perform pg_temp.overdue(v_id);
    perform pg_temp.expire();
  end loop;
  perform pg_temp.expect_error($q$select pg_temp.place()$q$, 'counter_blocked');
  perform pg_temp.place('{"payment_method":"card"}');  -- card still works
end $$;
reset role;
-- An old strike drops out of the window.
update public.orders set created_at = now() - interval '8 days'
 where id = (select v::uuid from t where k = 'late');
set local role authenticated;
select pg_temp.act_as('bbbbbbbb-0000-0000-0000-00000000000b');
do $$ begin
  perform public.cancel_order(id) from public.orders
   where customer_id = 'bbbbbbbb-0000-0000-0000-00000000000b' and status = 'AWAITING_PAYMENT';
  perform pg_temp.place();
end $$;

reset role;
select 'ALL MODULE 12 PAYMENT CHECKS PASSED' as result;
rollback;
