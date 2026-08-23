-- Run this manually in the Supabase SQL editor before using the
-- "Today's Dialysis Schedule" session completion / before-after tracking feature.
-- Not applied automatically by the app.

-- Track whether a scheduled dialysis session is still pending or completed.
alter table daily_schedules
  add column if not exists status text not null default 'pending',
  add column if not exists completed_at timestamptz;

alter table daily_schedules
  drop constraint if exists daily_schedules_status_check;

alter table daily_schedules
  add constraint daily_schedules_status_check check (status in ('pending', 'completed'));

-- Allow a weight record to be saved with only the "before dialysis" value
-- filled in; "after dialysis" is added once the session is completed.
alter table weight_logs
  alter column after_weight drop not null;

-- Add the "after dialysis" blood pressure reading alongside the existing
-- systolic/diastolic columns, which are treated as the "before dialysis" reading.
alter table blood_pressure_logs
  add column if not exists after_systolic integer,
  add column if not exists after_diastolic integer;
