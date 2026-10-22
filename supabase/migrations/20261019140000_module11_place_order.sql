-- Module 11 (D5+D6): placing and cancelling an order, entirely on the server.
-- place_order prices the plate itself, checks stock under row locks, takes the stock and
-- writes the order in one transaction (all or nothing). The phone sends choices, not prices.
-- Helpers live in `private`, which the API can't reach.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- RecipeLine.atScale for every line of one component: amount × (scale × calibration),
-- rounded half away from zero like Quantity.operator*.
create or replace function private.component_draw(p_component text, p_volume public.volume_type)
returns table (ingredient_id text, amount_minor_units bigint)
language sql stable set search_path = '' as $$
  select rl.ingredient_id,
         round(rl.amount_minor_units * (f.factor * coalesce(cs.portion_factor, 1)))::bigint
    from public.recipe_lines rl
    join public.menu_components mc on mc.component_id = rl.component_id
    join public.portion_scale_factors f on f.volume = p_volume and f.segment = mc.segment
    left join public.component_settings cs on cs.component_id = rl.component_id
   where rl.component_id = p_component;
$$;

-- InventoryLedger.deduct's draw: each component's lines, summed per ingredient.
create or replace function private.plate_draw(
  p_protein text, p_carb text, p_fiber text, p_volume public.volume_type)
returns table (ingredient_id text, amount_minor_units bigint)
language sql stable set search_path = '' as $$
  select d.ingredient_id, sum(d.amount_minor_units)::bigint
    from unnest(array[p_protein, p_carb, p_fiber]) as c (id)
    cross join lateral private.component_draw(c.id, p_volume) d
   group by d.ingredient_id;
$$;

-- InventoryLedger.portionsFor: standard portions left, set by the scarcest line.
-- Integer division truncates toward zero, like Dart's ~/. No recipe → 9999.
create or replace function private.component_portions(p_component text)
returns integer language sql stable set search_path = '' as $$
  select least(9999, coalesce(min(
           ri.stock_minor_units
           / round(rl.amount_minor_units * coalesce(cs.portion_factor, 1))::bigint), 9999))::integer
    from public.recipe_lines rl
    join public.raw_ingredients ri on ri.id = rl.ingredient_id
    left join public.component_settings cs on cs.component_id = rl.component_id
   where rl.component_id = p_component;
$$;

-- StockStatus.from: taken off by hand, or below the safety buffer = sold out.
create or replace function private.component_state(p_component text)
returns table (status text, sold_out_reason text)
language sql stable set search_path = '' as $$
  select case when coalesce(cs.forced_off, false) or p.n < r.safety_buffer_portions then 'soldOut'
              when p.n <= r.low_water_mark_portions then 'runningLow'
              else 'inStock' end,
         case when coalesce(cs.forced_off, false) then 'takenOff'
              when p.n < r.safety_buffer_portions then 'belowSafetyBuffer' end
    from public.stock_rails r
   cross join (select private.component_portions(p_component) as n) p
    left join public.component_settings cs on cs.component_id = p_component;
$$;

-- IngredientOption.atScale(...).portionGrams: what the kitchen plates.
create or replace function private.portion_grams(p_component text, p_volume public.volume_type)
returns numeric language sql stable set search_path = '' as $$
  select round(mc.base_portion_grams * f.factor, 1)
    from public.menu_components mc
    join public.portion_scale_factors f on f.volume = p_volume and f.segment = mc.segment
   where mc.component_id = p_component;
$$;

-- PriceBreakdown.forPlate. VAT rounds half away from zero, like Money.percentage.
create or replace function private.quote_plate(p_protein text, p_carb text, p_fiber text,
  p_volume public.volume_type, p_order_type public.order_type)
returns table (plate_minor_units integer, delivery_minor_units integer,
               tax_minor_units integer, total_minor_units integer)
language plpgsql stable set search_path = '' as $$
declare
  pr public.pricing;
  v_surcharges integer;
  v_found integer;
  v_plate integer;
  v_delivery integer;
  v_tax integer;
begin
  select * into strict pr from public.pricing;
  select coalesce(sum(surcharge_minor_units), 0), count(*) into v_surcharges, v_found
    from public.menu_components
   where (component_id, segment) in ((p_protein, 'protein'::public.plate_segment),
                                     (p_carb, 'smartCarb'), (p_fiber, 'vitalFiber'));
  if v_found <> 3 then
    raise exception using errcode = 'P0001', message = 'invalid_plate',
      detail = 'unknown component, or a component in the wrong compartment';
  end if;
  v_plate := pr.base_plate_minor_units + v_surcharges
           + case when p_volume = 'ATHLETIC' then pr.athletic_uplift_minor_units else 0 end;
  v_delivery := case when p_order_type = 'DELIVERY' then pr.delivery_fee_minor_units else 0 end;
  v_tax := round((v_plate + v_delivery) * pr.vat_basis_points / 10000.0);
  return query select v_plate, v_delivery, v_tax, v_plate + v_delivery + v_tax;
end $$;

