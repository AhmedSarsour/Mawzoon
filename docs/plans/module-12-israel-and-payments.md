# Module 12 — Israel market + real payment (McDonald's-style)

Status: **L, S, A2/A4/A5/A6, K1/K2, C app side shipped. E core shipped (not deployed — no
provider account yet). Left: A3 (card page) + E Cardcom adapter + deploy (Opus).** Mockup (**approved 2026-10-22**):
https://claude.ai/artifact/MPLbzfkAB12E5M4Emo6UaQ — 1 checkout pickup, 2 checkout delivery,
3 receipt (code), 4 tracking, 5 counter tablet, ✕ five-button layout (rejected: Hick's Law).

Why: Mawzoon operates in Israel and Ahmed owns it. Modules 01–11 assumed Saudi Arabia
(SAR/halalas, 15% VAT, +966 phones, "mada"). Payment today is a label only: an order
marked `wallet` or `savedCard` reaches the kitchen with no money moved.

The model (Ahmed, 2026-10-22): like a McDonald's kiosk. Guest builds the plate, then picks
**pay at the counter** or **pay by card**. Guests in his city aren't used to paying in
apps, so it must be dead simple — and fake orders must cost nothing.

**The core rule: no food is made before money is taken.** A counter order waits, invisible
to the cooks, until a staff member taps "paid" at the counter. A card order waits until
the payment company confirms. A fake order then wastes nothing but a held portion count
for a few minutes.

Order of work: **L → S → E → A + K + C**. L ships on its own.

---

## Shipped by Opus (2026-10-22) — S, E core, C server

**The kitchen can't see an order until it's paid.** The counter app (K, shipped below) is
what marks orders paid.

Database (applied live; separate files because a new enum value can't be used in the
transaction that adds it — **don't run either with `-1`**):
- `supabase/migrations/20261022130000_module12_awaiting_payment.sql` — enum value
  `AWAITING_PAYMENT` before `PENDING`.
- `supabase/migrations/20261022140000_module12_payment_state.sql`:
  - `private.payment_rules()` — the knobs: counter hold 45 min, card hold 15 min,
    strike limit 3, strike window 7 days.
  - `orders` + `payment_due_at`, `paid_at`, `cancel_reason` (`guest`/`staff`/`expired`);
    default status `AWAITING_PAYMENT`; partial index on due time.
  - `payments` table (S3). RLS: staff read only; no client writes. `unique (provider,
    provider_txn_id)`; **at most one `paid` row per order** (partial unique index).
  - `guard_order_status`: `AWAITING_PAYMENT → PENDING` only with the `mawzoon.paying`
    flag (set only inside `mark_paid_*`); `→ CANCELLED` only with `mawzoon.cancelling`.
  - `private.check_new_order` (insert trigger) now **forces** `status = AWAITING_PAYMENT`
    and sets `payment_due_at` — every insert path, not just `place_order`.
  - `private.cancel_orders(ids[], reason)` — the one cancel path (guest, staff, expiry):
    locks ingredients in id order, restores stock for AWAITING/PENDING/ACCEPTED, flips a
    `paid` payment to `needs_refund`.
  - `public.cancel_order`: **guests may cancel only unpaid orders** (was: PENDING). A paid
    order is staff's to cancel → its payment becomes `needs_refund`.
  - `private.expire_unpaid_orders()` + pg_cron job `mawzoon-expire-unpaid` every minute.
    One transaction, `FOR UPDATE SKIP LOCKED`, max 200 per run.
  - `public.mark_paid_counter(order_id)` (staff). Errors: `staff only`, `not_found`,
    `order_expired`, `order_cancelled`, `card_required` (delivery). Repeat →
    `{already_paid: true}`. **Strict on the deadline** (past due = expired even before the
    sweep). Works for card orders too (guest whose card failed can pay at the till).
  - `public.mark_paid_card(order_id, provider, txn_id, amount, currency, raw)` (service
    role only). Results: `paid`, `duplicate`, `already_paid`, `order_cancelled`,
    `amount_mismatch` — all but the first two record `needs_refund`. **Lenient on the
    deadline**: still AWAITING (not swept) → paid, because money already moved.
  - `place_order`: locks the guest's profile row first (serialises one guest's taps);
    refuses `unpaid_order_open` (detail = open order id, hint = its number) — a past-due
    one doesn't count; refuses `counter_blocked` (C4: ≥3 counter orders expired in 7
    days); answer adds `status`, `payment_method`, `payment_due_at`.

