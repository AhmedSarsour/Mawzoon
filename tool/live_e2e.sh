#!/usr/bin/env bash
# Live end-to-end: the app's real Supabase code (tool/live_e2e.dart) against the live
# project, in Chrome. Creates a throwaway staff account + stock for one plate, and
# restores stock, settings and accounts on exit, pass or fail.
# Run: bash tool/live_e2e.sh      (needs ~/.config/mawzoon/db_url)
set -euo pipefail
DB="$(cat ~/.config/mawzoon/db_url)"
q() { psql "$DB" -X -q -A -t -v ON_ERROR_STOP=1 "$@"; }

STAFF_ID="$(uuidgen | tr 'A-Z' 'a-z')"
EMAIL="e2e-$(date +%s)@mawzoon.test"
PASSWORD="$(openssl rand -hex 16)"
STARTED="$(q -c "select now()")"
LOG="$(mktemp)"
PLATE_INGREDIENTS="'raw.chicken_breast','raw.house_spice_blend','raw.olive_oil','raw.basmati_rice','raw.garden_vegetables'"

cleanup() {
  pkill -f "live_e2e.dart" >/dev/null 2>&1 || true
  q >/dev/null <<SQL
delete from public.payments where order_id in (select id from public.orders where customer_id in (
  select id from auth.users
   where id = '$STAFF_ID' or (is_anonymous and created_at >= '$STARTED')));
delete from public.orders where customer_id in (
  select id from auth.users
   where id = '$STAFF_ID' or (is_anonymous and created_at >= '$STARTED'));
delete from auth.users where id = '$STAFF_ID' or (is_anonymous and created_at >= '$STARTED');
update public.raw_ingredients r set stock_minor_units = b.stock_minor_units
  from private.e2e_stock_backup b where r.id = b.id;
delete from public.component_settings
 where component_id not in (select component_id from private.e2e_settings_backup);
update public.component_settings c set forced_off = b.forced_off, portion_factor = b.portion_factor
  from private.e2e_settings_backup b where c.component_id = b.component_id;
drop table if exists private.e2e_stock_backup, private.e2e_settings_backup;
SQL
  rm -f "$LOG"
}
trap cleanup EXIT

q >/dev/null <<SQL
create table private.e2e_stock_backup as select id, stock_minor_units from public.raw_ingredients;
create table private.e2e_settings_backup as select * from public.component_settings;
update public.raw_ingredients set stock_minor_units = 100000000 where id in ($PLATE_INGREDIENTS);
-- Salmon out for the run, so the sold-out path is exercised whatever the live stock is.
update public.raw_ingredients set stock_minor_units = 0 where id = 'raw.salmon_fillet';
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  email_change_token_current, phone_change, phone_change_token, reauthentication_token)
values ('00000000-0000-0000-0000-000000000000', '$STAFF_ID', 'authenticated', 'authenticated',
  '$EMAIL', extensions.crypt('$PASSWORD', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now(), false,
  '', '', '', '', '', '', '', '');
insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at,
  created_at, updated_at)
values (gen_random_uuid(), '$STAFF_ID', '$STAFF_ID',
  jsonb_build_object('sub', '$STAFF_ID', 'email', '$EMAIL', 'email_verified', true),
  'email', now(), now(), now());
update public.profiles set is_staff = true where id = '$STAFF_ID';
SQL

flutter run -d chrome -t tool/live_e2e.dart \
  --dart-define=E2E_STAFF_EMAIL="$EMAIL" --dart-define=E2E_STAFF_PASSWORD="$PASSWORD" \
  >"$LOG" 2>&1 &
for _ in $(seq 1 120); do
  sleep 2
  grep -qE "E2E (PASS|FAIL)|Error:|Failed to compile" "$LOG" && break
done
sleep 1
grep -E "^\s*ok |E2E (PASS|FAIL)|Error|Exception|StateError" "$LOG" | grep -v "^\s*$" | head -40
grep -q "E2E PASS" "$LOG"
