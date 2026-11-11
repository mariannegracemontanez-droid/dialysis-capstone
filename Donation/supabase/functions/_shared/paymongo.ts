// Shared helpers for the PayMongo TEST-mode Edge Functions.
//
// Secrets (set with `supabase secrets set`, never in Flutter code):
//   PAYMONGO_SECRET_KEY      sk_test_...  (live keys are refused)
//   PAYMONGO_WEBHOOK_SECRET  whsk_...     (returned when the webhook is created)
//   DONATION_SITE_URL        where PayMongo sends the donor back afterwards.
//                            Must be https://host[/path], with no credentials,
//                            port, query or fragment (see parseDonationSiteUrl).
//   DONATION_SITE_ALLOW_LOCAL_HTTP  optional; "true" ONLY for local development
//                            with DONATION_SITE_URL=http://localhost:<port>/
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by the runtime.

export const PAYMONGO_API = "https://api.paymongo.com/v1";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** Returns the PayMongo secret key, refusing anything but a TEST key. */
export function requireTestSecretKey(): string {
  const key = Deno.env.get("PAYMONGO_SECRET_KEY") ?? "";
  if (!key.startsWith("sk_test_")) {
    throw new Error(
      "PAYMONGO_SECRET_KEY must be a TEST key (sk_test_...). Live keys are refused in the sandbox.",
    );
  }
  return key;
}

export function basicAuth(secretKey: string): string {
  // PayMongo uses HTTP Basic auth with the secret key as the username.
  return "Basic " + btoa(`${secretKey}:`);
}

export interface SignatureParts {
  t: string;
  te: string;
  li: string;
}

/** Parses `Paymongo-Signature: t=...,te=...,li=...`. */
export function parseSignatureHeader(header: string | null): SignatureParts {
  const parts: Record<string, string> = {};
  for (const piece of (header ?? "").split(",")) {
    const i = piece.indexOf("=");
    if (i > 0) parts[piece.slice(0, i).trim()] = piece.slice(i + 1).trim();
  }
  return { t: parts.t ?? "", te: parts.te ?? "", li: parts.li ?? "" };
}

const encoder = new TextEncoder();

export async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(message));
  return Array.from(new Uint8Array(signature))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * Verifies a TEST-mode webhook as documented by PayMongo ("Securing a
 * webhook"): HMAC-SHA256 over `${t}.${rawBody}` with the webhook secret,
 * compared with the `te` (test) signature. Events carrying a live (`li`)
 * signature are rejected: this sandbox never accepts live events.
 */
export async function verifyTestSignature(
  header: string | null,
  rawBody: string,
  webhookSecret: string,
): Promise<boolean> {
  const { t, te, li } = parseSignatureHeader(header);
  // `t` is a Unix timestamp; anything else is a malformed header.
  if (!/^\d+$/.test(t) || !te || li) return false;
  const expected = await hmacSha256Hex(webhookSecret, `${t}.${rawBody}`);
  return timingSafeEqual(expected, te.toLowerCase());
}

// ------------------------------------------------------------ URL checks

/** The only host PayMongo checkout pages are served from. */
export const PAYMONGO_CHECKOUT_HOST = "checkout.paymongo.com";

// Whitespace, control characters and backslashes never appear in a genuine
// checkout URL; URL parsers silently strip or reinterpret them.
// deno-lint-ignore no-control-regex
const UNSAFE_URL_CHARS = /[\s\u0000-\u001f\u007f\\]/;

/**
 * Returns the normalised checkout URL when [raw] is an https URL on exactly
 * checkout.paymongo.com (no other subdomain), with no credentials and no
 * explicit port; otherwise null. The path is not restricted.
 */
export function validateCheckoutUrl(raw: unknown): string | null {
  if (typeof raw !== "string" || raw.length === 0 || raw.length > 2048) return null;
  if (UNSAFE_URL_CHARS.test(raw)) return null;
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (url.protocol !== "https:") return null;
  if (url.hostname !== PAYMONGO_CHECKOUT_HOST) return null;
  if (url.username || url.password) return null;
  // `port` is "" for the default 443; any explicit other port is refused.
  if (url.port !== "") return null;
  return url.href;
}

const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1", "[::1]"]);

/**
 * Parses DONATION_SITE_URL. Returns null (fail closed) unless it is:
 *   - https://host[/path] with no explicit port, or
 *   - http://localhost|127.0.0.1|[::1][:port][/path], and only when
 *     [allowLocalHttp] is true (local development);
 * with no credentials, query string or fragment. A path is kept so the site
 * may live under a sub-path. No domain is hard-coded: the deployer sets it.
 */
export function parseDonationSiteUrl(
  raw: string | undefined | null,
  allowLocalHttp = false,
): URL | null {
  if (typeof raw !== "string") return null;
  const value = raw.trim();
  if (!value || value.length > 2048 || UNSAFE_URL_CHARS.test(value)) return null;
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return null;
  }
  if (url.username || url.password) return null;
  if (url.search || url.hash || value.includes("?") || value.includes("#")) return null;
  if (!url.hostname) return null;

  if (url.protocol === "https:") {
    if (LOCAL_HOSTS.has(url.hostname)) {
      // A local address is only a valid return site during local development.
      if (!allowLocalHttp) return null;
    } else if (url.port !== "") {
      return null;
    }
  } else if (url.protocol === "http:") {
    if (!allowLocalHttp || !LOCAL_HOSTS.has(url.hostname)) return null;
  } else {
    return null;
  }
  return url;
}

/** Reads DONATION_SITE_URL / DONATION_SITE_ALLOW_LOCAL_HTTP from the environment. */
export function donationSiteUrlFromEnv(): URL | null {
  return parseDonationSiteUrl(
    Deno.env.get("DONATION_SITE_URL"),
    Deno.env.get("DONATION_SITE_ALLOW_LOCAL_HTTP") === "true",
  );
}

/**
 * PayMongo's success/cancel URL: the configured site with only
 * `paymongo=<outcome>` and `ref=<reference>` added (both URL-encoded).
 */
export function buildReturnUrl(
  site: URL,
  outcome: "success" | "cancel",
  reference: string,
): string {
  const url = new URL(site.href);
  url.search = "";
  url.hash = "";
  url.searchParams.set("paymongo", outcome);
  url.searchParams.set("ref", reference);
  return url.href;
}