App (pure wire + one service; no UI):
- `OrderPlaced.awaitingPayment`, `OrderPlaced.paymentDueAt`.
- `RefusalReason.unpaidOrderOpen` (+ `OrderRefused.openOrderId/openOrderNumber`),
  `RefusalReason.counterBlocked`, with Arabic/English messages.
- `lib/features/counter_desk/domain/counter_payment.dart`: `CounterPayResult`,
  `CounterDesk`. `lib/services/counter_wire.dart` (pure mapping),
  `lib/services/supabase_counter_desk.dart` (`markPaid(orderId)`).

Edge functions (`supabase/functions/`, Deno, **no dependencies** — plain fetch to
PostgREST; not deployed):
- `_shared/payment_provider.ts` — `PaymentProvider` adapter (`createHostedPage`,
  `verifyWebhook`), `providerFromEnv` (returns null until an adapter exists → 503
  `card_unavailable`).
- `_shared/rest.ts` — `readOwnOrder` (anon key + guest JWT, RLS), `markPaidCard`
  (service key).
- `create-payment/handler.ts` — amount from the row; refuses `not_signed_in`,
  `invalid_payload`, `not_found`, `not_awaiting_payment`, `not_card_order`,
  `order_expired`, `card_unavailable`; provider error → 502. Page expiry = order due time.
- `payment-webhook/handler.ts` — body goes only to the adapter; 200 for settled results
  (incl. duplicates/refunds), 400 unrecognised, 500 DB down, 502 provider down.
  Deploy with `--no-verify-jwt`.

Evidence:
- SQL: `module12_payment_state.sql` (new), `module12_israel`, `module11_place_order`,
  `module11_rls`, `module11_parity` — all pass. Concurrency script + 2 new real races
  (one guest, two keys at once → one order; two cashiers at once → one payment) pass.
- Live e2e passes: order unpaid with ~45 min deadline → second order refused naming it →
  kitchen doesn't see it → cashier marks paid (second tap = already paid) → kitchen sees it.
- Flutter: 899 tests pass, analyzer 0 errors. Deno: 12 tests pass, `deno check` clean.
- Planted bugs, each caught then restored — SQL (11): paying flag ignored; orders start
  PENDING; card amount unchecked; currency unchecked; cancel keeps stock; counter ignores
  deadline; strike limit 4; duplicate txn unchecked; paid cancel not flagged; expiry too
  eager; one-open-order check removed. Dart (3): unpaid hint dropped; already_paid
  inverted; awaitingPayment ignored. Deno (4): amount from request; paid order gets a
  page; guest read with the service key; declined charge pays.

## Shipped by Sonnet (2026-10-22) — A2, A4, A5, A6, K1, K2, C app side

Guest (`lib/features/order_tracking/`):
- `OrderStatusScreen` is both the receipt (unpaid: code, total, "نبدأ التحضير بعد الدفع",
  "محفوظ لك حتى HH:mm" from `payment_due_at`, cancel with a confirm dialog) and the tracker
  (paid → in kitchen → ready; expired / cancelled / not-found messages). Driven by the order
  row through `OrderTracker` (`SupabaseOrderTracker`: realtime = refetch signal, filtered on
  the order id). Expiry/cancel/footer are pinned, never scrolled away.
- `order_home_screen.dart`: placing an order pushes the screen (old snackbar kept only for
  the no-gateway demo path); `_resumeOpenOrder` on launch (A5); `CheckoutResult.openOrderId`
  makes `unpaidOrderOpen` jump to that order. `counterBlocked` shows its message on the sheet.
- `OrderGatewayScope.tracker` (wired in `main.dart`). Columns/mapping: `tracking_wire.dart`.
- Delivery/card copy is not built (A3). Card orders show the counter wording until A3 —
  harmless while `cardPayment` is off.

Counter (`lib/features/counter_desk/`, `lib/main_counter.dart` behind `StaffGate`):
- `SupabaseUnpaidOrders` (status `AWAITING_PAYMENT`, not `DELIVERY`, by due time),
  `CounterController` (search, ask → "نعم" → `markPaid`, every `CounterPayResult` has a
  message; `unreachable` keeps the question open), `CounterScreen`. Past-due cards grey out
  from the tablet clock; the server stays the judge.
- Skipped from the mockup: footer stats ("اليوم: 23 مدفوع") and signed-in email.

