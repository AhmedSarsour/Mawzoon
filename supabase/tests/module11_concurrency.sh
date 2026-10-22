#!/usr/bin/env bash
# Real two-connection races against place_order (a single session can't fake this).
#   1. Two guests, one sellable portion left: exactly one order, stock drawn once.
#   2. One guest, same idempotency key twice at once: one order, drawn once.
# Uses committed zz_race.* rows and deletes them on exit. Run: bash supabase/tests/module11_concurrency.sh
set -euo pipefail
DB="$(cat ~/.config/mawzoon/db_url)"
q() { psql "$DB" -X -q -A -t -v ON_ERROR_STOP=1 "$@"; }
TMP="$(mktemp -d)"
U1=cccccccc-0000-0000-0000-0000000000c1
U2=cccccccc-0000-0000-0000-0000000000c2

db_cleanup() {
  q >/dev/null <<SQL
delete from public.orders where customer_id in ('$U1', '$U2');
delete from auth.users where id in ('$U1', '$U2');
delete from public.menu_components where component_id like 'zz_race.%';
delete from public.raw_ingredients where id like 'zz_race.%';
SQL
}
trap 'db_cleanup; rm -rf "$TMP"' EXIT
db_cleanup

fixtures() { # $1 = meat stock in mg
  q >/dev/null <<SQL
delete from public.orders where customer_id in ('$U1', '$U2');
insert into auth.users (id, aud, role, is_anonymous) values
  ('$U1', 'authenticated', 'authenticated', true), ('$U2', 'authenticated', 'authenticated', true)
on conflict (id) do nothing;
insert into public.menu_components values ('zz_race.protein', 'protein', 0, 100),
  ('zz_race.carb', 'smartCarb', 0, 100), ('zz_race.fiber', 'vitalFiber', 0, 100)
on conflict do nothing;
insert into public.raw_ingredients (id, name_ar, name_en, unit, storage_area, stock_minor_units)
values ('zz_race.meat', 'لحم', 'Meat', 'gram', 'chiller', $1),
       ('zz_race.side', 'جانب', 'Side', 'gram', 'dryStore', 100000000)
on conflict (id) do update set stock_minor_units = excluded.stock_minor_units;
insert into public.recipe_lines values ('zz_race.protein', 'zz_race.meat', 100000),
  ('zz_race.carb', 'zz_race.side', 1000), ('zz_race.fiber', 'zz_race.side', 1000)
on conflict do nothing;
SQL
}

FP="$(q -c "select catalogue_fingerprint from public.pricing")"
PLATE='{"order_type":"PICKUP","payment_method":"cash","volume":"STANDARD","title":"race",
"protein_id":"zz_race.protein","carb_id":"zz_race.carb","fiber_id":"zz_race.fiber",
"nutrition":{"calories":500,"protein_g":40,"carbs_g":40,"fats_g":10}}'

# Places an order as $1 with key $2, then holds the transaction open $3 seconds.
order() {
  q <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"$1","role":"authenticated"}', true) \g /dev/null
select public.place_order('$PLATE'::jsonb, '$2', '$FP');
select pg_sleep($3) \g /dev/null
commit;
SQL
}

fail() { echo "FAIL: $*"; exit 1; }

# ── 1. Last portion: 5 standard portions = exactly the buffer, so one order may sell.
fixtures 500000
order "$U1" "$(uuidgen)" 3 >"$TMP/a" 2>&1 &
sleep 1
order "$U2" "$(uuidgen)" 0 >"$TMP/b" 2>&1 || true
wait
grep -q '"replayed": false' "$TMP/a" || fail "first guest should have ordered: $(cat "$TMP/a")"
grep -q 'sold_out' "$TMP/b" || fail "second guest should be sold out: $(cat "$TMP/b")"
[ "$(q -c "select count(*) from public.orders where customer_id in ('$U1','$U2')")" = 1 ] \
  || fail "oversold: more than one order went through"
[ "$(q -c "select stock_minor_units from public.raw_ingredients where id = 'zz_race.meat'")" = 400000 ] \
  || fail "stock drawn more than once"
echo "race 1 ok: one order, one sold_out, stock 500000 -> 400000"

# ── 2. Same key twice at once, same guest.
fixtures 2000000
KEY="$(uuidgen)"
order "$U1" "$KEY" 3 >"$TMP/c" 2>&1 &
sleep 1
order "$U1" "$KEY" 0 >"$TMP/d" 2>&1 || true
wait
grep -q '"replayed": false' "$TMP/c" || fail "first call should place: $(cat "$TMP/c")"
grep -q '"replayed": true' "$TMP/d" || fail "second call should replay: $(cat "$TMP/d")"
[ "$(q -c "select count(*) from public.orders where customer_id = '$U1'")" = 1 ] \
  || fail "same key placed two orders"
[ "$(q -c "select stock_minor_units from public.raw_ingredients where id = 'zz_race.meat'")" = 1900000 ] \
  || fail "same key drew stock twice"
echo "race 2 ok: same key -> one order, second call replayed, drawn once"
echo "ALL CONCURRENCY CHECKS PASSED"
