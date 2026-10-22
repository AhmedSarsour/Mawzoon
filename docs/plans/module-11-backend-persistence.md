# Module 11 — Backend & persistence (Supabase)

Status: **Module 11 shipped end to end: S1, W1, D1–D7, F1–F7, all live. Open items:
see "Not done" under F5–F7.**

Project: `esuifisyffmbopeorupp` (URL + anon key in `lib/services/supabase_service.dart`).
Anonymous sign-ins: **on** (verified via `/auth/v1/settings`).

**How SQL reaches the database:** the Supabase MCP connector is logged into a different
account and can't see this project. Instead, Ahmed saved the session-pooler URI to
`~/.config/mawzoon/db_url` (chmod 600, outside the repo). Never print it, never copy it
into the repo. Apply migrations with
`supabase db push --db-url "$(cat ~/.config/mawzoon/db_url)"` (records history in
`supabase_migrations.schema_migrations`); run checks with
`psql "$(cat ~/.config/mawzoon/db_url)" -X -q -v ON_ERROR_STOP=1 -f <file>`.
Ahmed deletes the file when Module 11 is done.

## The risky thing, first

The pasted spec says "guests can read their own orders via secure device tokens or
phone session" and models `profiles.id` as "uuid, references auth.users **or guest
uuid**". If that guest uuid is anything the client hands the server (a locally
generated id, a phone number typed into a header), it is spoofable: anyone can read
anyone else's order and delivery address by guessing or incrementing an id. RLS
cannot save you here — the policy would correctly check `customer_id = <claimed id>`,
but the claimed id is the attacker's to choose.

**Fix: Supabase anonymous auth, not a client-supplied guest id.** `supabase.auth
.signInAnonymously()` gives every install a real `auth.uid()` minted and verified
server-side, persisted on-device by the SDK. Every RLS policy keys off `auth.uid()`,
never off a payload field. Phone number becomes profile metadata, not the identity
boundary — a guest never authenticates with it in this MVP (no OTP flow exists or is
in scope), it is just what the kitchen reads to call about a delivery.

An RLS policy that "looks right" and still lets row A read row B is the most expensive
mistake to ship here. It doesn't show up in the UI; only a direct adversarial query
catches it. Hence `supabase/tests/module11_rls.sql` (see D1–D3).

## Context: what exists vs. what the pasted spec assumed

The pasted spec was written without reading the codebase. Two of its tables don't
match what's actually here, and matching them anyway would throw away correctness
the domain layer already has:

- **Inventory is not per-menu-item.** `InventoryLedger` (`lib/features/manager_suite
  /domain/inventory_ledger.dart`) tracks `RawIngredient` (chicken breast, potato,
  olive oil — `lib/features/manager_suite/domain/raw_ingredient.dart`), not
  `protein_entrecote` stock directly. A component like fries draws oil, and so does
  the grilled protein and the greens — three recipe lines against one ingredient.
  The spec's `inventory_items` keyed by component id can't represent a shared
  ingredient across compartments, which is exactly the case `InventoryLedger.deduct`
  was built to get right (binding-constraint reporting, `bindingConstraintFor`).
  **This plan keeps two tables (`raw_ingredients`, `recipe_lines`) instead of
  collapsing to one**, and derives per-component stock status the same way the
  in-memory code already does.
- **Money is integer minor units (halalas), not `numeric`.** `Money`
  (`lib/core/pricing/money.dart`) is explicit that floats are a rejected design
  ("`0.1 + 0.2` is not `0.3`"). `total_price` and every price/surcharge column here
  is `integer`, not `numeric`.
- **Quantities are also integer minor units**, scaled per `MeasureUnit` (milligrams
  for grams, microlitres for millilitres — `lib/core/measure/quantity.dart`).
  `stock_grams numeric` loses that; this plan stores `stock_minor_units integer` +
  the ingredient's fixed unit.
- **No state-management package** (no Riverpod/Bloc/get_it) — controllers are plain
  `ValueNotifier` subclasses constructed with everything they need
  (`PlateBuilderController`). "Dependency injection setup" in this codebase means
  passing a repository into a controller's constructor, not a DI container. F4 below
  follows that, not a new pattern.