-- Errors carry a stable key in `message` (and the component in `detail` for sold_out):
-- not_signed_in, menu_changed, invalid_payload, invalid_plate, needs_address,
-- needs_phone, sold_out, idempotency_conflict.
create or replace function public.place_order(
  p_order jsonb, p_idempotency_key uuid, p_catalogue_fingerprint text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_existing public.orders;
  v_order_id uuid;
  v_number bigint;
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

  -- Replay of a key this guest already used: return the first answer, run nothing again.
  select * into v_existing from public.orders where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.customer_id <> v_uid then
      raise exception using errcode = 'P0001', message = 'idempotency_conflict';
    end if;
    return jsonb_build_object('order_id', v_existing.id, 'order_number', v_existing.order_number,
      'total_minor_units', v_existing.total_price_minor_units, 'replayed', true);
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

  -- Claim the key first. A concurrent call with the same key waits here and, once
  -- this one commits, falls into the replay branch instead of placing a second order.
  insert into public.orders (idempotency_key, customer_id, customer_name, customer_phone,
    delivery_address, order_type, payment_method, note, total_price_minor_units,
    total_calories, total_protein_g, total_carbs_g, total_fats_g)
  values (p_idempotency_key, v_uid, nullif(btrim(p_order ->> 'customer_name'), ''), v_phone,
    v_address, v_type, v_payment, nullif(btrim(p_order ->> 'note'), ''),
    v_quote.total_minor_units, v_kcal, v_protein_g, v_carbs_g, v_fats_g)
  on conflict (idempotency_key) do nothing
  returning id, order_number into v_order_id, v_number;

  if v_order_id is null then
    select * into v_existing from public.orders where idempotency_key = p_idempotency_key;
    if v_existing.customer_id <> v_uid then
      raise exception using errcode = 'P0001', message = 'idempotency_conflict';
    end if;
    return jsonb_build_object('order_id', v_existing.id, 'order_number', v_existing.order_number,
      'total_minor_units', v_existing.total_price_minor_units, 'replayed', true);
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

  -- Record what was taken, then take exactly that. The book may go below zero; that is
  -- a shortfall for the next stock take, as in InventoryLedger.deduct.
  insert into public.order_draws (order_id, ingredient_id, amount_minor_units)
  select v_order_id, d.ingredient_id, d.amount_minor_units
    from private.plate_draw(v_protein, v_carb, v_fiber, v_volume) d;
  update public.raw_ingredients ri
     set stock_minor_units = ri.stock_minor_units - d.amount_minor_units, updated_at = now()
    from public.order_draws d
   where d.order_id = v_order_id and ri.id = d.ingredient_id;

  insert into public.order_items (order_id, item_type, source_signature_plate_id, title,
    protein_id, protein_weight_g, carb_id, carb_weight_g, fiber_id, fiber_weight_g,
    volume_type, price_minor_units)
  values (v_order_id,
    case when v_signature is null then 'CUSTOM_PLATE' else 'CHEF_PLATE' end::public.item_type,
    v_signature, v_title,
    v_protein, private.portion_grams(v_protein, v_volume),
    v_carb, private.portion_grams(v_carb, v_volume),
    v_fiber, private.portion_grams(v_fiber, v_volume),
    v_volume, v_quote.plate_minor_units);

  return jsonb_build_object('order_id', v_order_id, 'order_number', v_number,
    'total_minor_units', v_quote.total_minor_units, 'replayed', false);
end $$;

-- Guest: own order, only while PENDING. Staff: any order not yet completed.
-- Stock goes back once, and only if nothing was cooked yet (InventoryLedger.restore).
create or replace function public.cancel_order(p_order_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_staff boolean := public.is_staff();
  v_status public.order_status;
  v_customer uuid;
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
  if not v_staff and v_status <> 'PENDING' then
    raise exception using errcode = 'P0001', message = 'too_late_to_cancel';
  end if;

  perform set_config('mawzoon.cancelling', 'on', true);
  update public.orders set status = 'CANCELLED' where id = p_order_id;
  perform set_config('mawzoon.cancelling', 'off', true);

  if v_status in ('PENDING', 'ACCEPTED') then
    perform 1 from public.raw_ingredients
     where id in (select ingredient_id from public.order_draws where order_id = p_order_id)
     order by id
       for update;
    update public.raw_ingredients ri
       set stock_minor_units = ri.stock_minor_units + d.amount_minor_units, updated_at = now()
      from public.order_draws d
     where d.order_id = p_order_id and ri.id = d.ingredient_id;
    return jsonb_build_object('status', 'CANCELLED', 'restored', true);
  end if;
  return jsonb_build_object('status', 'CANCELLED', 'restored', false);
end $$;

-- What a guest may know about stock: a status per component, never a count.
create or replace function public.menu_availability()
returns table (component_id text, status text, sold_out_reason text)
language sql stable security definer set search_path = '' as $$
  select mc.component_id, s.status, s.sold_out_reason
    from public.menu_components mc
   cross join lateral private.component_state(mc.component_id) s;
$$;

-- Cancelling must go through cancel_order, or the stock it took is never put back.
create or replace function public.guard_order_status()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status = old.status then return new; end if;
  if not (
       (old.status = 'PENDING'    and new.status in ('ACCEPTED', 'CANCELLED'))
    or (old.status = 'ACCEPTED'   and new.status in ('ASSEMBLING', 'CANCELLED'))
    or (old.status = 'ASSEMBLING' and new.status in ('READY', 'CANCELLED'))
    or (old.status = 'READY'      and new.status in ('COMPLETED', 'CANCELLED'))
  ) then
    raise exception 'order % cannot go from % to %', old.order_number, old.status, new.status
      using errcode = 'check_violation';
  end if;
  if new.status = 'CANCELLED'
     and coalesce(current_setting('mawzoon.cancelling', true), '') <> 'on' then
    raise exception 'cancel order % with cancel_order(), so its stock is put back',
      old.order_number using errcode = 'check_violation';
  end if;
  new.updated_at := now();
  return new;
end $$;

revoke all on all functions in schema private from public, anon, authenticated;
revoke all on function public.place_order(jsonb, uuid, text), public.cancel_order(uuid),
  public.menu_availability() from public, anon;
grant execute on function public.place_order(jsonb, uuid, text), public.cancel_order(uuid),
  public.menu_availability() to authenticated;
