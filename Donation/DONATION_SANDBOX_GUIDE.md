# CureNurture GCash Donation Sandbox

How the sandbox donation flow works, how to set it up, and how to demonstrate it.

> **DEMO MODE: NO REAL MONEY IS TRANSFERRED.** Every donation created by this flow is a sandbox
> transaction. A "successful" payment is either produced by the internal demo simulator or by
> PayMongo's **test mode**. In both cases no money moves and no dialysis center receives funds.

---

## 1. Architecture

| Part | What it is | Role in donations |
|---|---|---|
| `Donation/` | Flutter web donor site | Collects amount, donation option and GCash; shows the preview, checkout and result |
| `super_admin_app/` | Flutter superadmin dashboard | **Donations → Donation Transactions (GCash Checkout)** lists every checkout with its allocation breakdown |
| `admin_panel/` | Flutter center-admin app | Unchanged except that a single-center donation's allocation row is not counted twice |
| Supabase Postgres | Tables, RLS, SECURITY DEFINER functions | **All donation decisions are made here** |
| Supabase Edge Functions | `paymongo-create-checkout`, `paymongo-webhook` | Only used when PayMongo test mode is switched on |

### Before this change
The donation page inserted rows into `donations` directly from the browser with `status = 'verified'`.
There was no payment step, and the random center and Donate-to-All split were both computed in the
browser. Anyone with the public anon key could create a "verified" donation.

### After this change
```
Donor browser                       Postgres (server-side)
─────────────                       ──────────────────────
choose option + amount  ──rpc──▶  create_donation_checkout()
                                    • validates amount (min/max) and mode
                                    • checks eligibility (center not 'closed')
                                    • random center: picked with random() on the server
                                    • Donate to All: integer-centavo split, remainder to first centers
                                    • writes donations (pending) + donation_allocations snapshot
review page  ◀──── recipients, amounts, reference (read back from the DB)
simulate / pay ──rpc──▶  simulate_donation_payment()      (sandbox + simulator only)
               ──fn───▶  paymongo-create-checkout → PayMongo TEST checkout
                         PayMongo ──webhook──▶ paymongo-webhook → paymongo_record_payment()
result page  ◀──── status read back from the DB
```

---

## 2. Files

**New**
- `Donation/supabase_migration_donation_sandbox.sql` adds the schema, functions, RLS and guards.
- `Donation/supabase_preflight_donation_sandbox.sql` is a read-only report of your current RLS policies, grants, columns and prerequisites.
- `Donation/supabase_tests_donation_sandbox.sql` is the database test suite. It runs inside a transaction and rolls back.
- `Donation/supabase/functions/_shared/paymongo.ts` holds the signature verification and key guard.
- `Donation/supabase/functions/_shared/paymongo_test.ts` contains the Deno tests for signature verification.
- `Donation/supabase/functions/paymongo-create-checkout/index.ts`
- `Donation/supabase/functions/paymongo-webhook/index.ts`
- `Donation/lib/config/payment_config.dart` holds `kBankTransferEnabled` and the demo banner text.
- `Donation/lib/services/donation_checkout_service.dart` contains the RPC calls, the centavo maths and resume-after-refresh.
- `Donation/lib/services/public_donation_service.dart` is the landing page's read of the public donation feed and totals.
- `Donation/test/public_donation_service_test.dart`
- `Donation/lib/pages/checkout_page.dart` is the review page, the simulator and PayMongo buttons, and the result.
- `Donation/lib/widgets/demo_banner.dart`
- `Donation/test/donation_checkout_test.dart`
- `super_admin_app/lib/models/payment_transaction.dart`
- `super_admin_app/lib/widgets/payment_transactions_section.dart`
- `super_admin_app/test/payment_transactions_test.dart`

