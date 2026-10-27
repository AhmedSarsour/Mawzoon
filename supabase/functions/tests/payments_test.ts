// Module 12 E: create-payment and payment-webhook against a fake provider and fake fetch.
// Run: deno test supabase/functions/tests/
import { handleCreatePayment } from "../create-payment/handler.ts";
import { handleWebhook } from "../payment-webhook/handler.ts";
import type {
  HostedPageRequest,
  PaymentProvider,
  VerifiedCharge,
} from "../_shared/payment_provider.ts";
import { providerFromEnv } from "../_shared/payment_provider.ts";
import { markPaidCard, type MarkPaidCardArgs, type OrderRow, readOwnOrder } from "../_shared/rest.ts";

// No test library: one equality helper keeps this dependency-free.
function eq(actual: unknown, expected: unknown, what = "") {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${what}\n  expected ${e}\n  got      ${a}`);
}

const ORDER_ID = "6f9c1d2e-0000-4000-8000-000000000001";
const NOW = new Date("2026-10-22T20:00:00Z");

const order = (over: Partial<OrderRow> = {}): OrderRow => ({
  id: ORDER_ID,
  order_number: 204,
  status: "AWAITING_PAYMENT",
  payment_method: "card",
  total_price_minor_units: 4900,
  payment_due_at: "2026-10-22T20:15:00Z",
  ...over,
});

class FakeProvider implements PaymentProvider {
  readonly name = "fake";
  pages: HostedPageRequest[] = [];
  charge: VerifiedCharge | null = null;
  webhookBodies: string[] = [];
  async createHostedPage(request: HostedPageRequest) {
    this.pages.push(request);
    return { url: `https://pay.example/${request.orderId}` };
  }
  async verifyWebhook(request: Request) {
    // Like a real adapter: reads the body, then trusts only what "the API" says.
    this.webhookBodies.push(await request.text());
    return this.charge;
  }
}

const post = (body: unknown, jwt: string | null = "guest-jwt") =>
  new Request("https://fn.example/create-payment", {
    method: "POST",
    headers: jwt ? { Authorization: `Bearer ${jwt}` } : {},
    body: JSON.stringify(body),
  });

function createDeps(row: OrderRow | null, provider: PaymentProvider | null = new FakeProvider()) {
  const reads: [string, string][] = [];
  return {
    reads,
    deps: {
      readOwnOrder: async (jwt: string, id: string) => {
        reads.push([jwt, id]);
        return row;
      },
      provider,
      now: () => NOW,
      returnUrl: "mawzoon://paid",
      webhookUrl: "https://fn.example/payment-webhook",
    },
  };
}

async function body(response: Response) {
  return [response.status, await response.json()];
}

// ── create-payment ─────────────────────────────────────────────────────────

Deno.test("create-payment charges the order row's total, not the request's", async () => {
  const provider = new FakeProvider();
  const { deps, reads } = createDeps(order(), provider);
  const response = await handleCreatePayment(
    post({ order_id: ORDER_ID, amount_minor_units: 1, total_price_minor_units: 1 }),
    deps,
  );
  eq(await body(response), [200, { url: `https://pay.example/${ORDER_ID}` }]);
  eq(provider.pages[0].amountMinorUnits, 4900, "amount from the row");
  eq(provider.pages[0].currency, "ILS");
  eq(provider.pages[0].expiresAt.toISOString(), "2026-10-22T20:15:00.000Z", "page dies with the order");
  eq(reads, [["guest-jwt", ORDER_ID]], "read with the guest's own token");
});

