-- Module 12, part L: Israel. Prices include VAT; pay at the counter or by card;
-- delivery and card sit behind launch switches until they're offered.
-- Don't run with -1: Postgres can't use an enum value in the transaction that adds it.

alter type public.payment_method add value if not exists 'counter';
alter type public.payment_method add value if not exists 'card';

-- Twins of LaunchSwitches in the app; the seed writes them from there.
alter table public.pricing
  add column if not exists delivery_enabled boolean not null default false,
  add column if not exists card_payment_enabled boolean not null default false;

-- PriceBreakdown.forPlate: the total is the sum of the charges, VAT inside it.
-- The VAT is Money.includedTax's whole-number formula, so phone and server agree.
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
  v_total integer;
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
  v_total := v_plate + v_delivery;
  return query select v_plate, v_delivery,
    (2 * v_total * pr.vat_basis_points + (10000 + pr.vat_basis_points))
      / (2 * (10000 + pr.vat_basis_points)),
    v_total;
end $$;

-- Every new order, whatever inserts it: only counter/card, switches respected,
-- and delivery is paid by card (nobody hands cash to a driver for an unknown guest).
create or replace function private.check_new_order()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  pr public.pricing;
begin
  select * into strict pr from public.pricing;
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
  return new;
end $$;

revoke all on function private.check_new_order() from public;

drop trigger if exists orders_check_new on public.orders;
create trigger orders_check_new before insert on public.orders
  for each row execute function private.check_new_order();