**Modified**
- `Donation/lib/pages/donation_page.dart` now hides Bank Transfer, shows the server-side preview, submits through the RPC and offers to resume a pending checkout.
- `Donation/lib/widgets/donation_steps.dart` and `Donation/lib/pages/landing_page.dart` have updated copy. Step 3 is "Review & pay", and the landing page no longer mentions bank transfer.
- `Donation/pubspec.yaml` adds `url_launcher` and `shared_preferences`.
- `super_admin_app/lib/services/donation_service.dart`:
  - It adds `fetchPaymentTransactions()`.
  - The existing donation history excludes sandbox rows.
  - Allocation rows are only listed for split donations.
- `super_admin_app/lib/pages/donations_page.dart` adds the new section.
- `admin_panel/lib/services/dashboard_service.dart` stops a single-center allocation from being counted twice.

`payment_page.dart` (old receipt upload, not used anywhere) and the bank/GCash QR assets are untouched.

---

## 3. Database changes

These are all in `supabase_migration_donation_sandbox.sql`. The migration only adds things and is safe to re-run.

**`donation_payment_settings`** is a new single-row table that holds the server-side mode:

| Column | Default | Meaning |
|---|---|---|
| `environment` | `sandbox` | `sandbox` or `production` |
| `simulator_enabled` | `true` | Internal demo simulator |
| `paymongo_test_enabled` | `false` | PayMongo test checkout |
| `min_amount_centavos` / `max_amount_centavos` | 2000 / 10,000,000 | ₱20.00 to ₱100,000.00 |

A constraint stops the simulator or PayMongo test mode from being on while `environment = 'production'`.

**`donations`** (the parent transaction) gets these new nullable columns: `amount_centavos`, `currency`,
`payment_provider`, `payment_environment`, `payment_status`, `status_reason`, `reference_code`,
`provider_checkout_id`, `provider_checkout_url`, `provider_payment_id`, `payment_confirmed_at`,
`updated_at`, `idempotency_key` (unique) and `client_secret_hash`.

**`donation_allocations`** (child rows, one per recipient center in all three modes) gets these new columns:
`amount_centavos`, `clinic_name_snapshot`, `allocation_status`, `provider_transfer_ref`,
`sort_order` and `updated_at`.

**Status design**

| `payment_status` | `donations.status` | Allocation status | Counted as money? |
|---|---|---|---|
| `pending` / `processing` | `pending` | `awaiting_payment` | No |
| `simulated_paid` (sandbox simulator) | `pending` | `simulated` | **No** |
| `paid` in sandbox (PayMongo test) | `pending` | `simulated` | **No** |
| `paid` in production (future) | `verified` | `pending_payout` | Yes |
| `failed` / `cancelled` | `rejected` | `void` | No |

`paid_out` can only be set together with a provider transfer reference. Nothing in this project sets it,
because no real payout integration exists.

**Integrity rules enforced by the database**
- `donations_sandbox_never_verified`: a sandbox row can never have `status = 'verified'`. Every money total
  in all three apps counts only `verified`, so sandbox donations are excluded everywhere automatically.
- Deferred trigger `donation_allocations_total_check`: a donation's allocations must add up exactly to `amount_centavos`.
- `amount = amount_centavos / 100` on both tables.
- Guard triggers refuse **every** direct INSERT, UPDATE, DELETE or TRUNCATE on `donations` and
  `donation_allocations` that comes through the Supabase API. That covers `anon`, `authenticated`, any
  custom role the API gateway can switch into, and a superadmin signed in to a dashboard. It holds
  whatever the RLS policies or grants are. No app writes these tables directly any more. The server
  functions, the SQL Editor and `service_role` are not affected.
- `payment_provider_events` stores each webhook event id once, so duplicate deliveries are ignored.

**RLS and privilege changes**
- **Dropped:** every INSERT, UPDATE or DELETE policy on `donations` and `donation_allocations` for
  anon, authenticated or public. On the live project that means `"Allow update donations"` (UPDATE to
  public, `true`) and `"Allow donation allocation inserts"`. SELECT policies are kept, including
  `"Allow read donations"`, so the landing page and dashboards read as before. Policies covering ALL
  commands are kept for their reads and reported as NOTICEs; their writes are blocked by the guard.
