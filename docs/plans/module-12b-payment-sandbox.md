# Module 12b — Payment sandbox (test the card path end to end, no real money)

Status: **planned, waiting for Ahmed's go.** Parent plan: `module-12-israel-and-payments.md`
(read its "Shipped by Opus" first). Mockup: https://claude.ai/artifact/G3jLuGvKaJp5JZkqRm7iWs (1 card receipt, 2 fake card
page, 3 scenarios, 4 declined, 5 checking payment, 6 counter test build, ✕ debug panel).

Why: Ahmed must test every payment scenario on a real phone before Cardcom exists. A fake
button that flips a flag would test nothing. So we build a **fake card company** that plugs
into the same adapter slot Cardcom will use. Everything behind it is the real code:
`create-payment` → card page → provider records the charge → `payment-webhook` asks the
"provider" what happened → `mark_paid_card` → the order screen updates live.

Decisions (Ahmed, 2026-10-23):
- D1 Fake card page **inside the app** (a Supabase function can't serve HTML — GET
  `text/html` is rewritten to `text/plain`). Opens where the real card page will.
- D2 Staff-only **"skip the clock"** button on the counter tablet, test builds only,
  refused by the server unless sandbox mode is on.
- D3 **Deploy** both card functions + `sandbox-pay` to the live project, provider =
  `sandbox`. Card-paid test orders get a `تجربة` badge on kitchen + counter tickets.

---

## Safety model (read first)

The sandbox can mark an order paid with no money. It must be impossible to leave on by
accident in a way a real guest can use:
- **Server switch** `pricing.sandbox_payments` (default false). `mark_paid_card` refuses
  provider `sandbox` unless it's on; `debug_expire_now` refuses unless it's on.
- **One provider at a time:** `PAYMENT_PROVIDER=sandbox` env on the functions. Setting
  `cardcom` later removes the sandbox adapter from the webhook path entirely.
- **App:** the card option and the sandbox page exist only in builds run with
  `--dart-define=MAWZOON_SANDBOX=true`. Store builds can't show them.
- **Visible:** an order gets `orders.is_test = true` the moment a sandbox card page is
  opened for it (so the counter sees the badge before payment too) → `تجربة` badge.
- Launch check (SQL test `module12b_sandbox.sql` asserts it's documented, not enforced
  live): before launch, `sandbox_payments = false`. Listed in the parent plan's launch list.

## Items

### Server — **Opus** (money path, webhook trust)

- **SB1** Migration `…_module12b_sandbox.sql`:
  - `pricing.sandbox_payments boolean not null default false`.
  - `orders.is_test boolean not null default false`.
  - `private.sandbox_sessions(id uuid pk, order_id, amount_minor_units, currency,
    expires_at, created_at)` and `private.sandbox_charges(id text pk 'sbx_…', session_id,
    amount_minor_units, currency, approved bool, created_at)`. Private schema: no API access.
  - `check_new_order`: card allowed when `card_payment_enabled OR sandbox_payments`.
  - `mark_paid_card`: provider `sandbox` → refuse unless `sandbox_payments`.
  - `sandbox_open_session` sets `orders.is_test = true`.
  - `public.debug_expire_now(order_id)` — staff only, sandbox on only: sets
    `payment_due_at = now()` then runs the sweep for that order (same `cancel_orders`).
  - Service-role-only RPCs used by the functions: `sandbox_open_session(order_id, amount,
    currency, expires_at)`, `sandbox_record_charge(session_id, amount, approved)` →
    charge id, `sandbox_get_charge(charge_id)` → the "provider API" answer.
- **SB2** Sandbox adapter in `supabase/functions/_shared/sandbox_provider.ts`:
  `createHostedPage` opens a session and returns `mawzoon-sandbox://pay?session=<id>`;
  `verifyWebhook` reads only `charge_id` from the body and asks `sandbox_get_charge`
  (exactly as Cardcom's adapter will ask Cardcom's API). `providerFromEnv("sandbox")`.
- **SB3** Function `sandbox-pay` (POST, guest JWT): `{session_id, scenario}`. Checks the
  session's order is the caller's (RLS read, like create-payment), then plays the
  scenario — records charge(s) and sends webhook(s) to the **deployed**
  `payment-webhook` over HTTP (delays via `EdgeRuntime.waitUntil`). Scenarios:

  | key | the card company does | expected end state |
  |---|---|---|
  | `approve` | charge OK, webhook now | paid → kitchen |
  | `decline` | charge declined, webhook says declined | still unpaid; page says declined, can retry |
  | `slow_webhook` | charge OK, webhook after 20 s | "checking payment…" then paid |
  | `lost_webhook` | charge OK, no webhook | unpaid → expires at 15 min; money "taken" → see `resend` |
  | `resend_webhook` | re-sends the last charge's webhook | paid, or refund-list if expired |
  | `duplicate_webhook` | charge OK, webhook twice at once | paid once, one payment row |
  | `double_charge` | two charges, two webhooks | paid + one `needs_refund` |
  | `wrong_amount` | charges 1 ₪ less | stays unpaid, `needs_refund` |
  | `forged_webhook` | posts a fake "paid" body with an unknown charge id | refused (400), nothing changes |
  | `close` | (app only) guest closes the page | unpaid, back on the receipt with "pay by card" |

