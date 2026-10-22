-- Module 11 (D1–D3): stock, profiles, orders, and who may touch them.
-- Mirrors the Dart domain (InventoryLedger, RecipeLine, OrderDraft) so its rules port as-is.
-- Re-runnable: every object is created only if missing, every policy is replaced.
-- Guests can only READ their own orders; creating one goes through a server function (D6),
-- so the phone never gets to state its own price.

-- ── Enums ────────────────────────────────────────────────────────────────────
do $$ begin
  create type public.measure_unit as enum ('gram', 'millilitre', 'piece');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.storage_area as enum ('chiller', 'dryStore', 'produce');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.order_type as enum ('DELIVERY', 'PICKUP');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.order_status as enum
    ('PENDING', 'ACCEPTED', 'ASSEMBLING', 'READY', 'COMPLETED', 'CANCELLED');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.item_type as enum ('CUSTOM_PLATE', 'CHEF_PLATE');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.volume_type as enum ('STANDARD', 'ATHLETIC');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.payment_method as enum ('wallet', 'savedCard', 'cash');
exception when duplicate_object then null; end $$;

-- ── D2: profiles ─────────────────────────────────────────────────────────────
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  phone text check (char_length(phone) <= 32),
  full_name text check (char_length(full_name) <= 120),
  is_staff boolean not null default false,
  created_at timestamptz not null default now()
);

-- Security definer so policies on profiles can ask "is this user staff?"
-- without re-entering profiles' own RLS (infinite recursion otherwise).
create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select p.is_staff from public.profiles p where p.id = auth.uid()), false);
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── D1: stock ────────────────────────────────────────────────────────────────
-- The book, not the shelf: stock may go below zero, which records a shortfall
-- (InventoryLedger.deduct applies the draw anyway — the food was cooked).
create table if not exists public.raw_ingredients (
  id text primary key,
  name_ar text not null,
  name_en text not null,
  unit public.measure_unit not null,
  storage_area public.storage_area not null,
  shelf_life_days integer check (shelf_life_days > 0),
  -- Thousandths of `unit` (mg, µl, milli-pieces), as Quantity.minorUnits.
  stock_minor_units bigint not null default 0,
  updated_at timestamptz not null default now()
);

-- One standard portion, raw. Scale and calibration are applied at draw time,
-- exactly as RecipeLine.atScale does.
create table if not exists public.recipe_lines (
  component_id text not null,
  ingredient_id text not null references public.raw_ingredients (id),
  amount_minor_units bigint not null check (amount_minor_units > 0),
  primary key (component_id, ingredient_id)
);
create index if not exists recipe_lines_ingredient_idx
  on public.recipe_lines (ingredient_id);

-- Per-component manager settings: calibration (RecipeBook) and the manual
-- "take it off the menu" switch (InventoryLedger.setForcedOff).
create table if not exists public.component_settings (
  component_id text primary key,
  portion_factor numeric(6, 3) not null default 1 check (portion_factor > 0),
  forced_off boolean not null default false,
  updated_at timestamptz not null default now()
);

-- The site's rails (StockRails), in portions. Exactly one row.
create table if not exists public.stock_rails (
  id boolean primary key default true check (id),
  safety_buffer_portions integer not null default 5 check (safety_buffer_portions >= 0),
  low_water_mark_portions integer not null default 12,
  check (low_water_mark_portions >= safety_buffer_portions)
);
insert into public.stock_rails (id) values (true) on conflict (id) do nothing;

-- ── D3: orders ───────────────────────────────────────────────────────────────
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  -- Client-made per placement; a retried placement hits this and is not a 2nd order.
  idempotency_key uuid not null unique,
  order_number bigint generated always as identity (start with 101) unique,
  customer_id uuid not null references public.profiles (id),
  customer_name text check (char_length(customer_name) <= 120),
  customer_phone text check (char_length(customer_phone) <= 32),
  delivery_address text check (char_length(delivery_address) <= 500),
  order_type public.order_type not null,
  payment_method public.payment_method not null,
  status public.order_status not null default 'PENDING',
  note text check (char_length(note) <= 280),
  total_price_minor_units integer not null check (total_price_minor_units >= 0),
  total_calories integer not null check (total_calories >= 0),
  total_protein_g numeric(7, 1) not null check (total_protein_g >= 0),
  total_carbs_g numeric(7, 1) not null check (total_carbs_g >= 0),
  total_fats_g numeric(7, 1) not null check (total_fats_g >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint delivery_needs_address
    check (order_type = 'PICKUP' or nullif(btrim(delivery_address), '') is not null)
);
-- The kitchen board: active orders, oldest first.
create index if not exists orders_kitchen_active_idx on public.orders (created_at)
  where status in ('PENDING', 'ACCEPTED', 'ASSEMBLING', 'READY');
