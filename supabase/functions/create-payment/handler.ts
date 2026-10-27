// E1: the guest's app asks for a card page for its unpaid order. The amount comes from
// the order row (read with the guest's own token), never from the request.
import type { PaymentProvider } from "../_shared/payment_provider.ts";
import type { OrderRow } from "../_shared/rest.ts";

export interface CreatePaymentDeps {
  /** The order as the caller's token sees it (RLS); null if not theirs or missing. */
  readOwnOrder(userJwt: string, orderId: string): Promise<OrderRow | null>;
  provider: PaymentProvider | null;
  now(): Date;
  returnUrl: string;
  webhookUrl: string;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Errors answer {error: key}, like place_order's keys.
const answer = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

export async function handleCreatePayment(
  request: Request,
  deps: CreatePaymentDeps,
): Promise<Response> {
  if (request.method !== "POST") return answer(405, { error: "method" });
  const jwt = request.headers.get("Authorization")?.match(/^Bearer (.+)$/)?.[1];
  if (!jwt) return answer(401, { error: "not_signed_in" });

  const body = await request.json().catch(() => null) as { order_id?: unknown } | null;
  const orderId = body?.order_id;
  if (typeof orderId !== "string" || !UUID.test(orderId)) {
    return answer(400, { error: "invalid_payload" });
  }

  const order = await deps.readOwnOrder(jwt, orderId);
  if (!order) return answer(404, { error: "not_found" });
  if (order.status !== "AWAITING_PAYMENT") {
    return answer(409, { error: "not_awaiting_payment", status: order.status });
  }
  if (order.payment_method !== "card") return answer(409, { error: "not_card_order" });
  const dueAt = order.payment_due_at ? new Date(order.payment_due_at) : null;
  if (!dueAt || dueAt <= deps.now()) return answer(409, { error: "order_expired" });
  if (!deps.provider) return answer(503, { error: "card_unavailable" });

  try {
    const page = await deps.provider.createHostedPage({
      orderId: order.id,
      orderNumber: order.order_number,
      amountMinorUnits: order.total_price_minor_units,
      currency: "ILS",
      expiresAt: dueAt,
      returnUrl: deps.returnUrl,
      webhookUrl: deps.webhookUrl,
    });
    return answer(200, { url: page.url });
  } catch (error) {
    console.error("createHostedPage failed", error);
    return answer(502, { error: "provider_error" });
  }
}
