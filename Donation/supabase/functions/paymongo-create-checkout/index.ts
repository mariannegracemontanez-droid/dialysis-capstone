// Creates a PayMongo TEST-mode Checkout Session (GCash only) for a pending
// donation that was already created by create_donation_checkout().
//
// The amount, recipients and reference all come from the database row --
// the request only identifies the donation and proves ownership with the
// donor's client secret. Creating a session never marks anything paid;
// only the paymongo-webhook function does that, after verification.
//
// Deploy: supabase functions deploy paymongo-create-checkout

import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  basicAuth,
  buildReturnUrl,
  corsHeaders,
  donationSiteUrlFromEnv,
  json,
  PAYMONGO_API,
  requireTestSecretKey,
  validateCheckoutUrl,
} from "../_shared/paymongo.ts";

/**
 * Returns the donor-facing checkout JSON only if any checkout_url in it is a
 * genuine PayMongo checkout URL; otherwise a fail-closed error response.
 */
// deno-lint-ignore no-explicit-any
function checkoutResponse(data: any, error: unknown): Response {
  if (error || !data || typeof data !== "object") {
    console.error("get_donation_checkout failed");
    return json({ error: "Could not load checkout" }, 500);
  }
  if (data.checkout_url != null && validateCheckoutUrl(data.checkout_url) === null) {
    console.error("Refusing to return an untrusted checkout URL");
    return json({ error: "Checkout link is invalid" }, 502);
  }
  return json(data);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: { donation_id?: string; client_secret?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }
  const donationId = body.donation_id;
  const secret = body.client_secret;
  if (
    typeof donationId !== "string" || !donationId ||
    typeof secret !== "string" || !secret
  ) {
    return json({ error: "Missing donation" }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // 1. Environment gate: sandbox + PayMongo test explicitly enabled.
  const { data: settings, error: settingsError } = await supabase
    .from("donation_payment_settings")
    .select("environment, paymongo_test_enabled")
    .single();
  if (settingsError || settings?.environment !== "sandbox" || !settings?.paymongo_test_enabled) {
    return json({ error: "PayMongo test checkout is not enabled" }, 409);
  }

  let secretKey: string;
  try {
    secretKey = requireTestSecretKey();
  } catch (e) {
    console.error(String(e));
    return json({ error: "Payment provider is not configured" }, 500);
  }

  // Fail closed on a missing or unsafe return site (see parseDonationSiteUrl).
  const siteUrl = donationSiteUrlFromEnv();
  if (!siteUrl) {
    console.error("DONATION_SITE_URL is missing or invalid");
    return json({ error: "Donation site URL is not configured correctly" }, 500);
  }

  // 2. Ownership + current state, from the database.
  const { data: donation, error: ownError } = await supabase.rpc(
    "paymongo_get_owned_donation",
    { p_donation_id: donationId, p_client_secret: secret },
  );
  if (ownError || !donation) return json({ error: "Donation not found" }, 404);
  if (donation.payment_provider !== "paymongo" || donation.payment_environment !== "sandbox") {
    return json({ error: "Not a PayMongo sandbox donation" }, 409);
  }

  const current = () =>
    supabase.rpc("get_donation_checkout", {
      p_donation_id: donationId,
      p_client_secret: secret,
    });

  // A session already exists (double click / retry): reuse it, but only if
  // the stored URL is still a genuine PayMongo checkout URL.
  if (donation.checkout_url) {
    const { data, error } = await current();
    return checkoutResponse(data, error);
  }
  if (donation.payment_status !== "pending") {
    return json({ error: "Donation is no longer awaiting payment" }, 409);
  }

  // 3. Create the TEST checkout session.
  const response = await fetch(`${PAYMONGO_API}/checkout_sessions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      Authorization: basicAuth(secretKey),
    },
    body: JSON.stringify({
      data: {
        attributes: {
          line_items: [{
            name: `CureNurture donation ${donation.reference} (TEST)`,
            amount: donation.amount_centavos, // centavos
            currency: "PHP",
            quantity: 1,
          }],
          payment_method_types: ["gcash"],
          success_url: buildReturnUrl(siteUrl, "success", String(donation.reference)),
          cancel_url: buildReturnUrl(siteUrl, "cancel", String(donation.reference)),
          reference_number: donation.reference,
          description: "CureNurture sandbox donation — TEST MODE, no real money",
          send_email_receipt: false,
          show_line_items: true,
          metadata: { donation_id: donationId, environment: "sandbox" },
        },
      },
    }),
  });

  const created = await response.json().catch(() => null);
  if (!response.ok || typeof created?.data?.id !== "string" || !created.data.id) {
    console.error("PayMongo checkout_sessions error", response.status, JSON.stringify(created));
    return json({ error: "Could not create PayMongo checkout" }, 502);
  }

  const checkoutId: string = created.data.id;
  // Never store or return a URL that is not a genuine PayMongo checkout page.
  const checkoutUrl = validateCheckoutUrl(created.data.attributes?.checkout_url);
  if (checkoutUrl === null) {
    console.error("PayMongo returned an invalid checkout_url; session not saved", checkoutId);
    return json({ error: "Could not create PayMongo checkout" }, 502);
  }

  // 4. Save it (first session wins if two requests raced).
  const { error: attachError } = await supabase.rpc("paymongo_attach_checkout", {
    p_donation_id: donationId,
    p_checkout_id: checkoutId,
    p_checkout_url: checkoutUrl,
  });
  if (attachError) {
    console.error("attach failed", attachError.message);
    return json({ error: "Could not save checkout" }, 500);
  }

  // If another request won the race, this returns ITS (validated) session.
  const { data, error } = await current();
  return checkoutResponse(data, error);
});
