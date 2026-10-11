-- Run this manually in the Supabase SQL editor, BEFORE releasing the mobile
-- app build that writes separated patient names.
--
-- Separated patient name columns (first / middle / last).
--
-- Where the name lives today:
--   profiles.full_name  - the account name, written at sign-up.
--   patients.full_name  - one row per clinic application; it is the snapshot
--                         of what the patient submitted to that clinic, and
--                         is what the Admin panel and
--                         initialize_patient_default_shifts() read.
-- Both tables get the same three columns. full_name is KEPT and the mobile
-- app keeps writing it (formatted "First Middle Last"), so every existing
-- reader (Admin, Superadmin, Donation, SQL functions) keeps working
-- unchanged.
--
-- Legacy rows: existing names are NOT split automatically (compound first
-- names / surnames make that unreliable). Their new columns stay NULL and
-- full_name is untouched; see section 5 for finding and fixing them.
--
-- Safety: no DROP, no DELETE, no UPDATE of existing data. Every statement
-- is idempotent, so the script can be re-run. It runs in one transaction.

begin;

-- 1. Columns. Nullable on purpose: legacy rows and accounts that haven't
--    finished setup have no separated name yet.
alter table public.profiles
  add column if not exists first_name text,
  add column if not exists middle_name text,
  add column if not exists last_name text;

alter table public.patients
  add column if not exists first_name text,
  add column if not exists middle_name text,
  add column if not exists last_name text;

comment on column public.patients.first_name is
  'Patient first name as submitted to this clinic. NULL on legacy rows (see full_name).';
comment on column public.patients.middle_name is
  'Patient middle name; NULL when the patient has no middle name or on legacy rows.';
comment on column public.patients.last_name is
  'Patient last name as submitted to this clinic. NULL on legacy rows (see full_name).';
comment on column public.profiles.first_name is
  'Account first name. NULL on legacy profiles (see full_name).';
comment on column public.profiles.middle_name is
  'Account middle name; NULL when there is none or on legacy profiles.';
comment on column public.profiles.last_name is
  'Account last name. NULL on legacy profiles (see full_name).';

-- 2. Constraints. A row is either
--      - not separated yet: first_name AND last_name both NULL (legacy), or
--      - complete: first_name AND last_name both non-blank;
--    and middle_name is NULL or non-blank (never an empty string).
--    The IS NOT NULL tests are explicit because a CHECK that evaluates to
--    NULL passes (e.g. first_name NULL with last_name set).
--    Existing rows all have NULL parts, so they pass; Admin/Superadmin
--    updates to other columns of legacy rows are unaffected.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_name_parts_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_name_parts_check check (
        (
          (first_name is null and last_name is null)
          or (
            first_name is not null and last_name is not null
            and btrim(first_name) <> '' and btrim(last_name) <> ''
          )
        )
        and (middle_name is null or btrim(middle_name) <> '')
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'patients_name_parts_check'
      and conrelid = 'public.patients'::regclass
  ) then
    alter table public.patients
      add constraint patients_name_parts_check check (
        (
          (first_name is null and last_name is null)
          or (
            first_name is not null and last_name is not null
            and btrim(first_name) <> '' and btrim(last_name) <> ''
          )
        )
        and (middle_name is null or btrim(middle_name) <> '')
      );
  end if;
end $$;

-- 3. Sorting: "Last name, First name", case-insensitive. Patient lists are
--    per clinic, so clinic_id leads the patients index.
create index if not exists patients_clinic_name_sort_idx
  on public.patients (clinic_id, lower(last_name), lower(first_name));

create index if not exists profiles_name_sort_idx
  on public.profiles (lower(last_name), lower(first_name));

-- 4. Budget Range was removed from the mobile app, which no longer sends
--    patients.budget. The column and its existing values are kept. If the
--    column happens to be NOT NULL without a default, new applications
--    would fail, so only in that case relax it to nullable (no data is
--    changed).
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'patients'
      and column_name = 'budget'
      and is_nullable = 'NO'
      and column_default is null
  ) then
    alter table public.patients alter column budget drop not null;
  end if;
end $$;

commit;

-- ---------------------------------------------------------------------------
-- 5. MANUAL REVIEW (read-only - run these separately, nothing is changed)
-- ---------------------------------------------------------------------------
-- Records whose name has not been separated yet. These keep working (the
-- app and Admin display full_name); they just can't sort by last name until
-- fixed. A patient fixes their own name by re-entering it in setup Step 1
-- when applying to another clinic; otherwise staff can correct it below.
--
-- select id, clinic_id, status, full_name, created_at
-- from public.patients
-- where first_name is null and last_name is null
-- order by clinic_id, lower(full_name);
--
-- select id, role, full_name, created_at
-- from public.profiles
-- where role = 'patient' and first_name is null and last_name is null
-- order by lower(full_name);
--
-- Correcting one record after confirming the parts with the patient (keep
-- full_name in step with the parts; use NULL for "no middle name"):
--
-- update public.patients
-- set first_name = 'Juan', middle_name = null, last_name = 'Dela Cruz',
--     full_name = 'Juan Dela Cruz'
-- where id = '<patients.id>';
--
-- ---------------------------------------------------------------------------
-- 6. Sorting example for patient lists (legacy rows sort by full_name):
-- ---------------------------------------------------------------------------
-- select id, first_name, middle_name, last_name, full_name
-- from public.patients
-- where clinic_id = '<clinic-id>'
-- order by lower(coalesce(last_name, full_name)),
--          lower(coalesce(first_name, '')),
--          lower(coalesce(middle_name, '')),
--          id;
