-- Run this manually in the Supabase SQL editor.
--
-- daily_schedules currently has RLS policies for SELECT, INSERT, and
-- DELETE (see: "Admins can view daily schedules", "Admins can insert
-- daily schedules", "Admins can delete clinic daily schedules") but no
-- policy for UPDATE. With RLS enabled, a command with no matching policy
-- doesn't error -- it silently matches zero rows. That's why every
-- UPDATE on this table (marking a session completed, saving before/after
-- dialysis data) has been failing without any visible database error.
--
-- This mirrors the same admin/clinic ownership check already used by the
-- existing SELECT and INSERT policies on this table.

drop policy if exists "Admins can update clinic daily schedules" on daily_schedules;

create policy "Admins can update clinic daily schedules"
on daily_schedules
for update
to authenticated
using (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = daily_schedules.clinic_id
  )
)
with check (
  exists (
    select 1 from profiles p
    where p.id = auth.uid()
      and p.role = 'admin'
      and p.clinic_id = daily_schedules.clinic_id
  )
);
