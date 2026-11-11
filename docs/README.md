# Documentation

## Project Overview

This folder contains documentation for the Dialysis Capstone Thesis Project (CureNurture).

## Start here

- [DESIGN_LEAD_HANDOFF.md](DESIGN_LEAD_HANDOFF.md) — the current setup and run guide for the
  Admin Panel, Super Admin and Donation Website on Windows (local Supabase, data import,
  development logins, verification, branch workflow).

## Structure (repository root)

- **admin_panel/** - Flutter web app for each dialysis centre's admin
- **super_admin_app/** - Flutter web app for the super admin
- **Donation/** - Flutter web app for donors (payments are simulated)
- **packages/curenurture_notice/** - shared Flutter package used by the Admin Panel and Super Admin
- **supabase/** - local Supabase configuration, migrations and (empty) seed
- **tools/handoff/** - data-package import, development logins and verification scripts
- **mobile-app/** - Flutter patient mobile app (not part of the design lead handoff)

## Not current setup instructions

See "Documents you should not follow" in [DESIGN_LEAD_HANDOFF.md](DESIGN_LEAD_HANDOFF.md#0-documents-you-should-not-follow).
