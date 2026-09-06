-- Run this manually in the Supabase SQL editor.
-- Follow-up to dialysis_session_tracking.sql.
--
-- Moves the per-session before/after dialysis record onto daily_schedules
-- itself, since each daily_schedules row already represents exactly one
-- dialysis session (one patient, one date, one shift) and already carries
-- status/completed_at. Storing before/after weight, before blood pressure,
-- and session duration directly on that row gives a single source of
-- truth per session and makes a future "Dialysis Session History" view a
-- straightforward query on this one table.

alter table daily_schedules
  add column if not exists before_weight numeric,
  add column if not exists before_systolic integer,
  add column if not exists before_diastolic integer,
  add column if not exists after_weight numeric,
  add column if not exists duration_hours integer,
  add column if not exists duration_minutes integer;

alter table daily_schedules
  drop constraint if exists daily_schedules_duration_hours_check;

alter table daily_schedules
  add constraint daily_schedules_duration_hours_check
    check (duration_hours is null or (duration_hours >= 0 and duration_hours <= 8));

alter table daily_schedules
  drop constraint if exists daily_schedules_duration_minutes_check;

alter table daily_schedules
  add constraint daily_schedules_duration_minutes_check
    check (duration_minutes is null or (duration_minutes >= 0 and duration_minutes <= 59));

-- After-dialysis blood pressure is not part of the workflow. These columns
-- (added in dialysis_session_tracking.sql) are unused anywhere in the app
-- now that the per-session before/after flow lives on daily_schedules
-- instead of blood_pressure_logs -- safe to drop.
alter table blood_pressure_logs
  drop column if exists after_systolic,
  drop column if exists after_diastolic;
