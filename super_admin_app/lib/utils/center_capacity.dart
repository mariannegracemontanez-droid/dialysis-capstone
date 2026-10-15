// The one Super Admin capacity calculation, shared by the Centres table, the
// centre details modal and DashboardService, so they can never disagree.
//
//   Total Capacity   = machines × the centre's saved shifts per day
//   Available (Est.) = Total Capacity − reserved patients (never below 0)
//
// Both are estimates for display only. Neither is ever written to
// `clinics.slots_available`, which keeps the separately saved Available
// Slots value.

import 'dart:math' as math;

/// Shifts per day assumed only when a centre's `shifts` value is missing or
/// unreadable -- the value centres were always saved with before the shift
/// count became editable.
const int defaultShiftsPerDay = 2;

/// Machines × shifts. Negative inputs count as 0.
int totalCenterCapacity({required int machines, required int shifts}) =>
    math.max(0, machines) * math.max(0, shifts);

/// [totalCapacity] minus [reservedPatients], clamped to 0 when reserved
/// patients exceed capacity.
int estimatedAvailableSlots({
  required int totalCapacity,
  required int reservedPatients,
}) => math.max(0, totalCapacity - reservedPatients);

/// A saved shift count, or [defaultShiftsPerDay] only when the value is
/// genuinely missing (null, blank or not a number). A saved 0, 1, 3 ... is
/// kept as-is.
int savedShiftsOrDefault(Object? raw) {
  final parsed = num.tryParse(raw?.toString().trim() ?? '');
  return parsed == null ? defaultShiftsPerDay : parsed.toInt();
}
