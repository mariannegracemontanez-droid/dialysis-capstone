# CureNurture — Design Lead Handoff (Admin Panel, Super Admin, Donation Website)

You receive the **same, current CureNurture source code** the project owner runs, plus a
private encrypted data package. With both, your machine runs the same three applications
with the same 23 dialysis centres, accounts, permissions, donation history and workflows.

**In scope:** `admin_panel/`, `super_admin_app/`, `Donation/` (and the shared package
`packages/curenurture_notice/` used by the Admin Panel and Super Admin).
**Out of scope:** `mobile-app/` — present in the repository but not part of this handoff.
Do not change it. (Optional: hide it from your working copy, see §16.)

What GitHub does **not** carry: your `.env` files, the database contents, any passwords,
and the original uploaded files (medical documents, receipts, profile photos). Those are
either created on your machine or delivered separately, as described below.

---

## 0. Documents you should not follow

These files are in the repository but are **not** setup instructions for this handoff:

| Document | Why not to follow it |
|---|---|
| Older copies of the root `README.md` / `docs/README.md` | They described folders that do not exist (`mobile/`, `admin-dashboard/`, `superadmin-dashboard/`, `donation-drive/`), an HTML donation site and a hosted "Supabase account" |
| `QUICK_REFERENCE.md`, `IMPLEMENTATION_SUMMARY.md` | Historical feature notes about an earlier Admin Panel; may not match the current code |
| `Donation/DONATION_SANDBOX_GUIDE.md` **sections 4 and 5** | Live Supabase operations: SQL in the hosted project's SQL Editor, `supabase link`, `supabase secrets set`, `supabase functions deploy`. Locally, the database changes are already in `supabase/migrations/` and PayMongo stays off. (The rest of that file is useful background on how simulated donations work.) |
| Anything about `mobile-app/` | Out of scope for this handoff |

Follow only this guide.

## 1. Architecture

| Part | What it is | Talks to |
|---|---|---|
| Admin Panel (`admin_panel/`) | Flutter web app for each dialysis centre's admin | Local Supabase API |
| Super Admin (`super_admin_app/`) | Flutter web app for system oversight | Local Supabase API |
| Donation Website (`Donation/`) | Flutter web app for donors; payments are **simulated** | Local Supabase API |
| Local Supabase (`supabase/`) | Postgres, Auth, REST, Storage in Docker, started by the Supabase CLI | — |

Everything runs on **your** laptop (`127.0.0.1`). Nothing connects to the live project.

## 2. Repository layout (relevant parts)

```
supabase/                      config.toml, migrations/ (7 files, in order), seed.sql (empty by design)
tools/handoff/                 import_handoff_data.ps1, create_dev_credentials.ps1,
                               verify_handoff.sql, export_handoff_data.ps1 (owner only), handoff_gpg.ps1
admin_panel/ super_admin_app/ Donation/     the three apps (+ .env.example templates)
packages/curenurture_notice/   shared Flutter package (Admin Panel + Super Admin)
docs/DESIGN_LEAD_HANDOFF.md    this guide
```

Migration sequence (applied automatically by `supabase start` / `supabase db reset`):

