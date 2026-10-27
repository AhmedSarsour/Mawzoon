import { providerFromEnv } from "../_shared/payment_provider.ts";
import { readOwnOrder, type RestConfig } from "../_shared/rest.ts";
import { handleCreatePayment } from "./handler.ts";

const env = Deno.env;
const rest: RestConfig = {
  url: env.get("SUPABASE_URL")!,
  anonKey: env.get("SUPABASE_ANON_KEY")!,
  // Not used here: this function only reads as the guest.
  serviceKey: "",
};

Deno.serve((request) =>
  handleCreatePayment(request, {
    readOwnOrder: (jwt, id) => readOwnOrder(rest, jwt, id),
    provider: providerFromEnv(env),
    now: () => new Date(),
    returnUrl: env.get("PAYMENT_RETURN_URL") ?? "",
    webhookUrl: `${rest.url}/functions/v1/payment-webhook`,
  })
);
