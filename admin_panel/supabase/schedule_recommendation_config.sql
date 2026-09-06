-- Run this manually in the Supabase SQL editor.
--
-- Supports the automated dialysis schedule recommendation engine
-- (ScheduleRecommendationService). Adds only the configuration/requirement
-- fields the algorithm needs and that genuinely do not exist anywhere in
-- the schema yet.
--
-- IMPORTANT: the recommender only decides which DAYS a patient should be
-- scheduled on. AM/PM shift and machine assignment are decided later, per
-- calendar date, by the center's existing first-come-first-served daily
-- scheduling workflow -- so there is deliberately no "preferred shift" or
-- other permanent per-patient shift field here.
--
-- - clinics.reserved_machines
--   Lets a center hold back machines (maintenance, walk-ins, etc.) instead
--   of the recommender assuming every machine is usable. Nullable-safe via
--   a default of 0 (no reservation), so existing centers behave exactly as
--   before until a superadmin/admin sets it.
--
-- - clinics.target_daily_capacity
--   The center's configured safe/target number of patients per day, e.g.
--   10 machines x 2 shifts = 18-20 theoretical max, but the center may set
--   a lower safe target such as 16. Nullable: the service falls back to
--   (machine - reserved_machines) * shifts when unset.
--
-- - patients.sessions_per_week
--   The one patient-side input the recommendation is built around: how
--   many dialysis days per week this patient needs. Nullable -- falls back
--   to a documented default (3, the standard hemodialysis frequency) in
--   the service when unset.
--
-- Nothing here changes weekly_schedules or daily_schedules -- those
-- already hold everything the recommender reads for day-level occupancy.

alter table clinics
  add column if not exists reserved_machines integer not null default 0,
  add column if not exists target_daily_capacity integer;

alter table clinics
  drop constraint if exists clinics_reserved_machines_check;
alter table clinics
  add constraint clinics_reserved_machines_check check (reserved_machines >= 0);

alter table clinics
  drop constraint if exists clinics_target_daily_capacity_check;
alter table clinics
  add constraint clinics_target_daily_capacity_check
    check (target_daily_capacity is null or target_daily_capacity >= 0);

alter table patients
  add column if not exists sessions_per_week integer;

alter table patients
  drop constraint if exists patients_sessions_per_week_check;
alter table patients
  add constraint patients_sessions_per_week_check
    check (sessions_per_week is null or (sessions_per_week between 1 and 6));
