// E2: the provider says "something was paid". The body is only a hint: the adapter asks
// the provider's API for the real charge, and mark_paid_card re-checks amount, currency,
// and order state. Answers 200 for anything settled (duplicates too) so the provider
// stops retrying; 5xx only when a retry could help.
import type { PaymentProvider, VerifiedCharge } from "../_shared/payment_provider.ts";
import type { MarkPaidCardArgs } from "../_shared/rest.ts";

export interface WebhookDeps {
  provider: PaymentProvider | null;
  markPaidCard(args: MarkPaidCardArgs): Promise<string>;
}

const answer = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

export async function handleWebhook(
  request: Request,
  deps: WebhookDeps,
): Promise<Response> {
  if (request.method !== "POST") return answer(405, { error: "method" });
  if (!deps.provider) return answer(503, { error: "card_unavailable" });

  let charge: VerifiedCharge | null;
  try {
    charge = await deps.provider.verifyWebhook(request);
  } catch (error) {
    console.error("verifyWebhook failed", error);
    return answer(502, { error: "provider_error" });
  }
  if (!charge) return answer(400, { error: "unrecognised" });
  if (!charge.approved) return answer(200, { result: "not_approved" });

  let result: string;
  try {
    result = await deps.markPaidCard({
      orderId: charge.orderId,
      provider: deps.provider.name,
      txnId: charge.txnId,
      amountMinorUnits: charge.amountMinorUnits,
      currency: charge.currency,
      raw: charge.raw,
    });
  } catch (error) {
    console.error("mark_paid_card failed", error);
    return answer(500, { error: "database" });
  }
  if (result !== "paid" && result !== "duplicate") {
    // Money moved but didn't settle an order: it's on the refund list (or, for an
    // unknown order, only here). Loud, so it's noticed in the function logs.
    console.error("card charge needs attention", result, charge.orderId, charge.txnId);
  }
  return answer(200, { result });
}