- **`OrderDraft` has no concept of "chef plate vs. custom plate" today** — it just
  carries a `PlateSelection`. D3 adds `sourceSignaturePlateId` (nullable) so
  `item_type` can be derived (`CUSTOM_PLATE` when null, `CHEF_PLATE` otherwise)
  without a parallel field that can disagree with it.

## Decisions carried over from the pasted spec (kept as-is)

- `orders` / `order_items` split, `order_type` and `status` as enums, realtime on
  `orders` and `inventory` tables, RLS on every table. Column names below follow the
  spec except where noted.
- Kitchen/manager roles read and mutate all active orders — implemented as a
  `staff` boolean on `profiles` (set only by a `SECURITY DEFINER` function a human
  runs from the SQL editor, never client-writable) checked in policies.

## Edge cases this design has to survive

1. **Two guests tap "place order" on the last portion of grilled salmon at the same
   moment.** The loser must get a clean "sold out", not a ticket the kitchen can't
   fulfil, and not a double-decremented ledger. → D5+D6: lock the ingredient rows in
   id order, check portions against the buffer, then draw.
2. **The app is offline when the guest taps "place order"** (the spec asks for
   "offline resilience"). → Retries must not create two orders: idempotency key
   (client-made UUID, unique constraint, `ON CONFLICT DO NOTHING`). ✅ Decided against
   a durable queue that sends later (late food); see F1–F4.
3. **A guest reinstalls the app or clears storage mid-order.** Anonymous auth session
   is gone; the in-flight order becomes unreadable to them. Acceptable for MVP — flag
   it, don't silently pretend it's solved (no account system exists yet).
4. **An order is cancelled after the kitchen already deducted stock.** →
   `InventoryLedger.restore`'s logic (put back only if this order code was actually
   counted, only once) has to survive the port to SQL, or a double-cancel invents
   stock. Same idempotency key covers both directions.
5. **A component has no recipe mapped** (`DeductionUnmapped` case in the current
   code) — must not silently skip depletion and must not block the order; it should
   surface as a manager-visible warning, matching current behaviour.
6. **Kitchen board reconnects after a dropped connection** and replays a station-tap
   that already landed. `station_status` writes must be idempotent per station, not
   "toggle" — a replayed toggle would double-flip it back off. ✅ `set_station_status`.
7. **A guest's address is empty-string vs. null for pickup.** `delivery_address`
   nullable only; a check constraint should enforce it's non-null when
   `order_type = 'DELIVERY'`, so a bad client can't ship a delivery order the kitchen
   can't route. ✅ `delivery_needs_address` (also rejects blank strings).
8. **Realtime payload leaking cross-tenant data.** Supabase realtime respects RLS on
   `postgres_changes` — must verify subscriptions filter server-side, not just
   client-side filter after receiving every row.

## Changes (stable IDs)

### S1 — Delete dead test file — ✅ SHIPPED
`test/widget_test.dart` referenced a `MyApp` class that no longer exists (the
default `flutter create` counter-app stub, never adapted). Deleted. Suite is 797/797
green, analyzer 0 errors (2 pre-existing warnings unrelated to this module: an unused
`cupertino.dart` import in `app_theme.dart`).

