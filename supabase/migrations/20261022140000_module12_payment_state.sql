-- Module 12, part S: no food is made before money is taken.
-- Every order starts AWAITING_PAYMENT (the kitchen board doesn't list it). Only
-- mark_paid_counter (cashier) or mark_paid_card (payment webhook) move it to PENDING.
-- Unpaid orders expire on a timer and give their stock back.

-- The tunable rules, in one place.
create or replace function private.payment_rules()
returns table (counter_hold interval, card_hold interval,
               strike_limit integer, strike_window interval)
language sql immutable set search_path = '' as $$
  select interval '45 minutes', interval '15 minutes', 3, interval '7 days';
$$;

-- ── Orders: payment columns ──────────────────────────────────────────────────
alter table public.orders
  add column if not exists payment_due_at timestamptz,
  add column if not exists paid_at timestamptz,
  add column if not exists cancel_reason text
    check (cancel_reason in ('guest', 'staff', 'expired'));
alter table public.orders alter column status set default 'AWAITING_PAYMENT';
create index if not exists orders_awaiting_due_idx on public.orders (payment_due_at)
  where status = 'AWAITING_PAYMENT';

-- ── S3: payments ─────────────────────────────────────────────────────────────
-- Money that moved. Clients can't write it; only the functions below do.
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id),
  method public.payment_method not null,
  provider text not null check (char_length(provider) <= 40),
  provider_txn_id text check (char_length(provider_txn_id) <= 120),
  amount_minor_units integer not null check (amount_minor_units >= 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  status text not null check (status in ('paid', 'needs_refund', 'refunded')),
  staff_id uuid references public.profiles (id),
  raw jsonb,
  created_at timestamptz not null default now(),
  -- A webhook replayed by the provider can't record the same charge twice.
  unique (provider, provider_txn_id)
);
-- An order is paid at most once; a second charge is a refund to make, not a payment.
create unique index if not exists payments_one_paid_per_order
  on public.payments (order_id) where status = 'paid';
create index if not exists payments_needs_refund_idx
  on public.payments (created_at) where status = 'needs_refund';

alter table public.payments enable row level security;
revoke all on public.payments from anon, authenticated;
grant select on public.payments to authenticated;
drop policy if exists "staff: read" on public.payments;
create policy "staff: read" on public.payments for select to authenticated
  using ((select public.is_staff()));

-- ── Status rules ─────────────────────────────────────────────────────────────
-- Forward only. Paying and cancelling each need their function's flag, so a staff
-- client can't mark an order paid (or drop it without returning stock) by hand.
create or replace function public.guard_order_status()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status = old.status then return new; end if;
  if not (
       (old.status = 'AWAITING_PAYMENT' and new.status in ('PENDING', 'CANCELLED'))
    or (old.status = 'PENDING'    and new.status in ('ACCEPTED', 'CANCELLED'))
    or (old.status = 'ACCEPTED'   and new.status in ('ASSEMBLING', 'CANCELLED'))
    or (old.status = 'ASSEMBLING' and new.status in ('READY', 'CANCELLED'))
    or (old.status = 'READY'      and new.status in ('COMPLETED', 'CANCELLED'))
  ) then
    raise exception 'order % cannot go from % to %', old.order_number, old.status, new.status
      using errcode = 'check_violation';
  end if;
  if old.status = 'AWAITING_PAYMENT' and new.status = 'PENDING'
     and coalesce(current_setting('mawzoon.paying', true), '') <> 'on' then
    raise exception 'order % is paid only through mark_paid_counter() or mark_paid_card()',
      old.order_number using errcode = 'check_violation';
  end if;
  if new.status = 'CANCELLED'
     and coalesce(current_setting('mawzoon.cancelling', true), '') <> 'on' then
    raise exception 'cancel order % with cancel_order(), so its stock is put back',
      old.order_number using errcode = 'check_violation';
  end if;
  new.updated_at := now();
  return new;
end $$;

-- Every new order, whatever inserts it: the part L rules, then it starts unpaid
-- with a deadline. Set here, not in place_order, so no insert path can skip it.
create or replace function private.check_new_order()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  pr public.pricing;
  rules record;