Deno.test("create-payment refuses what it must", async () => {
  const cases: [Request, OrderRow | null, PaymentProvider | null, number, string][] = [
    [post({ order_id: ORDER_ID }, null), order(), new FakeProvider(), 401, "not_signed_in"],
    [post({ order_id: "1; drop table" }), order(), new FakeProvider(), 400, "invalid_payload"],
    [post({}), order(), new FakeProvider(), 400, "invalid_payload"],
    [post({ order_id: ORDER_ID }), null, new FakeProvider(), 404, "not_found"],
    [post({ order_id: ORDER_ID }), order({ status: "PENDING" }), new FakeProvider(), 409, "not_awaiting_payment"],
    [post({ order_id: ORDER_ID }), order({ payment_method: "counter" }), new FakeProvider(), 409, "not_card_order"],
    [post({ order_id: ORDER_ID }), order({ payment_due_at: "2026-10-22T20:00:00Z" }), new FakeProvider(), 409, "order_expired"],
    [post({ order_id: ORDER_ID }), order({ payment_due_at: null }), new FakeProvider(), 409, "order_expired"],
    [post({ order_id: ORDER_ID }), order(), null, 503, "card_unavailable"],
  ];
  for (const [request, row, provider, status, error] of cases) {
    const { deps } = createDeps(row, provider);
    const [gotStatus, got] = await body(await handleCreatePayment(request, deps));
    eq([gotStatus, got.error], [status, error], error);
  }
});

Deno.test("create-payment: provider down is 502, not a crash", async () => {
  const provider = new FakeProvider();
  provider.createHostedPage = () => Promise.reject(new Error("timeout"));
  const { deps } = createDeps(order(), provider);
  eq(await body(await handleCreatePayment(post({ order_id: ORDER_ID }), deps)), [502, { error: "provider_error" }]);
});

// ── payment-webhook ────────────────────────────────────────────────────────

const hook = (text: string) =>
  new Request("https://fn.example/payment-webhook", { method: "POST", body: text });

function webhookDeps(provider: PaymentProvider | null, results: string[] | Error) {
  const calls: MarkPaidCardArgs[] = [];
  return {
    calls,
    deps: {
      provider,
      markPaidCard: async (args: MarkPaidCardArgs) => {
        calls.push(args);
        if (results instanceof Error) throw results;
        return results.shift()!;
      },
    },
  };
}

const charge = (over: Partial<VerifiedCharge> = {}): VerifiedCharge => ({
  orderId: ORDER_ID,
  txnId: "txn-1",
  amountMinorUnits: 4900,
  currency: "ILS",
  approved: true,
  raw: { from: "provider api" },
  ...over,
});

Deno.test("webhook pays with the provider's figures, not the body's", async () => {
  const provider = new FakeProvider();
  provider.charge = charge();
  const { deps, calls } = webhookDeps(provider, ["paid"]);
  const forged = JSON.stringify({ order_id: "someone-else", amount: 1, status: "approved" });
  eq(await body(await handleWebhook(hook(forged), deps)), [200, { result: "paid" }]);
  eq(calls, [{
    orderId: ORDER_ID,
    provider: "fake",
    txnId: "txn-1",
    amountMinorUnits: 4900,
    currency: "ILS",
    raw: { from: "provider api" },
  }]);
  eq(provider.webhookBodies, [forged], "body only reaches the adapter as a hint");
});

Deno.test("webhook: forged or unknown reference changes nothing", async () => {
  const provider = new FakeProvider(); // the API knows no such charge
  const { deps, calls } = webhookDeps(provider, []);
  eq(await body(await handleWebhook(hook("{}"), deps)), [400, { error: "unrecognised" }]);
  eq(calls.length, 0);
});

Deno.test("webhook: declined charge is acknowledged, nothing paid", async () => {
  const provider = new FakeProvider();
  provider.charge = charge({ approved: false });
  const { deps, calls } = webhookDeps(provider, []);
  eq(await body(await handleWebhook(hook("{}"), deps)), [200, { result: "not_approved" }]);
  eq(calls.length, 0);
});

Deno.test("webhook: duplicates and refunds answer 200 so the provider stops", async () => {
  for (const result of ["duplicate", "already_paid", "order_cancelled", "amount_mismatch", "unknown_order"]) {
    const provider = new FakeProvider();
    provider.charge = charge();
    const { deps } = webhookDeps(provider, [result]);
    eq(await body(await handleWebhook(hook("{}"), deps)), [200, { result }], result);
  }
});

