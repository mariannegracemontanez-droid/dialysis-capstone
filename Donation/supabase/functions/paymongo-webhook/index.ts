// Receives PayMongo webhook events (TEST mode only) and records verified
// payments. This is the ONLY path that can mark a PayMongo donation paid.
//
// Trust chain:
//   1. Paymongo-Signature verified with PAYMONGO_WEBHOOK_SECRET (test `te`
//      signature; any event signed for live mode is rejected).
//   2. The checkout session is re-fetched from PayMongo's API with the
//      secret key and must itself show a paid payment -- the event body is
//      never trusted on its own.
//   3. paymongo_record_payment() de-duplicates by event id, so repeated
//      deliveries are harmless, and refuses to touch non-sandbox rows.
//
// Deploy WITHOUT Supabase JWT verification (PayMongo cannot send one; the
// signature check above replaces it):
//   supabase functions deploy paymongo-webhook --no-verify-jwt

import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  basicAuth,
  json,
  PAYMONGO_API,
  requireTestSecretKey,
  verifyTestSignature,
} from "../_shared/paymongo.ts";

const PAID_EVENT = "checkout_session.payment.paid";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const webhookSecret = Deno.env.get("PAYMONGO_WEBHOOK_SECRET");
  if (!webhookSecret) {
    console.error("PAYMONGO_WEBHOOK_SECRET is not set");
    return json({ error: "Not configured" }, 500);
  }

  // Raw body: the signature is computed over the exact bytes received.
  const rawBody = await req.text();
  const valid = await verifyTestSignature(
    req.headers.get("paymongo-signature"),
    rawBody,
    webhookSecret,
  );
  if (!valid) return json({ error: "Invalid signature" }, 401);

  let event: any;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const eventId: string | undefined = event?.data?.id;
  const type: string | undefined = event?.data?.attributes?.type;
  const livemode: boolean | undefined = event?.data?.attributes?.livemode;
  const resource = event?.data?.attributes?.data;

  if (!eventId || !type) return json({ error: "Malformed event" }, 400);

  if (livemode !== false) {
    // Never applied in the sandbox. 200 so PayMongo stops retrying.
    return json({ received: true, ignored: "live event" });
  }

  if (type !== PAID_EVENT) {
    // Failures are not terminal for a checkout session (the donor can retry
    // on PayMongo's page); abandonment is handled by the donor's Cancel.
    return json({ received: true, ignored: type });
  }

  const checkoutId: unknown = resource?.id;
  if (typeof checkoutId !== "string" || !checkoutId) {
    return json({ error: "Missing checkout session id" }, 400);
  }

  // Server-side verification against PayMongo's API.
  let secretKey: string;
  try {
    secretKey = requireTestSecretKey();
  } catch (e) {
    console.error(String(e));
    return json({ error: "Not configured" }, 500);
  }

  const sessionResponse = await fetch(
    `${PAYMONGO_API}/checkout_sessions/${encodeURIComponent(checkoutId)}`,
    {
      headers: { Accept: "application/json", Authorization: basicAuth(secretKey) },
    },
  );
  const session = await sessionResponse.json().catch(() => null);
  if (!sessionResponse.ok || !session?.data) {
    console.error("Could not retrieve checkout session", sessionResponse.status);
    return json({ error: "Verification unavailable" }, 503); // PayMongo retries
  }
  // The verified session must be the one the event names; the payment is
  // then recorded against the donation that owns that checkout id only.
  if (session.data.id !== checkoutId) {
    console.error("Retrieved checkout session id does not match the event");
    return json({ error: "Checkout session mismatch" }, 400);
  }

  const attributes = session.data.attributes ?? {};
  if (attributes.livemode !== false) {
    return json({ received: true, ignored: "session is live mode" });
  }

  const payments: any[] = attributes.payments ?? [];
  const paid = payments.find((p) => p?.attributes?.status === "paid");
  if (!paid) {
    // Event arrived before the session reflects it: ask PayMongo to retry.
    return json({ error: "Payment not yet visible on session" }, 503);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const { data: result, error } = await supabase.rpc("paymongo_record_payment", {
    p_event_id: eventId,
    p_event_type: type,
    p_checkout_id: checkoutId,
    p_payment_id: paid.id ?? null,
    p_livemode: false,
  });
  if (error) {
    console.error("record_payment failed", error.message);
    return json({ error: "Database error" }, 500); // PayMongo retries
  }

  return json({ received: true, result });
});
