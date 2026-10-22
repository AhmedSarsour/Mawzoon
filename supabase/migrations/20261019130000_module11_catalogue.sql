-- Module 11 (D7): the menu numbers the server prices and draws stock from.
-- Rows come only from supabase/seed/module11_catalogue.sql, generated from the Dart
-- catalogue by tool/catalogue_seed.dart — never typed here, so the two can't drift.
-- Also: a delivery order must carry a phone (Ahmed, 2026-10-19).

do $$ begin
  create type public.plate_segment as enum ('protein', 'smartCarb', 'vitalFiber');
exception when duplicate_object then null; end $$;

create table if not exists public.menu_components (
  component_id text primary key,
  segment public.plate_segment not null,
  surcharge_minor_units integer not null default 0 check (surcharge_minor_units >= 0),
  base_portion_grams numeric(7, 1) not null check (base_portion_grams > 0)
);

create table if not exists public.signature_plates (
  id text primary key,
  protein_id text not null references public.menu_components (component_id),
  carb_id text not null references public.menu_components (component_id),
  fiber_id text not null references public.menu_components (component_id)
);

-- PortionScale.factorFor(segment), per volume.
create table if not exists public.portion_scale_factors (
  volume public.volume_type not null,
  segment public.plate_segment not null,
  factor numeric(5, 3) not null check (factor > 0),
  primary key (volume, segment)
);

-- PriceBreakdown's constants. Exactly one row, written by the seed.
create table if not exists public.pricing (
  id boolean primary key default true check (id),
  base_plate_minor_units integer not null check (base_plate_minor_units >= 0),
  athletic_uplift_minor_units integer not null check (athletic_uplift_minor_units >= 0),
  delivery_fee_minor_units integer not null check (delivery_fee_minor_units >= 0),
  vat_basis_points integer not null check (vat_basis_points between 0 and 10000),
  -- Hash of everything above + recipes. The app sends its own; a mismatch means the
  -- app shows prices the server won't charge, so place_order refuses.
  catalogue_fingerprint text not null
);

-- What each placed order actually took, so a cancel puts back exactly that —
-- not a recomputation that a recalibration in between would make wrong.
create table if not exists public.order_draws (
  order_id uuid not null references public.orders (id) on delete cascade,
  ingredient_id text not null references public.raw_ingredients (id),
  amount_minor_units bigint not null,
  primary key (order_id, ingredient_id)
);
create index if not exists order_draws_ingredient_idx on public.order_draws (ingredient_id);

do $$ begin
  alter table public.recipe_lines add constraint recipe_lines_component_fk
    foreign key (component_id) references public.menu_components (component_id) on delete cascade;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.component_settings add constraint component_settings_component_fk
    foreign key (component_id) references public.menu_components (component_id) on delete cascade;
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.orders add constraint delivery_needs_phone
    check (order_type = 'PICKUP' or nullif(btrim(customer_phone), '') is not null);
exception when duplicate_object then null; end $$;

-- Staff may read, nobody writes through the API: prices change only by re-seeding from
-- Dart, and draws only through place_order / cancel_order.
revoke all on public.menu_components, public.signature_plates, public.portion_scale_factors,
  public.pricing, public.order_draws from anon;
revoke insert, update, delete on public.menu_components, public.signature_plates,
  public.portion_scale_factors, public.pricing, public.order_draws from authenticated;
alter table public.menu_components enable row level security;
alter table public.signature_plates enable row level security;
alter table public.portion_scale_factors enable row level security;
alter table public.pricing enable row level security;
alter table public.order_draws enable row level security;
do $$
declare t text;
begin
  foreach t in array array['menu_components', 'signature_plates', 'portion_scale_factors',
                           'pricing', 'order_draws']
  loop
    execute format('drop policy if exists "staff: read" on public.%I', t);
    execute format(
      'create policy "staff: read" on public.%I for select to authenticated '
      'using ((select public.is_staff()))', t);
  end loop;
end $$;