Proof:
- `dart analyze`: 0 errors. `flutter test`: 939 pass (40 new).
- `bash tool/live_e2e.sh` → E2E PASS, now also covering: open order read-back, tracking
  stream, guest cancel (+ realtime push, repeat = already cancelled), counter list.
- Planted bugs, each caught then restored (15): +45 client expiry; receipt says "received";
  cancel without asking; old snackbar back; no jump on `unpaidOrderOpen`; no resume on
  reopen; unknown status = awaiting payment; too-late cancel read as unreachable; counter
  skips confirmation; unreachable closes the question; search ignored; past-due still
  payable; counter without `StaffGate`; `counterBlocked` message blanked.
- Simulator screenshots (Arabic RTL): receipt, tracking (iPhone 17 Pro Max), counter (iPad).

## Left

- **A3 (Opus-adjacent):** card → `create-payment` → in-app browser → back to the status
  screen (reuse `OrderStatusScreen`; it already follows the row). Needs the Cardcom adapter.
- **E (Opus, needs Ahmed's Cardcom sandbox):** the Cardcom adapter (`PaymentProvider`),
  `PAYMENT_PROVIDER` + Cardcom secrets via `supabase secrets set`, deploy both functions,
  E3 refund list screen (reads `payments where status = 'needs_refund'`).
- Known nit: `12–15 دقيقة` reads reversed in RTL ("15–12"); same string as the old
  estimate. Fix with an LRM or a different dash if it bothers you.

---

## Decisions

| # | Decision | Value |
|---|---|---|
| D1 | VAT rate | 18% (עוסק מורשה). **0% if Ahmed registers as עוסק פטור** — confirm with an accountant. One constant. |
| D2 | Prices | Same numbers in ₪ (49 base, 15 athletic, 12 delivery) — placeholders. |
| D3 | Provider | Cardcom, behind a server adapter. Verify fees vs Grow / PayPlus / Allpay first. |
| D4 | Choices at checkout | Two: **ادفع عند الاستلام** (pickup only) and **ادفع بالبطاقة**. Bit / Apple Pay / Google Pay appear on the card page as a bonus, not as extra buttons (Hick's Law). |
| D5 | Delivery | **Off at launch** (Ahmed: built but hidden). When on: card only. |
| D6 | Counter hold | Unpaid counter order expires after 45 min; card order after 15 min. Stock returns. |
| D7 | Open unpaid orders | Max 1 per guest at a time. |

---

## L — Israel locale — ✅ SHIPPED (live, 2026-10-22)

- **Launch switches** `lib/core/config/launch_switches.dart`: `delivery = false`,
  `cardPayment = false`. Twins `pricing.delivery_enabled` / `card_payment_enabled`,
  written by the seed from the Dart constants. Trigger `private.check_new_order` (before
  insert on `orders`) refuses `delivery_unavailable`, `card_unavailable`, `card_required`
  (counter + delivery) and legacy `wallet`/`savedCard`/`cash` (`invalid_payload`). App maps
  the three new keys to `RefusalReason.optionUnavailable`.
  **To turn card on (after E/A3):** flip `LaunchSwitches.cardPayment`, re-run
  `dart run tool/catalogue_seed.dart`, apply the seed.
- `CheckoutSheet(offerDelivery:, offerCard:)` default to the switches (tests pass `true`
  for the full sheet). Off: a `_PickupLine` replaces the mode switch; only `counter` shown.
- `Money`: `₪` format (`49.00 ₪` / `₪49.00`); `percentage` replaced by
  `includedTax(basisPoints)` — integer formula `(2·m·bp + g) ~/ (2g)`, g = 10000+bp,
  identical in `private.quote_plate`.
- `PriceBreakdown`: VAT-inclusive. `total` = sum of charges; `tax` extracted;
  `vatBasisPoints = 1800`; `lines()` no longer has a VAT row; `includedTaxNote` ("يشمل
  ضريبة 18%"), null at 0 bp. Parity test now compares total **and** tax (448 combos).
- `PaymentMethod`: `counter`, `card` (+ `pickupOnly`, `pickupOnlyReason`). DB enum gained
  `counter`, `card`. `OrderDraft.withMode` swaps counter→card on delivery; blocker if not.
- Phone: `israeliMobile` / `formatIsraeliMobile` (`050-123-4567`) / `localPart` (`050…`).
  Stored `+966` numbers read as null.
- Arabic-Indic digits removed from catalogue, recipes, estimates, saved places.
- Home dock total uses `defaultFulfilment` (pickup while delivery is off).
- Migration `20261022120000_module12_israel.sql` (don't run with `-1`). Test
  `supabase/tests/module12_israel.sql`. Module 11 SQL tests switch delivery/card on inside
  their rolled-back transaction.
- Proof: 893 Flutter tests, all SQL tests, concurrency, live e2e pass. Planted bugs caught:
  trigger ignoring the delivery switch, SQL VAT truncating (parity), Dart VAT truncating,
  card switch left on. Fonts checked: full IBM Plex Sans Arabic and Plus Jakarta Sans both
  contain `₪` (U+20AA).
- Deviation from mockup: kept the existing labels "طريقة الدفع" and "تأكيد الطلب"
  (never rename user-facing terms); VAT note sits in the price lines, not the bottom bar.
- ~~Gap until S ships~~ — closed by S: counter orders wait unpaid, invisible to the kitchen.

## S — Server payment state — ✅ SHIPPED (live; details in "Shipped by Opus")

- **S1** New order status `AWAITING_PAYMENT` before `PENDING`. The kitchen board filters by
  `kitchenActiveStatuses`, so cooks never see it — no client change needed. Trigger:
  `AWAITING_PAYMENT → PENDING` only via `mark_paid_*`; `→ CANCELLED` only via
  `cancel_order` / expiry (both through `private.cancel_orders`).
- **S2** `place_order`: every new order starts `AWAITING_PAYMENT` with `payment_due_at`
  (counter +45 min, card +15 min). Refuses `counter` + `DELIVERY` (`card_required`).
  Refuses a second open unpaid order for the same guest (`unpaid_order_open`), naming the
  existing one in the error (detail/hint) — a refusal, not a fake success, so the app
  can't mistake it for a new order.
- **S3** `payments(id, order_id, method, provider, provider_txn_id unique null,
  amount_minor_units, currency, status, staff_id null, created_at, raw jsonb)`. No client
  grants; only security-definer functions write it.
- **S4** Expiry: `pg_cron` (enabled by the migration) every minute cancels
  `AWAITING_PAYMENT` past `payment_due_at`. Ingredients locked in id order.
- **S5** `mark_paid_card(order_id, txn_id, amount, currency)` (service role only): amount
  == order total, currency == `ILS`, idempotent on txn id. Order already CANCELLED →
  payment row `needs_refund`, order not revived.
- **S6** `mark_paid_counter(order_id)` (staff only, `is_staff()`): records a counter
  payment with `staff_id`, moves to PENDING. Double tap = no-op.

## E — Edge functions (**Opus**: security) — core ✅ shipped, Cardcom adapter + deploy left

- **E1** `create-payment(order_id)`: reads the order with the guest's JWT (RLS proves
  ownership), takes the amount **from the row, never the request**, asks the provider for
  a hosted-page URL. Secret in `supabase secrets`, never in the app.
- **E2** `payment-webhook`: body is a hint only — takes the txn id, **asks the provider
  API for the real status**, then `mark_paid_card`. 200 on duplicates. Verify the
  signature too if the provider signs.
- **E3** Refunds: start manual — manager sees a "refund needed" list.
- **E4** Receipts / tax invoices: card → provider issues them (Cardcom does). Counter →
  the restaurant's register, as today. Confirm document type with the accountant.

## A — Guest app (after mockup)

- **A1** Checkout: two big payment cards (D4). In delivery mode, the counter card is
  greyed with its reason ("التوصيل بالبطاقة فقط") — clarity, not a hidden option.
- **A2 ✅** Counter order placed → **receipt screen**: big code `M-12`, total, "اعرض الرقم
  عند الصندوق وادفع — نبدأ التحضير بعد الدفع", and the expiry time. Honest about the
  wait (sets expectation; removes the "why isn't it ready?" surprise).
- **A3** Card → `create-payment` → provider page in an in-app browser
  (`url_launcher` `LaunchMode.inAppBrowserView`, **not** a WebView — Apple Pay and the
  Bit hand-off are unreliable in WebViews; verify on device) → back to a status screen.
- **A4 ✅** Status screen (also the order-tracking screen): waiting for payment → received →
  being made → ready. Driven by the order row (realtime refetch, like the kitchen feed).
- **A5 ✅** App reopened with an open order → that screen, not the menu.
- **A6 ✅** Cancel button while unpaid (frees the guest and the stock).

## K — Counter screen (staff; after mockup)

- **K1 ✅** List of unpaid counter orders: code, total, age. Big digits (cashier reads the
  guest's phone). Tap → confirm total → "تم الدفع". Search by code number.
- **K2 ✅** Its own entry point `lib/main_counter.dart` behind `StaffGate` (Ahmed: cashier
  never sees cook screens or stock).

## C — Fake-order rules — ✅ shipped (server in `place_order`, app on the sheet)

- **C1** Counter orders never cook unpaid (S1). The main defence.
- **C2** One open unpaid order per guest (S2).
- **C3** Delivery is card-only (S2).
- **C4** A guest with 3 expired counter orders in 7 days loses the counter option (card
  still works). Server-side, shown with its reason. Anonymous user reinstall resets it —
  acceptable: friction, not a wall.
- Later, only if needed: SMS code check (OTP) — costs per SMS.

---

## Edge cases

1. Card paid twice → second txn recorded `needs_refund`.
2. Card payment after expiry → order stays CANCELLED, `needs_refund`.
3. Webhook never arrives → order expires, stock returns; late payment → case 2.
4. Webhook duplicated / out of order → idempotent on txn id.
5. Forged webhook → E2 re-fetches from the provider; forged body changes nothing.
6. Amount tampering → amount from the DB row; re-checked in `mark_paid_card`.
7. Price change mid-payment → total fixed at `place_order`.
8. Guest cancels while unpaid → allowed; stock returns.
9. Kitchen never sees `AWAITING_PAYMENT` — test it.
10. Cashier taps "paid" twice / on an expired order → `already_paid` / `order_expired`
    ("انتهى الطلب").
11. Guest arrives at minute 46 → expired; counter screen shows "انتهى", guest re-orders
    (app shows the expiry time up front so this is rare).
12. Two cashiers tap the same order → row lock, one wins, other sees "مدفوع".
13. Old installs with +966 stored → no phone (L3). Old `wallet`/`savedCard` rows readable.
14. VAT 0% → VAT line hidden, parity green.
15. `₪` glyph missing → font fallback.
16. Guest switches pickup → delivery after choosing counter → card auto-selected, with
    the reason shown.
17. Refund fails at provider → stays on the manager list.
18. Staff cancels a paid order → payment flips to `needs_refund` (refund list).
19. Card paid at minute 15:30, sweep hasn't run → accepted (money moved, stock still held).
    Counter at minute 45:30 → refused (`order_expired`): the guest was shown that time.
20. Guest's open unpaid order is past due but not swept → doesn't block a new order.
21. Guest double-taps "place" with two different keys → profile row lock; one order, the
    other `unpaid_order_open` (race-tested).
22. Card switch off + guest has 3 strikes → no way to pay; acceptable at launch (they're
    the fake-order pattern). Message says why.

## Execution notes (for the implementing model)

- **Verify, don't assume:** Cardcom API version, hosted-page ("LowProfile") fields, whether
  amounts are agorot or shekels-with-decimals, webhook payload, webhook signing. Read
  current docs.
- Reuse Module 11 patterns: error keys mapped in `supabase_order_gateway.dart`; realtime
  as a refetch signal (`supabase_kitchen_feed.dart`); SQL tests in `supabase/tests/` against
  the live DB with the redacted db_url flow; extend `tool/live_e2e.sh`.
- Money is integer minor units. Server rounds VAT with numeric, Dart with double — the
  parity test (448 combos) must stay green after L2.
- Price/VAT changes alter the catalogue fingerprint → regenerate with
  `tool/catalogue_seed.dart`; never hand-edit `catalogue_fingerprint.g.dart`.
- Pin new packages exactly with a "why" comment.
- **S and E are Opus-only:** real money, stock locks, webhook trust. The Cardcom adapter
  is E — Opus, not Sonnet.
- Status names: guest-facing copy for `AWAITING_PAYMENT` must not say the kitchen has it.
- New SQL test fixtures that need an order *on the board* must pay it: set
  `mawzoon.paying` to `on` (see `module11_rls.sql`) or call `mark_paid_counter` as staff.
  Inserted orders always start `AWAITING_PAYMENT` (the trigger forces it).
- A guest test that places two orders must pay or cancel the first (`unpaid_order_open`).
- Tests: `deno test supabase/functions/tests/` for E; SQL tests in `supabase/tests/`
  (`module12_payment_state.sql` covers S); `bash tool/live_e2e.sh` end to end.
