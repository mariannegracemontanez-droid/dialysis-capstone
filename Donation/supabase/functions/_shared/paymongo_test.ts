// Run with: deno test supabase/functions/_shared/paymongo_test.ts
import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  buildReturnUrl,
  hmacSha256Hex,
  parseDonationSiteUrl,
  parseSignatureHeader,
  timingSafeEqual,
  validateCheckoutUrl,
  verifyTestSignature,
} from "./paymongo.ts";

const SECRET = "whsk_test_secret";
const BODY = '{"data":{"id":"evt_1","attributes":{"type":"checkout_session.payment.paid","livemode":false}}}';

Deno.test("parses the signature header", () => {
  assertEquals(parseSignatureHeader("t=123,te=abc,li="), { t: "123", te: "abc", li: "" });
  assertEquals(parseSignatureHeader(null), { t: "", te: "", li: "" });
});

Deno.test("accepts a correctly signed test event", async () => {
  const te = await hmacSha256Hex(SECRET, `123.${BODY}`);
  assert(await verifyTestSignature(`t=123,te=${te},li=`, BODY, SECRET));
});

Deno.test("rejects a tampered body", async () => {
  const te = await hmacSha256Hex(SECRET, `123.${BODY}`);
  assertFalse(await verifyTestSignature(`t=123,te=${te},li=`, BODY + " ", SECRET));
});

Deno.test("rejects the wrong secret, missing parts and live signatures", async () => {
  const te = await hmacSha256Hex("other", `123.${BODY}`);
  assertFalse(await verifyTestSignature(`t=123,te=${te},li=`, BODY, SECRET));
  assertFalse(await verifyTestSignature(`te=${te}`, BODY, SECRET));
  const good = await hmacSha256Hex(SECRET, `123.${BODY}`);
  assertFalse(await verifyTestSignature(`t=123,te=,li=${good}`, BODY, SECRET));
  assertFalse(await verifyTestSignature(`t=123,te=${good},li=${good}`, BODY, SECRET));
});

Deno.test("timingSafeEqual", () => {
  assert(timingSafeEqual("abc", "abc"));
  assertFalse(timingSafeEqual("abc", "abd"));
  assertFalse(timingSafeEqual("abc", "ab"));
});

Deno.test("rejects a non-numeric signature timestamp", async () => {
  const te = await hmacSha256Hex(SECRET, `abc.${BODY}`);
  assertFalse(await verifyTestSignature(`t=abc,te=${te},li=`, BODY, SECRET));
});

Deno.test("validateCheckoutUrl accepts genuine PayMongo checkout URLs", () => {
  assertEquals(
    validateCheckoutUrl("https://checkout.paymongo.com/cs_abc123"),
    "https://checkout.paymongo.com/cs_abc123",
  );
  assertEquals(
    validateCheckoutUrl("https://checkout.paymongo.com/cs_abc123#Y2lkPWNz"),
    "https://checkout.paymongo.com/cs_abc123#Y2lkPWNz",
  );
  // Default port and host case normalise to the canonical URL.
  assertEquals(
    validateCheckoutUrl("https://CHECKOUT.PAYMONGO.COM:443/cs_1"),
    "https://checkout.paymongo.com/cs_1",
  );
});