-- A guest's order history, newest first.
create index if not exists orders_customer_idx
  on public.orders (customer_id, created_at desc);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  item_type public.item_type not null,
  source_signature_plate_id text,
  title text not null check (char_length(title) <= 120),
  protein_id text not null,
  protein_weight_g numeric(7, 1) not null,
  carb_id text not null,
  carb_weight_g numeric(7, 1) not null,
  fiber_id text not null,
  fiber_weight_g numeric(7, 1) not null,
  volume_type public.volume_type not null,
  price_minor_units integer not null check (price_minor_units >= 0),
  -- {"grill": true, "starch": false, "prep": true}; only the three stations.
  station_status jsonb not null default '{}'::jsonb,
  constraint chef_plate_has_source
    check ((item_type = 'CHEF_PLATE') = (source_signature_plate_id is not null)),
  constraint known_stations_only
    check (jsonb_typeof(station_status) = 'object'
           and station_status - array['grill', 'starch', 'prep'] = '{}'::jsonb)
);
create index if not exists order_items_order_idx on public.order_items (order_id);

-- Status only moves forward; cancelling is allowed until the guest has it.
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
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists orders_status_guard on public.orders;
create trigger orders_status_guard
  before update of status on public.orders
  for each row execute function public.guard_order_status();

-- A cook marks one station done/undone. Merges one key under the row lock, so two
-- cooks tapping different stations at once can't overwrite each other, and a
-- replayed tap after a reconnect sets the same value again instead of flipping it.
create or replace function public.set_station_status(
  p_item_id uuid, p_station text, p_done boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
  if not public.is_staff() then
    raise exception 'staff only' using errcode = 'insufficient_privilege';
  end if;
  update public.order_items
     set station_status = station_status || jsonb_build_object(p_station, p_done)
   where id = p_item_id
  returning station_status into result;
  if result is null then
    raise exception 'no such item' using errcode = 'no_data_found';
  end if;
  return result;
end $$;

-- ── Privileges ───────────────────────────────────────────────────────────────
-- `anon` = no session at all (anonymous-auth guests are `authenticated`): nothing.
revoke all on public.profiles, public.raw_ingredients, public.recipe_lines,
  public.component_settings, public.stock_rails, public.orders, public.order_items
  from anon;
revoke execute on function public.set_station_status(uuid, text, boolean),
  public.is_staff(), public.handle_new_user(), public.guard_order_status()
  from public, anon;
grant execute on function public.set_station_status(uuid, text, boolean),
  public.is_staff() to authenticated;

-- Column-level: a signed-in user may only ever write these columns. RLS below
-- then decides *which rows*.
revoke insert, update, delete on public.profiles, public.orders, public.order_items
  from authenticated;
grant update (phone, full_name) on public.profiles to authenticated;
grant update (status) on public.orders to authenticated;

-- ── Row-level security ──────────────────────────────────────────────────────
alter table public.profiles enable row level security;
alter table public.raw_ingredients enable row level security;
alter table public.recipe_lines enable row level security;
alter table public.component_settings enable row level security;
alter table public.stock_rails enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

drop policy if exists "own profile: read" on public.profiles;
create policy "own profile: read" on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select public.is_staff()));
drop policy if exists "own profile: edit" on public.profiles;
create policy "own profile: edit" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- Stock, recipes and rails are back-office data: staff only. Guests will see
-- per-component availability (no counts) through a function in F3.
do $$
declare t text;
begin
  foreach t in array array['raw_ingredients', 'recipe_lines', 'component_settings', 'stock_rails']
  loop
    execute format('drop policy if exists "staff: all" on public.%I', t);
    execute format(
      'create policy "staff: all" on public.%I for all to authenticated '
      'using ((select public.is_staff())) with check ((select public.is_staff()))', t);
  end loop;
end $$;

drop policy if exists "orders: own or staff read" on public.orders;
create policy "orders: own or staff read" on public.orders for select to authenticated
  using (customer_id = (select auth.uid()) or (select public.is_staff()));
drop policy if exists "orders: staff moves status" on public.orders;
create policy "orders: staff moves status" on public.orders for update to authenticated
  using ((select public.is_staff())) with check ((select public.is_staff()));

drop policy if exists "order_items: follow parent" on public.order_items;
create policy "order_items: follow parent" on public.order_items for select to authenticated
  using (exists (
    select 1 from public.orders o
     where o.id = order_id
       and (o.customer_id = (select auth.uid()) or (select public.is_staff()))));

-- ── Realtime ─────────────────────────────────────────────────────────────────
-- Change events are filtered by each subscriber's RLS, same as a select.
do $$
declare t text;
begin
  foreach t in array array['orders', 'order_items', 'raw_ingredients', 'component_settings']
  loop
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