Deno.test("webhook: retryable failures are 5xx", async () => {
  const provider = new FakeProvider();
  provider.charge = charge();
  const db = webhookDeps(provider, new Error("db down"));
  eq((await handleWebhook(hook("{}"), db.deps)).status, 500, "database down");

  const flaky = new FakeProvider();
  flaky.verifyWebhook = () => Promise.reject(new Error("provider api down"));
  eq((await handleWebhook(hook("{}"), webhookDeps(flaky, []).deps)).status, 502, "provider down");

  eq((await handleWebhook(hook("{}"), webhookDeps(null, []).deps)).status, 503, "not configured");
  eq((await handleWebhook(new Request("https://x", { method: "GET" }), webhookDeps(provider, []).deps)).status, 405);
});

// ── REST calls: which key goes where ───────────────────────────────────────

function fakeFetch(status: number, responseBody: string) {
  const seen: { url: string; init: RequestInit }[] = [];
  const f = ((url: string, init: RequestInit = {}) => {
    seen.push({ url, init });
    return Promise.resolve(new Response(responseBody, { status }));
  }) as unknown as typeof fetch;
  return { seen, f };
}

Deno.test("readOwnOrder reads as the guest, never with the service key", async () => {
  const { seen, f } = fakeFetch(200, JSON.stringify([order()]));
  const row = await readOwnOrder(
    { url: "https://db", anonKey: "anon", serviceKey: "SERVICE", fetch: f },
    "guest-jwt",
    ORDER_ID,
  );
  eq(row?.total_price_minor_units, 4900);
  const headers = seen[0].init.headers as Record<string, string>;
  eq([headers.apikey, headers.Authorization], ["anon", "Bearer guest-jwt"]);
  if (JSON.stringify(seen).includes("SERVICE")) throw new Error("service key leaked into a guest read");
});

Deno.test("readOwnOrder: not visible or bad token is null", async () => {
  const cfg = (f: typeof fetch) => ({ url: "https://db", anonKey: "a", serviceKey: "", fetch: f });
  eq(await readOwnOrder(cfg(fakeFetch(200, "[]").f), "jwt", ORDER_ID), null);
  eq(await readOwnOrder(cfg(fakeFetch(401, "{}").f), "jwt", ORDER_ID), null);
});

Deno.test("markPaidCard sends the args and maps the answers", async () => {
  const args = { orderId: ORDER_ID, provider: "fake", txnId: "t", amountMinorUnits: 4900, currency: "ILS", raw: {} };
  const ok = fakeFetch(200, JSON.stringify({ result: "paid" }));
  eq(await markPaidCard({ url: "https://db", anonKey: "", serviceKey: "S", fetch: ok.f }, args), "paid");
  eq(JSON.parse(ok.seen[0].init.body as string), {
    p_order_id: ORDER_ID,
    p_provider: "fake",
    p_txn_id: "t",
    p_amount_minor_units: 4900,
    p_currency: "ILS",
    p_raw: {},
  });
  const missing = fakeFetch(400, JSON.stringify({ code: "P0001", message: "not_found" }));
  eq(await markPaidCard({ url: "https://db", anonKey: "", serviceKey: "S", fetch: missing.f }, args), "unknown_order");
  const down = fakeFetch(503, "upstream");
  let threw = false;
  try {
    await markPaidCard({ url: "https://db", anonKey: "", serviceKey: "S", fetch: down.f }, args);
  } catch {
    threw = true;
  }
  eq(threw, true, "a database outage must throw (webhook answers 500, provider retries)");
});

Deno.test("no provider configured → card stays off", () => {
  eq(providerFromEnv({ get: () => undefined }), null);
  eq(providerFromEnv({ get: () => "cardcom" }), null);
});