- **SB4** Deploy `create-payment`, `payment-webhook --no-verify-jwt`, `sandbox-pay`;
  `supabase secrets set PAYMENT_PROVIDER=sandbox PAYMENT_RETURN_URL=mawzoon-sandbox://done`;
  set `pricing.sandbox_payments = true`. Never print keys.
- **SB5** Tests: Deno (adapter + sandbox-pay with fake fetch), SQL `module12b_sandbox.sql`
  (switch refusals, is_test, debug_expire_now rules), live e2e extended: card order →
  `approve` → kitchen sees it with `is_test`.

### App — Sonnet (after the mockup is approved)

- **SB6** `LaunchSwitches.sandbox = bool.fromEnvironment('MAWZOON_SANDBOX')`; card shown
  when `cardPayment || sandbox`.
- **SB7** Card receipt (A3 for the sandbox): `TrackedOrder.paymentMethod` (add to
  `tracking_wire`); card + unpaid → "ادفع بالبطاقة" primary button → `create-payment` →
  URL scheme `mawzoon-sandbox` opens **SandboxPayScreen** (the real Cardcom URL will open
  the in-app browser later). Back from the page → "نتحقق من الدفع…" until the order row
  moves; after 30 s without change: "لم يصلنا تأكيد بعد" + "ادفع بالبطاقة" again.
- **SB8** `SandboxPayScreen` (mockup frame 1–3): orange `SANDBOX` bar, merchant, code,
  amount, fake card fields pre-filled, primary "ادفع 49.00 ₪" = `approve`, "More
  scenarios" sheet with the rest, close (X) = `close`. Processing spinner ~1.2 s like a
  real page; declined state with retry.
- **SB9** Counter tablet: in sandbox builds, per unpaid order "⏩ انتهاء الآن" (calls
  `debug_expire_now`), behind a confirm.
- **SB10** `تجربة` badge on kitchen ticket + counter row when `is_test`.
- **SB11** `docs/testing/payment-scenarios.md` — the scenario script Ahmed runs (Opus
  writes it with SB5; Sonnet keeps it in sync with the UI).

## Edge cases

1. Sandbox switch off but adapter env still `sandbox` → `mark_paid_card` refuses →
   webhook 200 `sandbox_off`, order stays unpaid (no free food).
2. Guest calls `sandbox-pay` for someone else's session → 404, nothing recorded.
3. Session expired (order due passed) → `sandbox-pay` answers `order_expired`; page shows it.
4. `slow_webhook` and guest cancels during the 20 s → webhook arrives → `order_cancelled`
   → refund list. (Real life: guest pays then panics.)
5. `approve` tapped twice fast → two charges? No: page disables the button while
   processing; server: one open charge per session per 10 s for `approve` (idempotent on
   session + scenario within 10 s).
6. `resend_webhook` with no prior charge → "nothing to resend".
7. App killed while on the card page → reopen lands on the receipt (A5), still unpaid.
8. Card order on the counter screen → cashier may still take money (S rule) → later
   webhook = `already_paid` → refund list.
9. `debug_expire_now` on a paid order → refused (`not_awaiting_payment`).
10. Real build (no dart-define) → no card option, no sandbox screen, no ⏩ button.
11. `PAYMENT_PROVIDER` unset → create-payment 503 → app: "الدفع بالبطاقة غير متاح الآن".

## Execution notes (for the implementing model)

- **SB1–SB5 are Opus**: they decide whether money-less "paid" can reach real guests.
- Edge Functions can't serve HTML (Supabase docs). Don't try to host the page there.
- `EdgeRuntime.waitUntil(promise)` keeps a delayed webhook alive after the response —
  verify it exists in the deployed runtime; fallback: the 20 s wait inside the request.
- Deploy JWT: `payment-webhook` with `--no-verify-jwt`; the others keep JWT checks.
- App: no `url_launcher` yet. Don't add it for the sandbox; A3's real browser comes with
  Cardcom (pin the version then).
- Reuse: `SupabaseOrderTracker.watch` for the "checking payment" state; counter
  `CounterController` for the ⏩ button; kitchen ticket chip style for `تجربة`.