- **Revoked:** INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES and TRIGGER on all five donation tables
  for anon and authenticated. SELECT stays granted.
- **Self-check:** the migration ends by checking that no write policy, write grant or disabled guard
  remains. If anything is left open, it aborts and nothing is applied.
- **Added:** anyone can read `donation_payment_settings`, and superadmins can read `payment_provider_events`.
- **Donor privacy and account roles:** see section 11.
- **Function privileges:**
  - Donors (anon/authenticated) can call only `create_donation_checkout`, `get_donation_checkout`,
    `cancel_donation_checkout`, `simulate_donation_payment`, `donation_eligible_centers` and `donation_equal_split`.
  - The `paymongo_*` functions are `service_role` only.
  - The internal helpers have no public access.
- **`approve_donation` / `reject_donation`** now refuse workflow donations. A superadmin can't settle a
  payment by hand.

**Eligibility.** The existing rule is unchanged: a center is eligible if `clinics.status` is not `'closed'`.
The `clinics` table has no payout or bank-account columns, so there are no account details to verify.
Hiding Bank Transfer did not change who is eligible.

**Anonymous donors.** The browser generates a random secret for each donation and the database stores
only its SHA-256 hash. The secret is required to view, simulate or cancel that donation, so one donor
can't touch another donor's checkout.

---

## 4. Setup

1. **Preflight (read-only).** Open the Supabase dashboard, then **SQL Editor → New query**. Paste
   `supabase_preflight_donation_sandbox.sql` and click **Run**. It changes nothing.
   - Every `prerequisite` row should say OK.
   - Review the `rls` and `policy` rows. They show your current donation security; the guard triggers
     protect writes either way.
2. **Migration.** Run `supabase_migration_donation_sandbox.sql` the same way. It's safe to run again.
3. **Tests.** Run `supabase_tests_donation_sandbox.sql`. The result row should read
   `ALL DONATION SANDBOX TESTS PASSED - all test data rolled back`. Any failure stops with an error that
   names the check. It needs at least 2 centers that aren't closed, and it leaves no data behind.
4. Start the donor site with `cd Donation`, `flutter pub get`, then `flutter run -d chrome`.
5. Start the superadmin dashboard with `cd super_admin_app` and `flutter run -d chrome`.

The simulator works right after step 2. No Edge Function or external account is needed.

Useful SQL:
```sql
-- current mode
select * from donation_payment_settings;
-- simulator only (default)
update donation_payment_settings set simulator_enabled = true, paymongo_test_enabled = false;
-- PayMongo test checkout (after section 5)
update donation_payment_settings set simulator_enabled = false, paymongo_test_enabled = true;
```

---

## 5. PayMongo test mode (optional)

The demo doesn't need this. Do it only when you have a PayMongo account. **Never** put keys in Flutter
code or in `.env` files that ship to the browser.

1. In the PayMongo dashboard, open **Developers → API Keys** and copy the **test** secret key (`sk_test_...`).
2. Install the Supabase CLI and link the project: `supabase login`, then `supabase link --project-ref <ref>`.
   Run the CLI from the `Donation/` folder, which contains `supabase/functions`.
3. Set the secrets:
   ```bash
   supabase secrets set PAYMONGO_SECRET_KEY=sk_test_xxx
   supabase secrets set DONATION_SITE_URL=https://<where-the-donation-site-is-hosted>/
   ```
   The functions refuse any key that doesn't start with `sk_test_`.

   `DONATION_SITE_URL` is where PayMongo sends the donor back after checkout. It must use HTTPS
   and have the form `https://host[/path]`, for example `https://donate.example.org/` or
   `https://example.org/donate/`. It must **not** contain:
   - a username or password (`https://user:pass@host/`)
   - an explicit port (`https://host:8443/`)
   - a query string (`?...`)
   - a fragment (`#...`)

   If the value is missing or invalid, `paymongo-create-checkout` refuses to start the checkout
   ("Donation site URL is not configured correctly") and nothing is sent to PayMongo.

   **Local development only:** plain HTTP is accepted only when **both** of these are set:
   ```bash
   supabase secrets set DONATION_SITE_URL=http://localhost:<port>/
   supabase secrets set DONATION_SITE_ALLOW_LOCAL_HTTP=true
   ```
   The supported loopback hosts are `localhost`, `127.0.0.1` and `[::1]`. Even with the flag set,
   HTTP is refused for any other host. Never enable `DONATION_SITE_ALLOW_LOCAL_HTTP` for a shared
   or production deployment. Unset it before any shared deployment
   (`supabase secrets unset DONATION_SITE_ALLOW_LOCAL_HTTP`) and set `DONATION_SITE_URL` back to
   the HTTPS address.
