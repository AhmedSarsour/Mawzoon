// The card company, behind one small interface (adapter), so Cardcom / Grow / PayPlus
// can be swapped without touching the money rules in the handlers.

/** What create-payment asks the provider for: a hosted card page for one order. */
export interface HostedPageRequest {
  orderId: string;
  orderNumber: number;
  /** Agorot, from the order row — never from the app. */
  amountMinorUnits: number;
  currency: "ILS";
  /** The page must stop taking money before the order expires. */
  expiresAt: Date;
  returnUrl: string;
  webhookUrl: string;
}

/** A charge as the provider's own API reports it, not as a webhook body claims. */
export interface VerifiedCharge {
  orderId: string;
  txnId: string;
  /** Agorot. Adapters convert the provider's unit (often shekels with decimals). */
  amountMinorUnits: number;
  currency: string;
  approved: boolean;
  raw: unknown;
}

export interface PaymentProvider {
  /** Short name stored in payments.provider, e.g. "cardcom". */
  readonly name: string;
  createHostedPage(request: HostedPageRequest): Promise<{ url: string }>;
  /**
   * Reads only a reference out of the webhook, then asks the provider's API what
   * really happened. null = not a webhook this provider recognises.
   */
  verifyWebhook(request: Request): Promise<VerifiedCharge | null>;
}

/**
 * The configured provider, or null while card payment isn't set up.
 * Cardcom's adapter lands with its sandbox account (Module 12 plan, E).
 */
export function providerFromEnv(
  env: { get(key: string): string | undefined },
): PaymentProvider | null {
  const name = env.get("PAYMENT_PROVIDER") ?? "";
  switch (name) {
    case "":
      return null;
    default:
      console.error(`PAYMENT_PROVIDER "${name}" has no adapter yet`);
      return null;
  }
}
