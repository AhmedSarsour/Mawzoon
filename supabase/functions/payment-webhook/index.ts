// Deploy with JWT checking off: the provider calls this, not a signed-in user.
//   supabase functions deploy payment-webhook --no-verify-jwt
import { providerFromEnv } from "../_shared/payment_provider.ts";
import { markPaidCard, type RestConfig } from "../_shared/rest.ts";
import { handleWebhook } from "./handler.ts";

const env = Deno.env;
const rest: RestConfig = {
  url: env.get("SUPABASE_URL")!,
  anonKey: env.get("SUPABASE_ANON_KEY")!,
  serviceKey: env.get("SUPABASE_SERVICE_ROLE_KEY")!,
};

Deno.serve((request) =>
  handleWebhook(request, {
    provider: providerFromEnv(env),
    markPaidCard: (args) => markPaidCard(rest, args),
  })
);