4. Deploy:
   ```bash
   supabase functions deploy paymongo-create-checkout
   supabase functions deploy paymongo-webhook --no-verify-jwt
   ```
   The webhook needs `--no-verify-jwt` because PayMongo can't send a Supabase token. The PayMongo
   signature check takes its place.
5. In the PayMongo dashboard (test mode), create a webhook for
   `https://<project-ref>.supabase.co/functions/v1/paymongo-webhook` subscribed to
   `checkout_session.payment.paid`. Copy the webhook's secret key, then run:
   ```bash
   supabase secrets set PAYMONGO_WEBHOOK_SECRET=whsk_xxx
   ```
6. Run `update donation_payment_settings set simulator_enabled = false, paymongo_test_enabled = true;`
7. Make a donation. On PayMongo's test page, choose GCash, then **Authorize** for success or **Fail**.

**How a payment is trusted**
1. The webhook's signature is checked as HMAC-SHA256 of `t.rawBody` against the test (`te`) signature.
   Live (`li`) events are rejected.
2. The checkout session is fetched again from PayMongo's API and must show a `paid` payment.
3. The event id is recorded once.

Neither the redirect back to the site nor the session creation marks anything paid.

**Verify on your first test run.** PayMongo's pages are inconsistent about whether the signed string
includes the timestamp, and the checkout-paid payload isn't fully documented. If valid events return 401,
check the signature format in `_shared/paymongo.ts`. If they return 503, check that
`attributes.payments[].attributes.status` is the field that shows `paid`.

---

## 6. Running the demo (step by step)

Have the donor site and the superadmin dashboard open side by side.

1. **Show the banner.** The donation page shows **"DEMO MODE — NO REAL MONEY TRANSFERRED"**, and
   GCash is the only payment method.
2. **Donate to All.** Choose *Donate Anonymously*, enter `1000`, and pick *Distribute Donation Equally
   Among All Centers*. The preview lists every eligible center and its share. With 3 centers the
   shares are ₱333.34, ₱333.33 and ₱333.33. Point out that the leftover centavo goes to the first
   center so the total is exactly ₱1,000.00.
3. Click **Review & Continue to GCash**. The checkout page shows the reference (`CN-SBX-...`) and the
   recipients and amounts *as saved by the server*. Note the "Internal demo simulator (not PayMongo)" label.
4. Click **Simulate successful payment**. The result says the payment was simulated and no money was
   transferred, and each allocation shows *Simulated allocation — no funds transferred*.
5. **Random Center.** Start a new donation with *Randomly Assign*. The page says the server will choose.
   On the checkout page, the chosen center appears. Refresh the browser, click **Resume checkout**, and
   show that the same center is still assigned. Then click **Simulate failed payment**.
6. **Specific Center.** Pick a center, ₱500, then **Simulate cancelled payment**.
7. **Superadmin.** Open **Donations → Donation Transactions (GCash Checkout)**.
   - Every row has a **SANDBOX** badge.
   - *Collected funds* stays at **₱0.00**. Sandbox successes appear only under
     *Sandbox completed (not real money)*, and the failed/cancelled ones under *Failed or cancelled*.
   - Click **View allocation** on the Donate-to-All row to show the per-center breakdown and
     "(matches donation total)".
   - Try the filters for mode, status, environment, center and date.
   - Point out that the existing *Total Donations* card and the center histories did not change, and
     that nowhere on the page can a status be changed.
