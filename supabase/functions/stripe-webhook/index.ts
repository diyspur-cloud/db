import { createClient } from "@supabase/supabase-js";
import Stripe from "stripe";

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`missing_required_env:${name}`);
  return value;
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }
  const signature = req.headers.get("stripe-signature");
  const secret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  if (!secret) {
    return new Response("webhook not configured", { status: 503 });
  }
  if (!signature) {
    return new Response("invalid signature", { status: 400 });
  }
  let stripe: Stripe;
  try {
    stripe = new Stripe(requiredEnv("STRIPE_SECRET_KEY"));
  } catch {
    return new Response("webhook not configured", { status: 503 });
  }
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      await req.text(),
      signature,
      secret,
    );
  } catch {
    return new Response("invalid signature", { status: 400 });
  }
  try {
    const supabase = createClient(
      requiredEnv("SUPABASE_URL"),
      requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
      {
        auth: { persistSession: false, autoRefreshToken: false },
      },
    );
    const asRecord = (value: unknown): Record<string, unknown> | null =>
      value !== null && typeof value === "object" && !Array.isArray(value)
        ? value as Record<string, unknown>
        : null;
    const object = asRecord(event.data.object) ?? {};
    const customerValue = object.customer;
    const customerObject = asRecord(customerValue);
    const customerId = typeof customerValue === "string"
      ? customerValue
      : typeof customerObject?.id === "string"
      ? customerObject.id
      : null;
    const metadata = asRecord(object.metadata);
    const rawUserId = metadata?.supabase_user_id ??
      object.client_reference_id ?? null;
    const metadataUserId =
      typeof rawUserId === "string" && UUID_RE.test(rawUserId)
        ? rawUserId
        : null;

    if (
      event.type === "checkout.session.completed" && customerId &&
      metadataUserId
    ) {
      const { error } = await supabase.rpc("link_stripe_customer", {
        p_customer_id: customerId,
        p_user: metadataUserId,
      });
      if (error) throw error;
    }

    let planId: string | null = null;
    let subscriptionId: string | null = null;
    let status: string | null = null;
    let start: string | null = null;
    let end: string | null = null;
    let cancelAtPeriodEnd = false;
    if (event.type.startsWith("customer.subscription.")) {
      subscriptionId = typeof object.id === "string" ? object.id : null;
      const items = asRecord(object.items);
      const itemData = Array.isArray(items?.data) ? items.data : [];
      const firstItem = asRecord(itemData[0]);
      const price = asRecord(firstItem?.price);
      const priceId = price?.id;
      if (typeof priceId !== "string") {
        throw new Error("subscription_price_missing");
      }
      const { data: plan, error: planError } = await supabase.from(
        "membership_plans",
      )
        .select("id").eq("stripe_price_id", priceId).maybeSingle();
      if (planError || !plan) throw new Error("subscription_plan_not_mapped");
      planId = plan.id;
      const statusMap: Record<string, string> = {
        trialing: "trialing",
        active: "active",
        past_due: "past_due",
        canceled: "canceled",
        paused: "paused",
        incomplete: "incomplete",
        unpaid: "past_due",
        incomplete_expired: "canceled",
      };
      status = typeof object.status === "string"
        ? statusMap[object.status] ?? null
        : null;
      if (!status) throw new Error("unsupported_subscription_status");
      const periodStart = object.current_period_start ??
        firstItem?.current_period_start;
      const periodEnd = object.current_period_end ??
        firstItem?.current_period_end;
      start = typeof periodStart === "number" && Number.isFinite(periodStart)
        ? new Date(periodStart * 1000).toISOString()
        : null;
      end = typeof periodEnd === "number" && Number.isFinite(periodEnd)
        ? new Date(periodEnd * 1000).toISOString()
        : null;
      cancelAtPeriodEnd = object.cancel_at_period_end === true;
    }

    const { data, error } = await supabase.rpc(
      "apply_stripe_subscription_event",
      {
        p_event_id: event.id,
        p_event_type: event.type,
        p_customer_id: customerId,
        p_metadata_user: metadataUserId,
        p_subscription_id: subscriptionId,
        p_plan_id: planId,
        p_status: status,
        p_period_start: start,
        p_period_end: end,
        p_cancel_at_period_end: cancelAtPeriodEnd,
        p_payload: event as unknown as Record<string, unknown>,
      },
    );
    if (error) throw error;
    return new Response(String(data ?? "ok"), { status: 200 });
  } catch (error) {
    console.error(
      "stripe-webhook: event processing failed",
      error instanceof Error ? error.message : "unknown",
    );
    // Retorna 5xx para que o Stripe repita; o RPC grava o evento junto com a assinatura.
    return new Response("event processing failed", { status: 500 });
  }
});