| # | File | Purpose |
|---|---|---|
| 1 | `20261110000001_baseline_public_schema.sql` | Original CureNurture schema: tables, functions, policies, triggers, realtime |
| 2 | `20261110000002_donation_sandbox.sql` | Server-side donation checkout + simulator; payment settings = sandbox |
| 3 | `20261110000003_donation_eligibility_v3.sql` | Centre eligibility (superseded by #6, kept for history) |
| 4 | `20261110000004_donation_permissions_v4.sql` | Donation permissions (active-admin rule, scoped logs) |
| 5 | `20261110000005_center_admin_views_v5.sql` | Privacy-safe views the Admin Panel reads |
| 6 | `20261110000006_donation_eligibility_v6.sql` | Eligibility: every centre except `closed`, with an active admin |
| 7 | `20261110000007_storage_buckets_and_policies.sql` | Private buckets `medical_docs`, `patient_profiles`, `donation_receipts` + access rules |

## 3. Tools: versions and installation (Windows)

### 3.1 Versions

**Recommended = the exact versions tested** with this project on the project owner's Windows
machine. Newer versions may work but have **not** been tested with this project and are not
guaranteed to be compatible.

| Tool | Minimum required | Tested (recommended) | Newer versions |
|---|---|---|---|
| Git for Windows | none stated by the project | 2.56.0 (includes GnuPG 2.4.9, `C:\Program Files\Git\usr\bin\gpg.exe`) | not tested |
| Flutter (stable) | Dart ≥ 3.10.8 (Admin Panel) and ≥ 3.11.1 (Super Admin, Donation), from each app's `pubspec.yaml` | 3.47.6 (Dart 3.13) | not tested |
| WSL | 2.1.5 or later (Docker Desktop requirement) | WSL 2 backend | — |
| Docker Desktop | Docker's own requirements (see 3.4) | Docker Engine 29.9.2 | not tested |
| Supabase CLI | none stated by the project | 3.0.0 | not tested |
| Browser | Microsoft Edge or Google Chrome | Edge | — |
| Editor | — | VS Code with the Flutter and Dart extensions | — |

Install the tools in the order below. Use **Windows PowerShell**.

### 3.2 Git for Windows

Download and run the installer from the official page: <https://git-scm.com/install/windows>.
Git for Windows also provides GnuPG, which decrypts the data package (§7).

```powershell
git --version
```

### 3.3 WSL 2 (needed by Docker Desktop)

Official guide: <https://learn.microsoft.com/en-us/windows/wsl/install>. Open PowerShell **as
administrator** (right-click → "Run as administrator"), run the command, then **restart** Windows:

```powershell
wsl --install
```

Check afterwards (if WSL was already installed, the official guide explains the alternatives):

```powershell
wsl --version
wsl.exe --list --verbose
```

### 3.4 Docker Desktop (WSL 2 backend)

Official guide: <https://docs.docker.com/desktop/setup/install/windows-install/>. Its WSL 2
requirements: Windows 11 version 23H2 (build 22631) or later (or the Windows 10 editions listed
there), WSL 2.1.5 or later, hardware virtualization enabled in BIOS/UEFI, and 8 GB RAM.
Install it with the WSL 2 backend, start Docker Desktop, and keep it **running** whenever you
use the project.

```powershell
docker version
```

Licensing: Docker Desktop is licensed under the Docker Subscription Service Agreement; check
whether its terms apply to you: <https://docs.docker.com/subscription/desktop-license/>.

### 3.5 Flutter (web)

Official guides:
- Install with VS Code (Flutter's recommended method): <https://docs.flutter.dev/install/with-vs-code>
- Manual install: <https://docs.flutter.dev/install/manual>; add Flutter to PATH:
  <https://docs.flutter.dev/install/add-to-path>
- Web setup (needs Edge or Chrome): <https://docs.flutter.dev/platform-integration/web/setup>
- To match the **tested** version exactly, download Flutter **3.47.6** for Windows from the SDK
  archive (<https://docs.flutter.dev/install/archive>, Stable channel → Windows) and follow the
  manual install. The VS Code method installs the newest stable release, which has not been
  tested with this project.

Close and reopen PowerShell after installing, then check:

```powershell
flutter --version
flutter doctor
flutter devices
```

`flutter doctor` needs a ✓ for Flutter; Android/Xcode warnings can be ignored (web only).
`flutter devices` must list **Edge (web)** or **Chrome (web)**.

### 3.6 Supabase CLI (via Scoop)

Official guide: <https://supabase.com/docs/guides/local-development/cli/getting-started>
(Windows method: Scoop). First install Scoop (<https://github.com/ScoopInstaller/Scoop>) from a
**regular, non-administrator** PowerShell:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
```

Then install the Supabase CLI:

```powershell
scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
scoop install supabase
```

Close and reopen PowerShell, then check (the scripts in `tools\handoff\` call `supabase` by name,
so it must work from any folder):

```powershell
supabase --version
```

Scoop installs the current Supabase CLI release, which may be newer than the tested 3.0.0.

### 3.7 Ports

Ports used on your machine: API **54321**, database **54322**, Studio **54323**, mail
**54324**. (A Windows PostgreSQL service on 5432, if you have one, is not affected.)

## 4. Clone

```powershell
git clone https://github.com/mariannegracemontanez-droid/dialysis-capstone.git
cd dialysis-capstone
git checkout -b design-lead-work      # your working branch (see §17)
```

## 5. Start your local Supabase (schema only)

```powershell
supabase start          # first run downloads images, then applies migrations 1-7
supabase status         # shows API URL and the local anon key
```

## 6. Environment variables

The apps read exactly two values: `SUPABASE_URL` and `SUPABASE_ANON_KEY`.

```powershell
copy Donation\.env.example            Donation\.env
copy admin_panel\.env.example         admin_panel\.env
copy super_admin_app\assets\.env.example super_admin_app\assets\.env
copy super_admin_app\.env.example     super_admin_app\.env     # must exist; may stay as-is
```

In the three files that contain `SUPABASE_ANON_KEY=`, paste the **anon key** from
`supabase status` (yours, local). Keep `SUPABASE_URL=http://127.0.0.1:54321`.
Never put the live project's URL or keys in these files. `.env` files are git-ignored.

Optional (Donation, developers only): `--dart-define=CURENURTURE_SIMULATOR_TEST_CONTROLS=true`
shows "simulate failed/cancelled payment" buttons on checkout.

## 7. Import the project data (centres, accounts, records)

You receive `curenurture-handoff-<date>.zip.gpg` **privately** (never via a public link)
and the passphrase **through a different channel**. Store the file outside the repository
or in `handoff-data\` (git-ignored).

```powershell
supabase db reset        # fresh database (only needed if you imported before)
powershell -ExecutionPolicy Bypass -File tools\handoff\import_handoff_data.ps1 -Package <path>\curenurture-handoff-<date>.zip.gpg
```

The script asks for the passphrase (masked), decrypts in a private temporary folder,
checks every file against its manifest, loads everything in one transaction, verifies
row counts and all foreign keys, and deletes the decrypted copy. On any error it rolls
back completely. It refuses to run on a database that already has centres.

The package contains **no passwords, tokens or sessions**, and no synthetic test data.

It also carries two private files that are deliberately **not** in Git: the Donation
payment QR images (`gcash_qr.jpg`, `bank_qr.jpg`). The import saves them to
`handoff-data\private-assets\` (git-ignored). They contain real payment-account details:
do not copy them into the app, commit them, or include them in any build or screenshot
you share. The Donation app does not need them to run.

## 8. Storage

Migration 7 creates the three **private** buckets and their rules (no anonymous access):

| Bucket | Read | Write |
|---|---|---|
| `medical_docs` (`<patient id>/<file>`) | the patient, the active admin of that patient's centre, superadmins | the patient, own folder |
| `patient_profiles` (`patients/<user id>_<time>.jpg`) | owner, own-centre admin, superadmins | owner |
| `donation_receipts` | superadmins | — |

**Original uploaded files are not available.** Their records exist (e.g. medical-document
entries), but the files themselves were never in the backup, so opening them shows an
error/empty preview. This is expected; do not upload real patient documents.

## 9. Centres

All 23 original centres (names, addresses, coordinates, hours, requirements, capacity,
shifts, house rules, statuses, contact numbers) arrive with the data package — not with
GitHub. Verification is in §15.

## 10. Your development logins

```powershell
powershell -ExecutionPolicy Bypass -File tools\handoff\create_dev_credentials.ps1
```

Sets **new random local-only passwords** for every superadmin, every active centre admin
(each still linked to its real centre) and one donor, and writes them to
`handoff-data\dev_credentials.LOCAL-ONLY.txt` (owner-only, git-ignored, never printed).
These are not anyone's real passwords and work only on your machine. Run it again any
time to issue new ones.

## 11-13. Run the apps

Use a separate terminal for each.

```powershell
cd admin_panel;     flutter pub get; flutter run -d edge --web-hostname 127.0.0.1 --web-port 5181
cd super_admin_app; flutter pub get; flutter run -d edge --web-hostname 127.0.0.1 --web-port 5182
cd Donation;        flutter pub get; flutter run -d edge --web-hostname 127.0.0.1 --web-port 5180
```

URLs (from the commands above): Admin Panel <http://127.0.0.1:5181>, Super Admin
<http://127.0.0.1:5182>, Donation Website <http://127.0.0.1:5180>.

**Optional — Google Chrome instead of Edge:** use the same commands with `-d chrome` in place of
`-d edge`; the hostname and ports stay the same.

- **Admin Panel:** log in with an admin from the credentials file — you see that centre only.
- **Super Admin:** log in with a superadmin — all centres, donation monitoring, history.
- **Donation Website:** donate anonymously or sign in as the donor; payment is simulated.

## 14. Workflows to try

- Donation: Specific / Random / Donate-to-All → review → confirm → **Complete donation**
  (simulated) → receipt download (an *acknowledgement* for simulated payments).
- Unfinished donation: start a checkout, leave, come back → offered to resume or cancel.
- Super Admin: Dashboard KPIs and trends; Donation Transactions (filters, details,
  allocation); Overall Donation History (all centres or one centre; references and statuses).
- Admin Panel: dashboard, patients, schedules, medical records (files unavailable, §8).

## 15. Verify the setup

```powershell
cmd /c "docker exec -i supabase_db_curenurture psql -U postgres -d postgres -f - < tools\handoff\verify_handoff.sql"
```

Expected: every row **PASS**, including *centres loaded … 23 original*, *payments: sandbox,
simulator on, PayMongo off*, *received funds = verified only*, and *foreign keys … 0 with
orphan rows*. Then also check in the apps:

- Super Admin lists exactly the **23 original centres** (synthetic test centres are never in the package).
- **Valenzuela Dialysis Center** (status *full*) appears in the Donation centre list.
- Simulated donations show as **Completed (simulated)** and never add to *Collected funds*
  (Super Admin) or the Admin Panel's received total — only **verified** donations count.

## 16. Troubleshooting

| Symptom | Fix |
|---|---|
| Build error about a missing asset `.env` | Create the `.env` files from the examples (§6); Super Admin needs both `assets\.env` and `.env` |
| `ClientException: Failed to fetch`, API gives an empty reply after Docker restarts | `docker restart supabase_kong_curenurture` (Docker can keep a stale port route) |
| Import says the database already has centres | `supabase db reset`, then import again |
| Login fails right after import | Run `create_dev_credentials.ps1` (§10); use the emails/passwords in the credentials file |
| "Decryption failed" | Wrong passphrase or damaged file; ask for the file/passphrase again |
| `gpg not found` | Install Git for Windows (it includes GnuPG) |
| `supabase` (or `flutter`) "is not recognized" | Close and reopen PowerShell after installing (§3.5, §3.6); check with `supabase --version` / `flutter --version` |
| Port already in use | Stop the other process, or change the port in `supabase\config.toml` |
| Medical documents do not open | Expected: original files are not available (§8) |
| Hide `mobile-app/` locally (optional) | `git sparse-checkout set --no-cone "/*" "!/mobile-app/"` |

## 17. Branch workflow (fork and pull request)

You work in **your own fork** of the public repository; you do not need write access to the
owner's repository. GitHub's guide: <https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/fork-a-repo>.

1. On GitHub, open <https://github.com/mariannegracemontanez-droid/dialysis-capstone> and click
   **Fork** to create `https://github.com/<your-github-username>/dialysis-capstone`.
2. Keep the clone from §4 (`origin` = the owner's repository, used to receive updates) and add
   your fork as a second remote, once:
   ```powershell
   git remote add fork https://github.com/<your-github-username>/dialysis-capstone.git
   ```
3. Work only on your branch (`design-lead-work`); keep `main` untouched.
4. Preserve existing behaviour and business rules unless a change is agreed.
5. Commit small, focused changes, then push the branch to **your fork**:
   `git push -u fork design-lead-work`.
6. On GitHub, open a **pull request** from `<your-github-username>:design-lead-work` into the
   owner's `main`. The project owner reviews and merges it.
7. Before starting new work: `git fetch origin` and `git merge origin/main` into your branch.

Avoid conflicts: agree who edits which screens; do not reformat whole files; never commit
`.env`, `handoff-data\`, credentials or data exports (they are git-ignored — keep it so).

## 18. Security rules (non-negotiable)

- Never connect any app or tool to the live/hosted Supabase project.
- Never enable real payments, PayMongo live keys, or deploy Edge Functions.
- Never commit or share `.env` files, the data package, the passphrase, the credentials file
  or anything in `handoff-data\` (including the private QR images).
- The data package contains real patient and donor information: keep it on your encrypted
  laptop only, never upload it, and delete it when the project ends.
- Do not upload real documents into Storage.
- Do not modify `mobile-app/`.