### W1 — Client wiring — ✅ SHIPPED
- `supabase_flutter: 2.18.3` pinned exact. It raised the lockfile's Flutter floor
  3.38.4 → 3.41.0 (Ahmed's machine: 3.41.7).
- `lib/services/supabase_service.dart`: `SupabaseConfig` (url, anon key) +
  `SupabaseService.initialize()` (never throws; returns false and logs on failure, so the
  app still opens on local data) + `client` getter. Called from `main()` before `runApp`.
  Uses `publishableKey:` — `anonKey:` is deprecated in 2.18.3; both feed the same slot.
- `test/services/supabase_config_test.dart`: the key's JWT `role` is `anon` (a
  service-role key can't be pasted in) and its `ref` matches the URL's project. Both
  proven non-vacuous.
- `tool/patch_platforms.dart` now also adds Android `INTERNET` (release builds don't get
  it from the debug manifest) and the macOS `network.client` entitlement. Applied to the
  real files; tested in `test/tool/patch_platforms_test.dart`.
- Verified: `Supabase init completed` in a Chrome debug run. macOS run is blocked by an
  unrelated Xcode destination issue (only an x86_64 "My Mac" offered).
- Not done (rest of F1): the connectivity listener and anonymous sign-in.

### D1–D3 — Schema, privileges, RLS, realtime — ✅ SHIPPED (live)
Source of truth: `supabase/migrations/20261019120000_module11_schema.sql` (re-runnable;
applied twice with no error). Adversarial proof: `supabase/tests/module11_rls.sql`
(guest A, guest B, staff, no-session; always rolls back). It passes against the live
schema, and 6 planted holes each made it fail with a named `FAIL:` (leaky read policy,
guest order insert, writable `is_staff`, station function without staff check, status
guard dropped, RLS off on a table). Also checked through the real REST API: no session
→ 401; a real anonymous sign-in gets its profile from the trigger, sees `[]` orders,
and `PATCH is_staff` → 42501.

What the shipped SQL does differently from the draft that used to be here (read the
migration, not memory of the draft):
- **Tables:** `raw_ingredients`, `recipe_lines`, `component_settings`, `stock_rails`,
  `profiles`, `orders`, `order_items`.
- **Units are `gram | millilitre | piece`** (`MeasureUnit`); the draft said `count`.
- **`recipe_lines` has no `scale` column.** It stores one standard portion, raw, keyed
  `(component_id, ingredient_id)`. Scale is applied at draw time exactly as
  `RecipeLine.atScale` does: `amount × scale.factorFor(segment) × portionFactor`.
- **Calibration and "take off menu" are per component**, not per ingredient:
  `component_settings(portion_factor, forced_off)` mirrors `RecipeBook` and
  `InventoryLedger.setForcedOff`.
- **Safety buffer / low-water mark are in portions, per site**: single-row
  `stock_rails` (5 / 12), mirroring `StockRails`.
- **Stock may go below zero.** No `>= 0` check and no `greatest(…, 0)` clamp: the
  ledger applies a draw even when the book is short (the food was cooked) and reports
  the shortfall. Clamping would erase the discrepancy the manager needs to see. Selling
  stops at the safety buffer *before* the draw, in D6.
- **Guests have no INSERT on orders/items at all**, not even "own rows". The phone
  would be stating its own price. Orders are created only by D6.
- **Writes are limited per column, not just per row.** Table-level
  INSERT/UPDATE/DELETE are revoked from `authenticated`, then only
  `profiles(phone, full_name)` and `orders(status)` are granted back. RLS picks the
  rows: own profile; staff-only for order status. So no one, staff included, can
  rewrite a price through the API.
- **`is_staff()`** is SECURITY DEFINER (avoids RLS recursion on `profiles`). Promoting
  someone is a manual `update public.profiles set is_staff = true where id = '…'` as
  owner. Policies call it as `(select public.is_staff())` so it runs once per query.
- **Status only moves forward** (`guard_order_status` trigger): PENDING→ACCEPTED→
  ASSEMBLING→READY→COMPLETED, and CANCELLED from any non-final state, but only via
  `cancel_order` (D5+D6). No path back from CANCELLED.
- **Stations:** `set_station_status(item_id, station, done)`, staff only, merges one
  key under the row lock (edge case 6). `known_stations_only` check allows only
  grill/starch/prep.
- **Stock tables are staff-only** (counts are business data). Guests get availability
  through `menu_availability()` (D5+D6), never raw counts.
- `anon` (no session) has no table access and no function execute.
- Realtime publication: `orders`, `order_items`, `raw_ingredients`, `component_settings`.
- Added from `OrderDraft`, missing in the spec: `payment_method`, `note` (≤280).
  `customer_name`/`customer_phone` are **nullable**: checkout doesn't collect them yet.
  Phone: required for delivery (Ahmed decided; enforced in D7 + `place_order`).

### D4 — Anonymous auth — ✅ SHIPPED
`SupabaseService.ensureSession()`: no session → `signInAnonymously()`; never throws,
returns false when offline. Called lazily by every guest gateway call (place order,
availability), not only at launch, so a guest who opened the app offline signs in on
their first real action. The SDK persists the session; edge case 3 (reinstall loses
order access) still stands.

### D7 — Server catalogue generated from Dart — ✅ SHIPPED (live)
- Tables (migration `20261019130000_module11_catalogue.sql`): `menu_components`
  (segment, surcharge, base portion grams), `signature_plates`, `portion_scale_factors`,
  single-row `pricing` (base 4900, athletic 1500, delivery 1200, VAT 1500 bp +
  `catalogue_fingerprint`), `order_draws` (what each order took). Staff can **read**
  them; nobody writes them through the API. Also adds `delivery_needs_phone` on
  `orders` (Ahmed's decision: phone required for delivery, optional for pickup).
- `tool/catalogue_seed.dart` generates, from `MawzoonCatalog`, `SignaturePlateCatalog`,
  `PortionScale`, `PriceBreakdown`, `RawStore`, `MawzoonRecipes`:
  `supabase/seed/module11_catalogue.sql` (re-runnable sync; never touches
  `stock_minor_units`; keeps ingredients dropped from the menu because past draws
  reference them), `supabase/tests/module11_parity.sql`, and
  `lib/core/menu/catalogue_fingerprint.g.dart` (SHA-256 of the catalogue, 16 hex).
- `test/tool/catalogue_seed_test.dart` fails if any of the three is stale (proven:
  bumping one surcharge without regenerating fails all 3). After **any** menu, price
  or recipe change: `dart run tool/catalogue_seed.dart`, then apply the seed with psql
  (see the header). If the seed isn't applied, `place_order` refuses every order from
  the new build with `menu_changed`, so the miss is loud, not silent.
- Live: 17 components, 43 recipe lines, 23 ingredients, fingerprint `7b9236aabfaeb181`.
- **Stock is 0 for every ingredient on the live project**, so everything reads
  `soldOut` until the first stock take. Expected (the seed never invents stock); F4
  needs a manager stock-take path writing `raw_ingredients.stock_minor_units` (staff
  have RLS write access).
- Known duplication, not fixed: 4900 and 1500 live both in `PriceBreakdown` and in
  `SignaturePlate`/`SignaturePlateCatalog`. The checkout uses `PriceBreakdown`, so the
  server mirrors that. Extract to one constant when next touching pricing.
- Rounding note: Dart taxes with a double (`(minor * 0.15).round()`), the server with
  exact numeric. They agree for every current combination (parity test), because every
  price is a multiple of 100 halalas. A price that creates a .5 tie could split them;
  the parity test is what would catch it.

### D5 + D6 — `place_order` / `cancel_order` / `menu_availability` — ✅ SHIPPED (live)
Migration `20261019140000_module11_place_order.sql`. Helpers live in schema `private`
(no API access). Each mirrors one Dart function, named in its comment:
`component_draw` (RecipeLine.atScale), `plate_draw`, `component_portions`
(InventoryLedger.portionsFor), `component_state` (StockStatus.from), `portion_grams`,
`quote_plate` (PriceBreakdown.forPlate).

**`place_order(p_order jsonb, p_idempotency_key uuid, p_catalogue_fingerprint text)`**:
the app-side contract F2 must follow exactly:
```json
{ "order_type": "PICKUP" | "DELIVERY", "payment_method": "wallet" | "savedCard" | "cash",
  "volume": "STANDARD" | "ATHLETIC",
  "protein_id": "...", "carb_id": "...", "fiber_id": "...",
  "signature_plate_id": "signature.x" (only if the chef plate is unmodified, else omit),
  "title": "shown to the kitchen (required)",
  "delivery_address": "...", "customer_phone": "...", "customer_name": "...", "note": "...",
  "nutrition": { "calories": int, "protein_g": num, "carbs_g": num, "fats_g": num } }
```
Returns `{order_id, order_number, total_minor_units, replayed}`. Send
`catalogueFingerprint` from `catalogue_fingerprint.g.dart`. **Show the returned total
on the confirmation**: it is what the guest pays. Errors come back as PostgREST errors
whose `message` is a stable key:
`not_signed_in`, `menu_changed` (app build older than the server menu → "update the
app"), `invalid_payload`, `invalid_plate`, `needs_address`, `needs_phone` (missing or
not 8–15 digits after stripping spaces/dashes; optional `+`), `sold_out` (`details` =
component id, `hint` = `takenOff` | `belowSafetyBuffer`; the first one in build order,
like `OrderDraft.blockerIn`), `idempotency_conflict`.
Order of work inside: replay check → fingerprint → parse/validate → server price →
claim the key (`insert … on conflict do nothing`) → lock the plate's ingredient rows
**in id order** → sold-out check under the lock → record `order_draws` → subtract →
insert the item (kitchen weights computed server-side).

**`cancel_order(p_order_id)`**: guest: own order, PENDING only (`too_late_to_cancel`
otherwise). Staff: any non-final order. Returns `{status, restored}`. Puts stock back
from `order_draws` exactly once, and only from PENDING/ACCEPTED (from ASSEMBLING
onwards the food is being made). Not-yours and not-there both answer `not_found`. The
status trigger refuses CANCELLED unless it comes through this function, so a staff
`update … set status = 'CANCELLED'` can't skip the restore.

**`menu_availability()`**: `(component_id, status, sold_out_reason)` for every
component, with no counts. Any signed-in user may call it.

Proofs, all run against the live database:
- `supabase/tests/module11_parity.sql`: server price == Dart `PriceBreakdown` for all
  448 plate × volume × fulfilment combinations; server draw == Dart `drawAt` for all
  86 component × volume × ingredient lines.
- `supabase/tests/module11_place_order.sql`: every error key, replay, totals (5635
  pickup, 7015 delivery), phone normalisation, exact draw and exact restore, double
  cancel, cancel windows, forced-off, the trigger refusal, and that guests can't
  reach `private`, `pricing` or `order_draws`. 7 planted bugs each made it (or the
  parity file) fail.
- `supabase/tests/module11_concurrency.sh`: two real connections. (1) Two guests,
  one sellable portion: one order, one `sold_out`, stock drawn once. (2) Same key
  twice at once: one order, the second call `replayed: true`. Proven: with the
  `for update` lock removed from the live function, race 1 fails (both guests got the
  last portion). Lock restored and re-verified.


### F1–F4 — App side wired to the server — ✅ SHIPPED
All adapters live in `lib/services/` (not `lib/repositories/` as first planned), next
to `SupabaseService`. Interfaces live in the features. Each adapter takes the client as
a lazily resolved function, as the global rules ask.

**Guest app (`lib/main.dart`)**
- `SupabaseOrderGateway` (implements `OrderGateway`, `cart_checkout/domain/order_placement.dart`):
  `rpc('place_order')` with `placeOrderPayload(draft)` + `catalogueFingerprint`, 15 s
  timeout. Outcomes: `OrderPlaced` (server number + total), `OrderRefused(reason)`,
  `OrderUnreachable`.
- `lib/services/order_wire.dart`: pure mappings, unit-tested. A chef plate is
  detected by its components (`signaturePlateFor`). The Postgres error key maps to a
  reason. **Rule:** an error Postgres answered (SQLSTATE / PGRST code) = nothing placed;
  no answer or a bare 3-digit HTTP code from a proxy = unreachable (may have landed).
- Checkout sheet: closes only on `OrderPlaced`. Refusals show in the button's
  existing "what's missing" slot (no new visuals). `couldNotSend` and unreachable keep
  the button live ("try again"). **Idempotency key:** one per attempt. It is renewed
  when the guest edits the order, *except* after an unreachable attempt, which keeps its
  key until the outcome is known, so a retry can't double-order. Edge it leaves: lost
  answer → edit → retry places the *first* draft (replay); the snackbar shows the real
  order number. Accepted.
- Home snackbar shows the kitchen's code (`M-<number>`).
- `ServerMenuAvailability`: polls `menu_availability()` every 30 s, on app resume,
  and right after a `sold_out` / `menu_changed` refusal (`OrderGatewayScope.onMenuStale`).
  It starts as "everything", so the first frame isn't a wall of sold-out.
- **Fixed an existing bug:** `MenuScope` (and now `OrderGatewayScope`,
  `ReflectionScope`) sat inside `home`, so the checkout sheet (a route above home)
  never saw them. `MenuScope.of` silently fell back to "everything in stock", so the
  sheet's own sold-out blocker never fired in the real app. Moved into
  `MaterialApp.builder`. Regression test: `test/main_wiring_test.dart` (proven: the
  old layout fails it).
- **Not built, on purpose:**
  - **No durable offline outbox for orders** (the plan's F2 had one). A food order
    queued offline and sent hours later delivers dinner nobody is waiting for. Instead:
    retry with the same key while the guest is in the sheet, and tell them plainly when
    it can't connect. So no `connectivity_plus` either: the real request failing is a
    better offline signal than interface state.
  - `streamGuestActiveOrder`: no screen shows live order status yet. Building the
    stream with no consumer would be dead code. Add it together with an
    order-tracking screen (needs a mockup).
  - `SavedPlaces` stays local: there is no addresses table. That belongs to an
    accounts feature.

**Kitchen app (`lib/main_kitchen.dart`)**
- `KitchenOrderFeed` (interface) / `SupabaseKitchenFeed`: realtime on `orders` and
  `order_items` is only a signal. Each change (debounced 250 ms) refetches the active
  board in one query with the plate embedded (`kitchen_wire.dart`, pure, tested).
  A sequence number drops out-of-order fetches.
- Status mapping: first station tap = the kitchen starts (PENDING→ACCEPTED→ASSEMBLING,
  so guest cancel closes there); third station = READY (packaging); "collected" =
  COMPLETED. Stations go through `set_station_status` with the *resulting* value, never
  a flip.
- `KitchenBoardController(feed:)`: keeps its local tap logic and chime. Snapshots
  arriving while a write is in flight are dropped, and one refresh runs once writes
  settle (no flicker back). A plate saved with all three stations but never marked READY
  is finished once (never in a loop).
- Behind staff sign-in (F6); with no `auth` (tests) it's the old empty demo board.

**Manager app (`lib/main_manager.dart`)**
- Migration `20261019150000_module11_back_office.sql`: staff-only `set_stock_count`
  and `adjust_stock` (a delta in one statement, so two tablets can't overwrite each
  other). Covered in `module11_rls.sql` (guest refused, arithmetic, missing
  ingredient). Proven by planting a missing staff check.
- `BackOfficeStore` / `SupabaseBackOffice`: load stock + forced-off + rails; realtime
  on `raw_ingredients` / `component_settings` (debounced 400 ms) → reload.
- `ManagerSuiteController(store:)`: count/receive/writeOff/setForcedOff and
  calibrate/revert are written back. Calibration sends **only the portion factor**
  (what the server's draws use); calibrated nutrition figures stay on that device, as
  before. Reloads wait for in-flight writes. A failed write is undone by the next
  reload (the server's view wins), not left looking saved.
- `Quantity.fromMinorUnits` added: DB values in, no decimal round-trip.
- Stock-count UI is F7; sign-in is F6.

**Proof**
- `flutter test`: 835 green. New: `test/services/order_wire_test.dart`,
  `test/features/cart_checkout/checkout_placement_test.dart`,
  `test/main_wiring_test.dart`, `test/features/kitchen_display/kitchen_feed_test.dart`,
  `test/features/manager_suite/back_office_sync_test.dart`. Six planted bugs (key
  renewal ×2, scope layout, mid-write snapshot, flip-not-set, reload over a write)
  each made one fail.
- **`bash tool/live_e2e.sh`**: the real Dart adapters against the live project, in
  Chrome. Throwaway staff account + stock for one plate, then: anonymous guest,
  availability, place (server total == app total), replay, `needs_phone`, `sold_out`
  named, staff kitchen feed sees the ticket → 3 stations → READY → COMPLETED,
  back-office delivery + forced-off. Restores stock, settings and accounts on exit
  (verified: 0 left behind). Passed.

Mockup (approved by Ahmed, all three recommended designs):
https://claude.ai/artifact/HDHL1gjJ5ZNJF8MSVqk9Z9

### F5 — Delivery phone — ✅ SHIPPED
- `cart_checkout/domain/guest_phone.dart`: `saudiMobile()` normalises what people
  type (`05…`, `5…`, `+966…`, `00966…`, spaces/dashes, Arabic-Indic digits) to
  `+9665XXXXXXXX`, else null. `formatSaudiMobile`, `localPart`. The `PhoneMemory`
  interface; `SharedPreferencesPhoneMemory` (`mawzoon.guest_phone.v1`, re-validated on
  read).
- `OrderDraft.phone` + `withPhone()`; delivery blocker `needsPhoneBlocker`, after the
  address blocker (`OrderRefused(needsPhone)` reuses it). Payload sends `customer_phone`.
- Checkout: `_PhoneEntry` under the addresses, delivery only. First time: a field with a
  `+966 |` prefix, phone keyboard, digits only, and the help line. Remembered: one row
  plus "تغيير". **Changed from the mockup:** the label sits *above* the number, not
  beside it. Side by side overflowed a 390 pt phone by 136 pt (caught by tests), and a
  phone number can't be shortened with "…". Typing gives no haptic per keystroke. The
  sheet lifts above the keyboard (`viewInsets` padding in `showCheckoutSheet`).
- Home screen reads the memory before opening checkout (no flicker) and writes the
  number after a placed order.
- Shared field look extracted to `ui_primitives/controls/mawzoon_input_decoration.dart`
  (checkout goldens unchanged after the extraction: pixel-identical).
- Not done: `profiles.phone` isn't written (local memory only). Add it if staff ever
  need a guest's number outside an order.

### F6 — Staff sign-in — ✅ SHIPPED
- `staff_auth/domain/staff_auth.dart`: `StaffAccess` (SignedIn / SignedOut /
  NotOnTeam(email)), `StaffSignInFailure` (wrongCredentials, deliberately one message
  for both parts; unreachable). `SupabaseStaffAuth`: email+password, then `is_staff()`.
  GoTrue 400 = wrong credentials.
- `StaffGate` (shared by both apps): blank canvas while checking a stored session →
  form / not-on-team card / the app. `main_kitchen.dart` and `main_manager.dart` pass
  `SupabaseStaffAuth()`. The live board/office is a child widget that owns its
  controller, so leaving it closes the realtime channel. No `auth` = the old demo (tests).
- Manager calibrations are stamped with the signed-in email.
- `ui_primitives/controls/mawzoon_pill_button.dart` extracted (used by the gate and
  the stock screens).
- Not done: no sign-out button in either app. The copy says the screen stays signed in
  until the manager signs it out (revoke the session in the Supabase dashboard).
  Not-on-team's "use another account" signs out.
- Creating staff: Supabase dashboard → Authentication → add user (email + password,
  auto-confirm), then `update public.profiles set is_staff = true where id = '<uid>';`.

### F7 — Stock take / delivery / write-off — ✅ SHIPPED
- `manager_suite/domain/stock_entry.dart`: `parseBulkAmount` (typed in kg / L / pieces;
  Arabic digits, `٫` and `,` accepted; negative or garbage → null), `applyMovement`,
  `StockMovement`.
- `arabic_count.dart`: the four-form rule extracted to `arabicCounted()`;
  `arabicKilocalories` now goes through it (same output) + `arabicItemsGenitive`.
  **Digits are Western** (`احفظ جرد 8 مواد`), matching the app's existing counts; the
  mockup showed `٨`.
- `StockCountScreen` ("ابدأ الجرد" on the stock panel): one column per storage area,
  store-room order. A blank field = not counted (book untouched). Counted = olive ring,
  unparseable = terracotta ring and save disabled. Units always visible (`suffixIcon`;
  `suffixText` hid them until typing). The "whole menu is sold out" line shows only
  when every count is zero.
- `StockMovementDialog` (tap any stock row): count / delivery / write-off; sign shown
  as `+` / `−`; before → after (wraps to two lines rather than overflow; a write-off
  below zero shows in terracotta); action label per movement.
- Not done: cancelling count mode with typed entries discards them without asking.

**Proof for F5–F7:** 887 tests green including goldens. New goldens (looked at):
`checkout_light_remembered`, `staff_sign_in`, `staff_not_on_team`,
`stock_count_mode`, `stock_delivery_dialog`; updated `checkout_*`,
`manager_inventory_*`. Planted bugs caught: delivery without phone, a 9-digit
non-mobile accepted, not-on-team opening the board, write-off recorded as a delivery.
`tool/live_e2e.sh` also covers delivery with a phone, wrong vs right staff password,
and leaves live stock byte-identical (hash checked).

**Live data note:** live stock was seeded with demo stock (60 plates' worth per
ingredient, the same as `InventoryLedger.stockedFor(60)`) on Ahmed's go. The first
real count in F7 replaces it.

## Execution notes (for whoever codes this)

- Realtime uses channel `onPostgresChanges(...)` as a refetch signal (see
  `SupabaseKitchenFeed`), not `.stream()`. Copy that pattern for any new live screen;
  don't build state from event payloads.
- `supabase_flutter` is pinned exact; ask before any major bump (global rule).
- New UI that talks to the server goes through the existing scopes/controllers
  (`OrderGatewayScope`, `ManagerSuiteController(store:)`, `KitchenBoardController(feed:)`).
  Scopes that routes must see belong in `MaterialApp.builder`, never inside `home`.
- `Quantity` and `Money` are both integer-minor-units types with `unit`/no-unit
  arithmetic guards (`_requireUnit` throws on a unit mismatch) — when mapping a DB
  row back to these types, construct through their existing factories
  (`Quantity.zeroIn`, etc.), don't hand-roll a constructor bypass.
- `MawzoonRecipes.forOption`/`forComponent` (`lib/core/menu/recipe_book.dart`) is the
  existing source of truth for component→ingredient lines. `recipe_lines` is that
  data in SQL, generated by D7, never typed by hand.
- The kitchen board marks stations only through `rpc('set_station_status', …)`. It
  never writes `station_status` directly (no grant exists), and never sends a
  client-computed toggle. Map the KDS's `toggle()` to "set to the opposite of what the
  board currently shows".
- Guests are `authenticated` (anonymous auth), not `anon`. A query returning `[]` for a
  guest usually means RLS is working, not that the query is wrong.
- New SQL goes in a **new** timestamped file under `supabase/migrations/`. Never edit
  the applied one; it's recorded as applied and won't re-run.

## Verification (what "done" requires — no exceptions per project rules)

1. `flutter analyze` — 0 errors (currently true; re-check after each step).
2. `flutter test -x golden` — 835+ green, no regressions.
3. **RLS proof:** `supabase/tests/module11_rls.sql` passes against the live database
   (✅ for D1–D3). Every new table or function adds its own refusal cases there,
   proven by planting the hole and watching it `FAIL:`.
4. **Concurrency:** `bash supabase/tests/module11_concurrency.sh` ✅ (proven by
   removing the lock).
5. **Server logic:** `module11_place_order.sql` and `module11_parity.sql` pass live ✅.
6. Migrations and seed are re-runnable: each applied twice with psql `-1 -f`, no
   error ✅.
7. App side: `bash tool/live_e2e.sh` passes ✅. Re-run it after any change to
   `lib/services/` or the SQL.