8. *(Optional security point.)* Show `supabase_tests_donation_sandbox.sql` and its output. It shows
   that anon and logged-in users can't insert a donation, can't mark one paid, and can't call the
   provider functions.

---

## 7. Tests

| Suite | Command | Result |
|---|---|---|
| Donor app: new checkout tests (amount parsing, centavo split incl. remainders, error mapping, idempotency keys, checkout page success/failure/cancel/PayMongo/320px layout) | `cd Donation && flutter test test/donation_checkout_test.dart` | **Passed** |
| Donor app: existing input + responsive tests | `flutter test test/donation_input_test.dart test/responsive_layout_test.dart` | **Passed** (86 total with the above) |
| Donor app: `design_preview_test.dart` (goldens), `widget_test.dart` (default counter template) | `flutter test` | **Fail, same as before this change** (verified on the unmodified code) |
| Superadmin: all tests incl. new `payment_transactions_test.dart` (summary excludes sandbox/failed, filters, allocation dialog, read-only) | `cd super_admin_app && flutter test` | **157 passed** |
| Database: modes, validation, idempotency, eligibility changes, simulator, environment isolation, webhook dedupe, sum constraint, RLS/authorization | Supabase SQL Editor: `supabase_tests_donation_sandbox.sql` | **Passed on a local Postgres 15 copy** of the schema built from the repo migrations, in three setups: permissive legacy policies, RLS off, and the live project's reported policies (`Allow read/update donations`, `amount numeric not null`, a custom API role). Also passed when upgrading from the previous version of the migration. Run it again on your project after the migration |
| Edge Function shared helpers: webhook signature verification, checkout URL validation, `DONATION_SITE_URL` validation, return-URL building | `deno test --no-lock supabase/functions/_shared/paymongo_test.ts` (Deno isn't installed on the dev machine, so it was run in Docker: `docker run --rm -v "${PWD}:/app:ro" -w /app denoland/deno:latest deno test --no-lock supabase/functions/_shared/paymongo_test.ts`) | **12 passed.** This covers only the shared helpers in `_shared/paymongo.ts`. The Edge Function request handlers (`paymongo-create-checkout`, `paymongo-webhook`) have been type-checked but not run, and no PayMongo checkout or webhook has been tested end to end |

---

## 8. Limitations and approvals still needed

- **No real money movement and no real payouts.** Allocations record the *intended* distribution.
  Real transfers to several centers would need a provider arrangement for split payments or payouts,
  plus verified center payout accounts. Neither exists today; `clinics` has no account fields.
- **Production is disabled.** With `environment = 'production'`, `create_donation_checkout` refuses all
  donations because there's no live payment integration. Going live needs live PayMongo approval,
  live keys, and a review of this flow. The functions also currently refuse any non-test key.
- **PayMongo test mode hasn't been run end to end** (no keys yet). See the verification note in section 5.
- **Registered donors.** The donor's email comes from their Supabase account, and the name comes from
  the form, then their profile, then their email.
- **The `donations` RLS policies aren't in this repository.** The migration lists any ALL-command
  policies on `donations` as NOTICEs. Review them so that only superadmins hold one.
- **Abandoned checkouts** stay `pending` until the donor cancels them. A scheduled clean-up isn't included.

---

## 9. Restoring Bank Transfer later

1. In `Donation/lib/config/payment_config.dart`, set `kBankTransferEnabled = true`. The original
   two-option layout comes back unchanged.
2. In `donation_page.dart`, remove the "Only GCash is available" check in `_handleDonate`.
3. On the server, `create_donation_checkout` currently records `payment_method = 'GCASH'`. Bank transfers
   also need a confirmation path, such as a `manual_bank` provider whose confirmation is a superadmin RPC
   that checks a receipt. `approve_donation` deliberately refuses workflow donations. Decide this
   before turning Bank Transfer back on.

No bank data, assets or tables were removed, so there's nothing to restore in the database.

---

## 10. Keeping sandbox data distinct from production

- Every row created by this flow has `payment_environment` set and a `CN-SBX-` reference.
- The database itself stops a sandbox row from ever becoming `verified`, so sandbox amounts can't
  reach any total.
- The superadmin shows sandbox rows only in their own section, each with a SANDBOX badge, and never in
  *Collected funds* or the existing donation histories.
- The donor site shows the DEMO banner whenever the server setting is `sandbox`.
- To clear demo data before a real launch:
  ```sql
  delete from donations where payment_environment = 'sandbox';  -- allocations and audit rows cascade
  ```
  Look at what this matches before running it.

---

## 11. Donor privacy and account roles

These are migration sections 13 and 14. Both apply to every donation, not only sandbox ones.

### Who can read donations

| Reader | Before | After |
|---|---|---|
| Public visitor (landing page) | Every donation row, including donor **emails** (`Allow read donations`, SELECT to public, `true`) | No direct table access. `public_donation_feed()` returns display name ("Anonymous" for anonymous gifts), date and amount of verified donations; `public_donation_totals()` returns the count and sum |
| Patient or donor (signed in) | Every row, through the public policy | Nothing directly |
| Patient who picked a clinic | Also that clinic's rows: the old center-admin policies checked only `profiles.clinic_id` | Nothing |
| Center admin (`role = 'admin'`) | Every row, through the public policy | Their own center's donations, plus Donate-to-All donations their center has a share of |
| Superadmin (`profiles.role` or `app_metadata.role` = `superadmin`, the same rule as the Super Admin login) | Every row, only through the public policy (there was no superadmin policy) | Every row, through its own policy |

The landing page shows exactly what it showed before: the five most recent verified donations and the
totals. It now refreshes every 20 seconds instead of listening in realtime, because realtime would need
public read access to the whole table. The superadmin and center-admin dashboards need no code change.

### Who can change roles

Every superadmin and center-admin check reads `profiles.role`, and the apps write `profiles` from the
browser. A trigger (`profiles_guard_privileges`) now enforces these rules for any write through the API by
someone who is **not** a superadmin, whatever the `profiles` RLS policies say:

- They can create only their **own** profile, and never with role `admin` or `superadmin` (any case or spacing).
- They can edit only their **own** profile, and never its `role` or `id`.
- An `admin` account can't change its own `clinic_id`, `status` or `is_active`. That would move it to
  another center or reactivate it.
- Deleting a profile is refused.

These still work unchanged:
- donor signup (upserts its own profile with no role);
- patient signup (role `patient`, status `pending`);
- patients editing their own name and choosing a clinic;
- the Super Admin app creating, editing, deactivating and reactivating admin accounts;
- server-side auth triggers, the SQL Editor and `service_role`.

### Deployment order

1. Run `supabase_preflight_donation_sandbox.sql`. Every BLOCKER must be fixed first. The FIXED BY MIGRATION rows list what will change.
2. Run `supabase_migration_donation_sandbox.sql`. It ends with two "Self-check passed" notices; if any check fails, nothing is applied.
3. Run `supabase_tests_donation_sandbox.sql`. Expect `ALL DONATION SANDBOX TESTS PASSED - all test data rolled back`.
4. **Deploy the new Donation web build at the same time.** The old build reads the `donations` table
   directly (its recent-donations list and totals would go empty) and inserts donations directly (now refused).
5. Run the preflight again. No FIXED BY MIGRATION, REVIEW or BLOCKER rows should remain.

### Still outside this change

- Donor **names** remain public on the landing page, as before. To show initials or "A donor" instead,
  change one line in `public_donation_feed()`.
- A patient can still change their own profile `status` (for example from `pending`). If your patient
  approval depends on `profiles.status`, decide whether to restrict that as well; the role guard leaves
  patient fields alone so the mobile app keeps working.
- Other `profiles` columns (email, phone) are protected only by your existing `profiles` RLS. The
  preflight lists those policies.
