-- Run this manually in the Supabase SQL editor.
-- Run AFTER center_scheduling_foundation.sql.
--
-- Patient medical information history (task C). The patients table
-- already holds the current medical values (blood_type, dialysis_stage,
-- existing_condition) plus the scheduling requirement added earlier
-- (sessions_per_week) -- none of those are duplicated here. What's
-- missing is history: today an edit silently overwrites the previous
-- value with no record of what changed, when, or by whom.
--
-- This adds an append-only change log written by a trigger on patients,
-- so history is captured no matter which code path performs the update
-- (admin panel, mobile app, SQL editor) and cannot be bypassed or
-- rewritten from the client.

create table if not exists patient_medical_updates (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references patients(id) on delete cascade,
  clinic_id uuid references clinics(id) on delete set null,
  field text not null,
  old_value text,
  new_value text,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists patient_medical_updates_patient_idx
  on patient_medical_updates (patient_id, created_at desc);

alter table patient_medical_updates enable row level security;

-- Read-only from the client: rows are written exclusively by the
-- security-definer trigger below, so history can't be edited or deleted
-- after the fact.
drop policy if exists "Admins can view own clinic medical history" on patient_medical_updates;
create policy "Admins can view own clinic medical history"
on patient_medical_updates
for select
to authenticated
using (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = patient_medical_updates.clinic_id
  )
);

create or replace function public.log_patient_medical_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
begin
  if new.blood_type is distinct from old.blood_type then
    insert into patient_medical_updates
      (patient_id, clinic_id, field, old_value, new_value, updated_by)
    values
      (new.id, new.clinic_id, 'Blood Type', old.blood_type, new.blood_type, v_actor);
  end if;

  if new.dialysis_stage is distinct from old.dialysis_stage then
    insert into patient_medical_updates
      (patient_id, clinic_id, field, old_value, new_value, updated_by)
    values
      (new.id, new.clinic_id, 'Dialysis Stage', old.dialysis_stage, new.dialysis_stage, v_actor);
  end if;

  if new.existing_condition is distinct from old.existing_condition then
    insert into patient_medical_updates
      (patient_id, clinic_id, field, old_value, new_value, updated_by)
    values
      (new.id, new.clinic_id, 'Existing Condition', old.existing_condition, new.existing_condition, v_actor);
  end if;

  if new.sessions_per_week is distinct from old.sessions_per_week then
    insert into patient_medical_updates
      (patient_id, clinic_id, field, old_value, new_value, updated_by)
    values
      (new.id, new.clinic_id, 'Required Sessions / Week',
       old.sessions_per_week::text, new.sessions_per_week::text, v_actor);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_log_patient_medical_update on patients;
create trigger trg_log_patient_medical_update
after update on patients
for each row
execute function public.log_patient_medical_update();
