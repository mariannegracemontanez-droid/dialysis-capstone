-- Intentionally empty.
--
-- CureNurture's centres, accounts, patients and donation history are NOT
-- stored in this repository. They are delivered as an encrypted data package
-- outside GitHub and loaded with tools/handoff/import_handoff_data.ps1
-- (see docs/DESIGN_LEAD_HANDOFF.md). The migrations in supabase/migrations
-- create the schema; the payment settings row (sandbox, simulator on,
-- PayMongo off) is created by the donation sandbox migration.
select 1;
