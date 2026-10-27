// The two database calls the payment functions make, over PostgREST with plain fetch.
// The guest's read uses the guest's own token (RLS proves the order is theirs); only
// the webhook's mark_paid_card uses the service key.

export interface OrderRow {
  id: string;
  order_number: number;
  status: string;
  payment_method: string;
  total_price_minor_units: number;
  payment_due_at: string | null;
}

export interface RestConfig {
  url: string;
  anonKey: string;
  serviceKey: string;
  fetch?: typeof fetch;
}

export class DatabaseError extends Error {
  constructor(readonly status: number, readonly body: string) {
    super(`database answered ${status}: ${body}`);
  }
}

/** The order, if the caller's token may see it; null otherwise. */
export async function readOwnOrder(
  config: RestConfig,
  userJwt: string,
  orderId: string,
): Promise<OrderRow | null> {
  const doFetch = config.fetch ?? fetch;
  const columns =
    "id,order_number,status,payment_method,total_price_minor_units,payment_due_at";
  const response = await doFetch(
    `${config.url}/rest/v1/orders?id=eq.${encodeURIComponent(orderId)}&select=${columns}`,
    { headers: { apikey: config.anonKey, Authorization: `Bearer ${userJwt}` } },
  );
  if (!response.ok) {
    // A bad or expired token reads as "not yours", like a missing row.
    if (response.status === 401) return null;
    throw new DatabaseError(response.status, await response.text());
  }
  const rows = (await response.json()) as OrderRow[];
  return rows[0] ?? null;
}

export interface MarkPaidCardArgs {
  orderId: string;
  provider: string;
  txnId: string;
  amountMinorUnits: number;
  currency: string;
  raw: unknown;
}

/**
 * public.mark_paid_card. Answers its `result`, or "unknown_order" when the order
 * id doesn't exist. Any other failure throws, so the webhook answers 500 and the
 * provider retries.
 */
export async function markPaidCard(
  config: RestConfig,
  args: MarkPaidCardArgs,
): Promise<string> {
  const doFetch = config.fetch ?? fetch;
  const response = await doFetch(`${config.url}/rest/v1/rpc/mark_paid_card`, {
    method: "POST",
    headers: {
      apikey: config.serviceKey,
      Authorization: `Bearer ${config.serviceKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      p_order_id: args.orderId,
      p_provider: args.provider,
      p_txn_id: args.txnId,
      p_amount_minor_units: args.amountMinorUnits,
      p_currency: args.currency,
      p_raw: args.raw,
    }),
  });
  const text = await response.text();
  if (response.ok) return (JSON.parse(text) as { result: string }).result;
  const error = safeJson(text) as { message?: string } | null;
  if (error?.message === "not_found") return "unknown_order";
  if (error?.message === "invalid_payload") return "invalid_payload";
  throw new DatabaseError(response.status, text);
}

function safeJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}