begin
  select * into strict pr from public.pricing;
  select * into rules from private.payment_rules();
  if new.payment_method::text not in ('counter', 'card') then
    raise exception using errcode = 'P0001', message = 'invalid_payload', detail = 'payment method';
  end if;
  if new.order_type = 'DELIVERY' and not pr.delivery_enabled then
    raise exception using errcode = 'P0001', message = 'delivery_unavailable';
  end if;
  if new.payment_method::text = 'card' and not pr.card_payment_enabled then
    raise exception using errcode = 'P0001', message = 'card_unavailable';
  end if;
  if new.order_type = 'DELIVERY' and new.payment_method::text = 'counter' then
    raise exception using errcode = 'P0001', message = 'card_required';
  end if;
  new.status := 'AWAITING_PAYMENT';
  new.paid_at := null;
  new.cancel_reason := null;
  new.payment_due_at := now() + case when new.payment_method::text = 'card'
                                     then rules.card_hold else rules.counter_hold end;
  return new;
end $$;

-- ── Cancelling (guest, staff, expiry): one path ──────────────────────────────
-- Caller holds the order rows' locks. Stock goes back for anything not yet cooking
-- (InventoryLedger.restore); a payment already taken becomes a refund to make.
create or replace function private.cancel_orders(p_ids uuid[], p_reason text)
returns integer language plpgsql volatile set search_path = '' as $$
declare v_restore uuid[];
begin
  select array_agg(id) into v_restore from public.orders
   where id = any (p_ids) and status in ('AWAITING_PAYMENT', 'PENDING', 'ACCEPTED');

  -- Same lock order as place_order (ingredient id), so the two queue, never deadlock.
  perform 1 from public.raw_ingredients
   where id in (select ingredient_id from public.order_draws where order_id = any (v_restore))
   order by id
     for update;

  perform set_config('mawzoon.cancelling', 'on', true);
  update public.orders set status = 'CANCELLED', cancel_reason = p_reason
   where id = any (p_ids) and status <> 'CANCELLED';
  perform set_config('mawzoon.cancelling', 'off', true);

  update public.raw_ingredients ri
     set stock_minor_units = ri.stock_minor_units + d.amount, updated_at = now()
    from (select ingredient_id, sum(amount_minor_units) as amount
            from public.order_draws where order_id = any (v_restore)
           group by ingredient_id) d
   where ri.id = d.ingredient_id;

  update public.payments set status = 'needs_refund'
   where order_id = any (p_ids) and status = 'paid';
  return coalesce(cardinality(v_restore), 0);
end $$;

