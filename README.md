# Dialysis Capstone Thesis Project (CureNurture)

A system for managing dialysis patient care: a patient mobile app, a centre admin web panel,
a super admin web portal, and a donation website, all backed by Supabase.

> **Setting up the project?** Start with [docs/DESIGN_LEAD_HANDOFF.md](docs/DESIGN_LEAD_HANDOFF.md).
> It is the only current setup guide for the Admin Panel, Super Admin and Donation Website.

## 📁 Project Structure

```
dialysis-capstone/
├── admin_panel/                  # Flutter web app for each dialysis centre's admin
├── super_admin_app/              # Flutter web app for system oversight (super admin)
├── Donation/                     # Flutter web app for donors (payments are simulated)
├── packages/curenurture_notice/  # Shared Flutter package (Admin Panel + Super Admin)
├── supabase/                     # Local Supabase: config, migrations, seed
├── tools/handoff/                # Data-package import, dev logins, verification
├── docs/                         # Documentation (setup guide)
└── mobile-app/                   # Flutter patient mobile app (not part of the design lead handoff)
```

## ✨ Features

### Mobile App (Patients) — `mobile-app/`
- User authentication (Login/Signup)
- Appointment scheduling
- Medical records management
- Patient profile information
- Donation drive registration

### Admin Panel — `admin_panel/`
- Patient management
- Appointment scheduling
- Medical records access
- Donation management

### Super Admin — `super_admin_app/`
- Full system control
- Admin management
- Analytics and reporting
- System configuration

### Donation Website — `Donation/`
- Donor registration
- Donation tracking
- Donor history

## 🛠️ Tech Stack

- **Apps:** Flutter + Dart (mobile app and all three web apps, including the Donation Website)
- **Backend/Database:** Supabase (for development: a local Supabase in Docker, started with the Supabase CLI)
- **Version Control:** Git & GitHub

## 📋 Setup Instructions

Follow [docs/DESIGN_LEAD_HANDOFF.md](docs/DESIGN_LEAD_HANDOFF.md) for the Admin Panel, Super Admin
and Donation Website. The mobile app is not covered by that guide.

## ⚠️ Documents you should not follow for setup

| Document | Why |
|---|---|
| Earlier versions of this README | Described folders that do not exist (`mobile/`, `admin-dashboard/`, `superadmin-dashboard/`, `donation-drive/`) and an HTML donation site |
| `QUICK_REFERENCE.md`, `IMPLEMENTATION_SUMMARY.md` | Historical feature notes, not current setup instructions |
| `Donation/DONATION_SANDBOX_GUIDE.md`, sections 4 and 5 | They run SQL and deploy functions on the **live** Supabase project. Locally, those database changes are already in `supabase/migrations/` |

## 👥 Contributors

- Marianne Grace Montanez (Lead Developer)

## 📄 License

MIT License

# dialysis-capstone
Monorepo for dialysis management system - mobile app, admin dashboard, super admin dashboard, and donation drive
