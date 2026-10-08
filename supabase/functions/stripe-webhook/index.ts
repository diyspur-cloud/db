import { serve } from "https://deno.land/std@0.200.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@14?target=denonext";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2024-06-20",
});

serve(async (req) => {
  const sig = req.headers.get("stripe-signature")!;
  const raw = await req.text();
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      raw,
      sig,
      Deno.env.get("STRIPE_WEBHOOK_SECRET")!,
    );
  } catch (_e) {
    return new Response("invalid signature", { status: 400 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { error: insErr } = await supabase.from("payment_events").insert({
    provider: "stripe",
    event_id: event.id,
    event_type: event.type,
    payload: event as unknown as Record<string, unknown>,
    processed_at: new Date().toISOString(),
  });
  if (insErr) return new Response("duplicate", { status: 200 });

  const obj = event.data.object as Record<string, any>;
  if (event.type.startsWith("customer.subscription.")) {
    const { data: plan } = await supabase
      .from("membership_plans")
      .select("id")
      .eq("stripe_price_id", obj.items?.data?.[0]?.price?.id)
      .maybeSingle();

    await supabase.from("user_subscriptions").upsert(
      {
        provider_subscription_id: obj.id,
        provider_customer_id: obj.customer,
        plan_id: plan?.id,
        status: obj.status,
        current_period_start: new Date(obj.current_period_start * 1000).toISOString(),
        current_period_end: new Date(obj.current_period_end * 1000).toISOString(),
        cancel_at_period_end: obj.cancel_at_period_end,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "provider_subscription_id" },
    );
  }

  return new Response("ok", { status: 200 });
});
