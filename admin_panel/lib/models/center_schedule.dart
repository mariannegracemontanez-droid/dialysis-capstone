// Result types for CenterScheduleService.

import 'clinic_shift.dart';

/// One day + shift pair, as either an existing patient's recurring
/// schedule entry or a pending selection in the assignment UI.
class DayShiftSelection {
  final String day;
  final String shiftId;

  const DayShiftSelection({required this.day, required this.shiftId});
}

/// A patient's existing recurring schedule, if any -- the day/shift pairs
/// live in patient_schedule_days; scheduled_days on weekly_schedules
/// itself stays the plain day-name array every other reader expects.
class PatientRecurringSchedule {
  final String weeklyScheduleId;
  final bool isActive;
  final List<DayShiftSelection> days;

  const PatientRecurringSchedule({
    required this.weeklyScheduleId,
    required this.isActive,
    required this.days,
  });
}

/// Availability outcome for one day + shift combination, surfaced live in
/// the assignment UI as the admin picks days/shifts.
enum DayShiftAvailability {
  available,
  nearCapacity,
  full,
  centerClosed,
  shiftInactive,
}

class DayShiftStatus {
  final String day;
  final String shiftId;
  final DayShiftAvailability availability;
  final String message;

  const DayShiftStatus({
    required this.day,
    required this.shiftId,
    required this.availability,
    required this.message,
  });

  bool get isBlocking =>
      availability == DayShiftAvailability.full ||
      availability == DayShiftAvailability.centerClosed ||
      availability == DayShiftAvailability.shiftInactive;
}

/// Capacity for one shift on one operating day: what the center
/// configured, how many patients already recur there, and what's left.
class ShiftCapacity {
  final ClinicShift shift;
  final int scheduled;

  /// The day-level cap (clinics.target_daily_capacity) can leave a shift
  /// with less usable room than its own configured capacity; this is the
  /// effective figure after that cap has been applied.
  final int effectiveCapacity;

  const ShiftCapacity({
    required this.shift,
    required this.scheduled,
    required this.effectiveCapacity,
  });

  int get available {
    final remaining = effectiveCapacity - scheduled;
    return remaining < 0 ? 0 : remaining;
  }

  bool get isFull => available <= 0;

  /// 0.0 (empty) .. 1.0 (full). A shift configured with zero capacity
  /// counts as fully utilized rather than dividing by zero.
  double get utilization =>
      effectiveCapacity <= 0 ? 1.0 : scheduled / effectiveCapacity;
}

/// Capacity for one day across every configured shift.
class DayCapacity {
  final String day;
  final bool isOperating;
  final List<ShiftCapacity> shifts;

  const DayCapacity({
    required this.day,
    required this.isOperating,
    required this.shifts,
  });

  int get capacity =>
      shifts.fold<int>(0, (sum, s) => sum + s.effectiveCapacity);
  int get scheduled => shifts.fold<int>(0, (sum, s) => sum + s.scheduled);
  int get available => shifts.fold<int>(0, (sum, s) => sum + s.available);
  bool get hasRoom => isOperating && available > 0;

  ShiftCapacity? shiftById(String shiftId) {
    for (final s in shifts) {
      if (s.shift.id == shiftId) return s;
    }
    return null;
  }
}

/// The single source of truth for "what can this center still take?".
/// Built once per operation by CenterScheduleService.getCapacitySnapshot
/// and then shared by validation, the recommendation algorithm, the
/// acceptance evaluation, and the weekly schedule UI -- so capacity is
/// never recomputed differently in two places.
class CenterCapacitySnapshot {
  final List<String> operatingDays;
  final List<ClinicShift> activeShifts;
  final List<DayCapacity> days;

  /// clinics.target_daily_capacity when set -- an optional safety cap
  /// below the sum of the shift capacities.
  final int? dailyCap;

  const CenterCapacitySnapshot({
    required this.operatingDays,
    required this.activeShifts,
    required this.days,
    this.dailyCap,
  });

  DayCapacity? dayByName(String day) {
    for (final d in days) {
      if (d.day == day) return d;
    }
    return null;
  }

  ShiftCapacity? shiftFor(String day, String shiftId) =>
      dayByName(day)?.shiftById(shiftId);

  bool get isConfigured => activeShifts.isNotEmpty && operatingDays.isNotEmpty;
}

/// One patient's entry in the weekly schedule view of the Patients page.
class WeeklyScheduleEntry {
  final String patientId;
  final String patientName;
  final String day;
  final String shiftLabel;
  final String shiftCode;
  final bool isActive;

  const WeeklyScheduleEntry({
    required this.patientId,
    required this.patientName,
    required this.day,
    required this.shiftLabel,
    required this.shiftCode,
    required this.isActive,
  });
}