Deno.test("validateCheckoutUrl rejects untrusted or malformed URLs", () => {
  for (
    const bad of [
      undefined,
      null,
      42,
      {},
      "",
      "not a url",
      "/cs_1",
      "//checkout.paymongo.com/cs_1",
      "http://checkout.paymongo.com/cs_1",
      "javascript:alert(1)",
      "data:text/html,hi",
      "ftp://checkout.paymongo.com/cs_1",
      "https://evil.example/cs_1",
      "https://paymongo.com/cs_1",
      "https://pay.paymongo.com/cs_1",
      "https://evil.checkout.paymongo.com/cs_1",
      "https://checkout.paymongo.com.evil.example/cs_1",
      "https://checkout-paymongo.com/cs_1",
      "https://user:pass@checkout.paymongo.com/cs_1",
      "https://user@checkout.paymongo.com/cs_1",
      "https://checkout.paymongo.com@evil.example/cs_1",
      "https://checkout.paymongo.com:8443/cs_1",
      "https://checkout.paymongo.com:80/cs_1",
      "https://checkout.paymongo.com\\@evil.example/",
      " https://checkout.paymongo.com/cs_1",
      "https://checkout.paymongo.com/cs_1\n",
      "https://checkout.paymongo.com/c s",
      "https://checkout.paymongo.com/" + "a".repeat(3000),
    ]
  ) {
    assertEquals(validateCheckoutUrl(bad), null, String(bad));
  }
});

Deno.test("parseDonationSiteUrl accepts https sites with an optional path", () => {
  assertEquals(parseDonationSiteUrl("https://donate.example.org/")?.href, "https://donate.example.org/");
  assertEquals(parseDonationSiteUrl("https://donate.example.org")?.href, "https://donate.example.org/");
  assertEquals(parseDonationSiteUrl("https://example.org/donate/")?.href, "https://example.org/donate/");
  assertEquals(parseDonationSiteUrl("  https://example.org/  ")?.href, "https://example.org/");
});

Deno.test("parseDonationSiteUrl allows local http only when explicitly enabled", () => {
  for (const local of ["http://localhost:5000/", "http://127.0.0.1:8080/", "http://[::1]:3000/", "http://localhost/"]) {
    assertEquals(parseDonationSiteUrl(local), null, local);
    assertEquals(parseDonationSiteUrl(local, true)?.href, local);
  }
  assertEquals(parseDonationSiteUrl("https://localhost:5000/"), null);
  assertEquals(parseDonationSiteUrl("https://localhost:5000/", true)?.href, "https://localhost:5000/");
  // The local flag never permits http for a non-local host.
  assertEquals(parseDonationSiteUrl("http://donate.example.org/", true), null);
  assertEquals(parseDonationSiteUrl("http://localhost.evil.example/", true), null);
});

Deno.test("parseDonationSiteUrl rejects unsafe or malformed configuration", () => {
  for (
    const bad of [
      undefined,
      null,
      "",
      "   ",
      "donate.example.org",
      "/donate",
      "http://donate.example.org/",
      "ftp://donate.example.org/",
      "javascript:alert(1)",
      "https://user:pass@donate.example.org/",
      "https://user@donate.example.org/",
      "https://donate.example.org:8443/",
      "https://donate.example.org:443x/",
      "https://donate.example.org/?next=https://evil.example",
      "https://donate.example.org/?",
      "https://donate.example.org/#/home",
      "https://donate.example.org\\@evil.example/",
      "https://donate.example.org/a b",
    ]
  ) {
    assertEquals(parseDonationSiteUrl(bad), null, String(bad));
    assertEquals(parseDonationSiteUrl(bad, true), null, `${bad} (local allowed)`);
  }
});

Deno.test("buildReturnUrl adds only encoded paymongo/ref parameters", () => {
  const site = parseDonationSiteUrl("https://example.org/donate/")!;
  assertEquals(
    buildReturnUrl(site, "success", "CN-SBX-ABC123"),
    "https://example.org/donate/?paymongo=success&ref=CN-SBX-ABC123",
  );
  const tricky = buildReturnUrl(site, "cancel", "x&next=https://evil.example#frag");
  const parsed = new URL(tricky);
  assertEquals(parsed.origin, "https://example.org");
  assertEquals(parsed.pathname, "/donate/");
  assertEquals(parsed.hash, "");
  assertEquals([...parsed.searchParams.keys()], ["paymongo", "ref"]);
  assertEquals(parsed.searchParams.get("ref"), "x&next=https://evil.example#frag");
  assertEquals(parsed.searchParams.get("paymongo"), "cancel");
});