-- Guest: own order, only while unpaid (once paid, cancelling means a refund — staff).
-- Staff: any order not yet completed.
create or replace function public.cancel_order(p_order_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_staff boolean := public.is_staff();
  v_status public.order_status;
  v_customer uuid;
  v_restored integer;
begin
  if v_uid is null then
    raise exception using errcode = 'P0001', message = 'not_signed_in';
  end if;
  -- A second cancel waits on this lock, then sees CANCELLED and restores nothing.
  select status, customer_id into v_status, v_customer
    from public.orders where id = p_order_id for update;
  if not found or (v_customer <> v_uid and not v_staff) then
    -- Same answer whether the order is missing or someone else's: no enumeration.
    raise exception using errcode = 'P0001', message = 'not_found';
  end if;
  if v_status = 'CANCELLED' then
    return jsonb_build_object('status', 'CANCELLED', 'restored', false);
  end if;
  if not v_staff and v_status <> 'AWAITING_PAYMENT' then
    raise exception using errcode = 'P0001', message = 'too_late_to_cancel';
  end if;
  -- COMPLETED is refused by guard_order_status inside cancel_orders.
  v_restored := private.cancel_orders(array[p_order_id],
                  case when v_customer = v_uid and not v_staff then 'guest' else 'staff' end);
  return jsonb_build_object('status', 'CANCELLED', 'restored', v_restored > 0);
end $$;

-- ── S4: expiry ───────────────────────────────────────────────────────────────
-- Run every minute by pg_cron. SKIP LOCKED: an order a cashier or webhook is paying
-- right now is left for the next run. Capped so one run stays short.
create or replace function private.expire_unpaid_orders()
returns integer language plpgsql volatile set search_path = '' as $$
declare v_ids uuid[];
begin
  select array_agg(id) into v_ids from (
    select id from public.orders
     where status = 'AWAITING_PAYMENT' and payment_due_at <= now()
     order by payment_due_at
     limit 200
       for update skip locked) due;
  if v_ids is null then return 0; end if;
  perform private.cancel_orders(v_ids, 'expired');
  return cardinality(v_ids);
end $$;

-- ── S6: the cashier takes the money ──────────────────────────────────────────
-- Errors: staff only, not_found, order_expired, order_cancelled, card_required.
-- Paying twice (double tap, two cashiers) answers already_paid and changes nothing.
create or replace function public.mark_paid_counter(p_order_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare o public.orders;
begin
  if not public.is_staff() then
    raise exception 'staff only' using errcode = 'insufficient_privilege';
  end if;
  select * into o from public.orders where id = p_order_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'not_found';
  end if;
  if o.status = 'CANCELLED' then
    raise exception using errcode = 'P0001',
      message = case when o.cancel_reason = 'expired' then 'order_expired' else 'order_cancelled' end;
  end if;
  if o.status <> 'AWAITING_PAYMENT' then
    return jsonb_build_object('status', o.status, 'already_paid', true);
  end if;
  if o.order_type = 'DELIVERY' then
    raise exception using errcode = 'P0001', message = 'card_required';
  end if;
  -- Strict at the counter: past the time the guest was shown, it's over, even if
  -- the minute-timer hasn't swept it yet.
  if o.payment_due_at <= now() then
    raise exception using errcode = 'P0001', message = 'order_expired';
  end if;

  insert into public.payments (order_id, method, provider, amount_minor_units, currency,
    status, staff_id)
  values (o.id, 'counter', 'counter', o.total_price_minor_units, 'ILS', 'paid', auth.uid());
  perform set_config('mawzoon.paying', 'on', true);
  update public.orders set status = 'PENDING', paid_at = now() where id = o.id;
  perform set_config('mawzoon.paying', 'off', true);
  return jsonb_build_object('status', 'PENDING', 'already_paid', false,
    'total_minor_units', o.total_price_minor_units);
end $$;

-- ── S5: the payment provider confirms a card charge ─────────────────────────
-- Called by the payment-webhook edge function (service role) after it has asked the
-- provider itself. Idempotent on (provider, txn). Money that can't settle an unpaid
-- order — wrong amount, order cancelled/expired, already paid — is recorded as
-- needs_refund and the order is left alone.
-- Card is lenient on the deadline (unlike the counter): money already moved, and
-- while the order is still AWAITING_PAYMENT its stock is still held.
create or replace function public.mark_paid_card(p_order_id uuid, p_provider text,
  p_txn_id text, p_amount_minor_units integer, p_currency text, p_raw jsonb default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  o public.orders;
  v_seen text;
  v_ok boolean;
  v_result text;
begin
  if nullif(btrim(p_txn_id), '') is null or nullif(btrim(p_provider), '') is null
     or p_amount_minor_units is null or p_currency is null then
    raise exception using errcode = 'P0001', message = 'invalid_payload';
  end if;
  select * into o from public.orders where id = p_order_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'not_found';
  end if;
  -- After the order lock, so two copies of one webhook can't both miss each other.
  select status into v_seen from public.payments
   where provider = p_provider and provider_txn_id = p_txn_id;
  if found then
    return jsonb_build_object('result', 'duplicate', 'payment_status', v_seen);
  end if;

  v_ok := p_amount_minor_units = o.total_price_minor_units and p_currency = 'ILS';
  v_result := case when not v_ok then 'amount_mismatch'
                   when o.status = 'AWAITING_PAYMENT' then 'paid'
                   when o.status = 'CANCELLED' then 'order_cancelled'
                   else 'already_paid' end;

  insert into public.payments (order_id, method, provider, provider_txn_id,
    amount_minor_units, currency, status, raw)
  values (o.id, 'card', p_provider, p_txn_id, p_amount_minor_units, p_currency,
    case when v_result = 'paid' then 'paid' else 'needs_refund' end, p_raw);

  if v_result = 'paid' then
    perform set_config('mawzoon.paying', 'on', true);
    update public.orders set status = 'PENDING', paid_at = now() where id = o.id;
    perform set_config('mawzoon.paying', 'off', true);
  end if;
  return jsonb_build_object('result', v_result);
end $$;

-- ── S2: place_order — starts unpaid, one open unpaid order per guest ─────────
-- Changes from Module 11: locks the guest's profile row first (serialises one guest's
-- placements, so "one open unpaid order" holds under a double tap); refuses
-- unpaid_order_open (detail = that order's id, hint = its number) and counter_blocked
-- (C4); answers status, payment_method and payment_due_at too.
-- Error keys: not_signed_in, menu_changed, invalid_payload, invalid_plate, needs_address,
-- needs_phone, sold_out, idempotency_conflict, unpaid_order_open, counter_blocked,
-- delivery_unavailable, card_unavailable, card_required.
create or replace function public.place_order(
  p_order jsonb, p_idempotency_key uuid, p_catalogue_fingerprint text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_existing public.orders;
  v_open public.orders;
  v_new public.orders;
  v_rules record;
  v_type public.order_type;
  v_payment public.payment_method;
  v_volume public.volume_type;
  v_protein text := p_order ->> 'protein_id';
  v_carb text := p_order ->> 'carb_id';
  v_fiber text := p_order ->> 'fiber_id';
  v_signature text := nullif(p_order ->> 'signature_plate_id', '');
  v_title text := nullif(btrim(p_order ->> 'title'), '');
  v_address text := nullif(btrim(p_order ->> 'delivery_address'), '');
  v_phone text := nullif(regexp_replace(coalesce(p_order ->> 'customer_phone', ''), '[\s-]', '', 'g'), '');
  v_kcal integer;
  v_protein_g numeric;
  v_carbs_g numeric;
  v_fats_g numeric;
  v_quote record;
  v_state record;
  v_component text;
begin
  if v_uid is null then
    raise exception using errcode = 'P0001', message = 'not_signed_in';
  end if;
  if p_idempotency_key is null then
    raise exception using errcode = 'P0001', message = 'invalid_payload', detail = 'idempotency key';
  end if;

  -- One guest places one order at a time. A concurrent retry with the same key
  -- waits here, then takes the replay branch below.
  perform 1 from public.profiles where id = v_uid for no key update;

  -- Replay of a key this guest already used: return the first answer, run nothing again.
  select * into v_existing from public.orders where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.customer_id <> v_uid then
      raise exception using errcode = 'P0001', message = 'idempotency_conflict';
    end if;
    return private.order_answer(v_existing, true);
  end if;

  if p_catalogue_fingerprint is distinct from (select catalogue_fingerprint from public.pricing) then
    raise exception using errcode = 'P0001', message = 'menu_changed';
  end if;

  begin
    v_type := (p_order ->> 'order_type')::public.order_type;
    v_payment := (p_order ->> 'payment_method')::public.payment_method;
    v_volume := (p_order ->> 'volume')::public.volume_type;
    v_kcal := (p_order #>> '{nutrition,calories}')::integer;
    v_protein_g := (p_order #>> '{nutrition,protein_g}')::numeric;
    v_carbs_g := (p_order #>> '{nutrition,carbs_g}')::numeric;
    v_fats_g := (p_order #>> '{nutrition,fats_g}')::numeric;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception using errcode = 'P0001', message = 'invalid_payload', detail = sqlerrm;
  end;
  -- Nutrition is display-only (the server doesn't re-run the Atwater engine), so it is
  -- trusted from the phone but held to plausible bounds.
  if v_type is null or v_payment is null or v_volume is null or v_title is null
     or v_kcal is null or v_protein_g is null or v_carbs_g is null or v_fats_g is null
     or v_kcal not between 0 and 5000 or v_protein_g not between 0 and 1000
     or v_carbs_g not between 0 and 1000 or v_fats_g not between 0 and 1000 then
    raise exception using errcode = 'P0001', message = 'invalid_payload',
      detail = 'missing field, or nutrition out of range';
  end if;

  if v_phone is not null and v_phone !~ '^\+?[0-9]{8,15}$' then
    raise exception using errcode = 'P0001', message = 'needs_phone';
  end if;
  if v_type = 'DELIVERY' then
    if v_address is null then
      raise exception using errcode = 'P0001', message = 'needs_address';
    end if;
    if v_phone is null then
      raise exception using errcode = 'P0001', message = 'needs_phone';
    end if;
  else
    v_address := null;
  end if;

  if v_signature is not null and not exists (
    select 1 from public.signature_plates s
     where s.id = v_signature
       and s.protein_id = v_protein and s.carb_id = v_carb and s.fiber_id = v_fiber
  ) then
    raise exception using errcode = 'P0001', message = 'invalid_plate',
      detail = 'chef plate does not match its components';
  end if;

  select * into v_quote from private.quote_plate(v_protein, v_carb, v_fiber, v_volume, v_type);

  -- D7: one open unpaid order. One past its deadline doesn't count (the timer sweeps it).
  select * into v_open from public.orders
   where customer_id = v_uid and status = 'AWAITING_PAYMENT' and payment_due_at > now()
   order by created_at desc limit 1;
  if found then
    raise exception using errcode = 'P0001', message = 'unpaid_order_open',
      detail = v_open.id::text, hint = v_open.order_number::text;
  end if;

  -- C4: walked away from too many counter orders lately → card only.
  select * into v_rules from private.payment_rules();
  if v_payment::text = 'counter' and (
       select count(*) from public.orders
        where customer_id = v_uid and payment_method::text = 'counter'
          and cancel_reason = 'expired' and created_at > now() - v_rules.strike_window
     ) >= v_rules.strike_limit then
    raise exception using errcode = 'P0001', message = 'counter_blocked';
  end if;

  -- The key can't be taken by now (the profile lock serialises this guest, and a key
  -- is per guest), but on conflict still guards a key reused across guests.
  insert into public.orders (idempotency_key, customer_id, customer_name, customer_phone,
    delivery_address, order_type, payment_method, note, total_price_minor_units,
    total_calories, total_protein_g, total_carbs_g, total_fats_g)
  values (p_idempotency_key, v_uid, nullif(btrim(p_order ->> 'customer_name'), ''), v_phone,
    v_address, v_type, v_payment, nullif(btrim(p_order ->> 'note'), ''),
    v_quote.total_minor_units, v_kcal, v_protein_g, v_carbs_g, v_fats_g)
  on conflict (idempotency_key) do nothing
  returning * into v_new;

  if v_new.id is null then
    raise exception using errcode = 'P0001', message = 'idempotency_conflict';
  end if;

  -- Lock every ingredient this plate draws on, always in id order, so two orders that
  -- share an ingredient queue up instead of deadlocking. The second one then sees the
  -- first one's draw before it checks — the "two guests, last portion" race.
  perform 1 from public.raw_ingredients
   where id in (select d.ingredient_id
                  from private.plate_draw(v_protein, v_carb, v_fiber, v_volume) d)
   order by id
     for update;

  -- Selling stops at the safety buffer, checked before the draw (OrderDraft.blockerIn
  -- names the first one, in build order).
  foreach v_component in array array[v_protein, v_carb, v_fiber] loop
    select * into v_state from private.component_state(v_component);
    if v_state.status = 'soldOut' then
      raise exception using errcode = 'P0001', message = 'sold_out',
        detail = v_component, hint = v_state.sold_out_reason;
    end if;
  end loop;

  -- Record what was taken, then take exactly that: an unpaid order holds its portions
  -- until it's paid or expires. The book may go below zero (InventoryLedger.deduct).
  insert into public.order_draws (order_id, ingredient_id, amount_minor_units)
  select v_new.id, d.ingredient_id, d.amount_minor_units
    from private.plate_draw(v_protein, v_carb, v_fiber, v_volume) d;
  update public.raw_ingredients ri
     set stock_minor_units = ri.stock_minor_units - d.amount_minor_units, updated_at = now()
    from public.order_draws d
   where d.order_id = v_new.id and ri.id = d.ingredient_id;

  insert into public.order_items (order_id, item_type, source_signature_plate_id, title,
    protein_id, protein_weight_g, carb_id, carb_weight_g, fiber_id, fiber_weight_g,
    volume_type, price_minor_units)
  values (v_new.id,
    case when v_signature is null then 'CUSTOM_PLATE' else 'CHEF_PLATE' end::public.item_type,
    v_signature, v_title,
    v_protein, private.portion_grams(v_protein, v_volume),
    v_carb, private.portion_grams(v_carb, v_volume),
    v_fiber, private.portion_grams(v_fiber, v_volume),
    v_volume, v_quote.plate_minor_units);

  return private.order_answer(v_new, false);
end $$;

-- place_order's answer, fresh or replayed (a replay reports the order as it is now).
create or replace function private.order_answer(o public.orders, p_replayed boolean)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('order_id', o.id, 'order_number', o.order_number,
    'total_minor_units', o.total_price_minor_units, 'replayed', p_replayed,
    'status', o.status, 'payment_method', o.payment_method,
    'payment_due_at', o.payment_due_at);
$$;

-- ── Privileges ───────────────────────────────────────────────────────────────
revoke all on all functions in schema private from public, anon, authenticated;
revoke all on function public.mark_paid_counter(uuid),
  public.mark_paid_card(uuid, text, text, integer, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.mark_paid_counter(uuid) to authenticated;
grant execute on function public.mark_paid_card(uuid, text, text, integer, text, jsonb)
  to service_role;

-- ── S4: the timer ────────────────────────────────────────────────────────────
create extension if not exists pg_cron;
select cron.schedule('mawzoon-expire-unpaid', '* * * * *',
  'select private.expire_unpaid_orders()');
