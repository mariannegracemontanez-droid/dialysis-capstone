-- Feature 3: Direct-to-center donation allocation
--
-- Run this ONCE in the Supabase SQL Editor (Project -> SQL Editor -> New
-- query) for the CureNurture Supabase project used by the Donation app,
-- BEFORE testing the "Distribute Donation Equally Among All Centers" option.
--
-- This script only ADDS one new table. It does not alter, drop, or touch
-- donations, clinics, profiles, fund_distributions, donation_purchase_logs,
-- or any Super Admin functionality in any way.
--
-- WHY THIS IS NEEDED:
-- - "Specific Dialysis Center" and "Randomly Assign a Dialysis Center" both
--   resolve to exactly one center, so they already use the existing
--   donations.clinic_id column directly -- no schema change needed for
--   those two, and the app code for them is unchanged by this migration.
-- - "Distribute Donation Equally Among All Centers" splits one donation
--   across multiple centers. donations.clinic_id can only ever hold one
--   value, and the existing proof-of-payment flow (proof_page.dart) updates
--   exactly one donations row per donation, so equal distribution still
--   creates exactly one donations row (clinic_id left null, amount = the
--   full total) plus one row per center here recording that center's share.
-- - fund_distributions is intentionally NOT used for this: it is the Super
--   Admin's separate manual "push already-collected funds to a center"
--   ledger (every existing row has an admin distributed_by and a fixed
--   status of "Distributed"), which is exactly the manual step this
--   feature is meant to remove. Using it here would route new donations
--   back through the thing being replaced.

create table if not exists public.donation_allocations (
  id uuid primary key default gen_random_uuid(),
  donation_id uuid not null references public.donations(id) on delete cascade,
  clinic_id uuid not null references public.clinics(id),
  amount numeric(12, 2) not null,
  created_at timestamptz not null default now()
);

create index if not exists donation_allocations_donation_id_idx
  on public.donation_allocations (donation_id);

create index if not exists donation_allocations_clinic_id_idx
  on public.donation_allocations (clinic_id);

alter table public.donation_allocations enable row level security;

-- Donors (anonymous or registered) must be able to create allocation rows
-- at donation time, exactly like they already can with donations today.
drop policy if exists "Allow donation allocation inserts" on public.donation_allocations;
create policy "Allow donation allocation inserts"
  on public.donation_allocations
  for insert
  to anon, authenticated
  with check (true);

-- A center admin may only read allocation rows for their OWN center, so
-- one center admin can never see another center's donations. This matches
-- the existing admin-to-clinic relationship already used throughout
-- admin_panel: profiles.clinic_id identifies which center an admin belongs
-- to.
drop policy if exists "Center admins can view their own allocations" on public.donation_allocations;
create policy "Center admins can view their own allocations"
  on public.donation_allocations
  for select
  to authenticated
  using (
    clinic_id in (
      select clinic_id from public.profiles where id = auth.uid()
    )
  );
