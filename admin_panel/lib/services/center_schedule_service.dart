import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/center_schedule.dart';
import '../models/clinic_shift.dart';

/// The center-side scheduling foundation: operating days, configured
/// shifts, capacity, recurring patient schedules, and the validation the
/// assignment UI, the recommendation algorithm, the acceptance check and
/// the daily schedule all share.
///
/// Capacity is calculated in exactly one place -- [getCapacitySnapshot].
/// Nothing else in the app is allowed to derive capacity from machine
/// counts or shift counts on its own.
///
/// This never decides AM/PM for a specific calendar date on its own
/// initiative: [generateTodayDefaultSchedule] only materializes what a
/// patient's ACTIVE recurring schedule already says, and never overwrites
/// a daily_schedules row that already exists for that patient/date.
class CenterScheduleService {
  final SupabaseClient supabase = Supabase.instance.client;

  static const List<String> allDays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  /// A shift at or above this share of its capacity is flagged as "near
  /// capacity" in the UI and penalized (but not excluded) when ranking
  /// recommendations.
  static const double nearCapacityThreshold = 0.8;

  // ------------------------------------------------------------------
  // Center configuration
  // ------------------------------------------------------------------

  Future<List<String>> getOperatingDays(String clinicId) async {
    final row = await supabase
        .from('clinic_schedule_settings')
        .select('operating_days')
        .eq('clinic_id', clinicId)
        .maybeSingle();

    final raw = row?['operating_days'];
    if (raw is List && raw.isNotEmpty) {
      // Keep the canonical week order regardless of stored order.
      final stored = raw.map((d) => d.toString()).toSet();
      return allDays.where(stored.contains).toList();
    }

    // No row yet for this clinic -- same default the migration seeds, so
    // behavior is unchanged until an admin customizes it.
    return List<String>.from(allDays);
  }

  Future<void> setOperatingDays({
    required String clinicId,
    required List<String> operatingDays,
  }) async {
    await supabase.from('clinic_schedule_settings').upsert({
      'clinic_id': clinicId,
      'operating_days': operatingDays,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'clinic_id');
  }

  Future<List<ClinicShift>> getClinicShifts(
    String clinicId, {
    bool activeOnly = false,
  }) async {
    final response = await supabase
        .from('clinic_shifts')
        .select()
        .eq('clinic_id', clinicId)
        .order('start_time');

    final shifts = (response as List)
        .map((row) => ClinicShift.fromJson(row as Map<String, dynamic>))
        .toList();

    if (!activeOnly) return shifts;
    return shifts.where((s) => s.isActive).toList();
  }

  Future<void> updateClinicShift({
    required String shiftId,
    required String shiftLabel,
    required String startTime,
    required String endTime,
    required int capacity,
    required bool isActive,
  }) async {
    await supabase.from('clinic_shifts').update({
      'shift_label': shiftLabel,
      'start_time': startTime,
      'end_time': endTime,
      'capacity': capacity,
      'is_active': isActive,
    }).eq('id', shiftId);
  }

  /// Optional day-level safety cap (clinics.target_daily_capacity): a
  /// center with 2 x 10-patient shifts may still cap the day at 16.
  Future<int?> _getDailyCap(String clinicId) async {
    final clinic = await supabase
        .from('clinics')
        .select('target_daily_capacity')
        .eq('id', clinicId)
        .maybeSingle();

    return clinic?['target_daily_capacity'] as int?;
  }

  // ------------------------------------------------------------------
  // Capacity -- the single calculation everything else reuses
  // ------------------------------------------------------------------

  /// How many patients recur on each day+shift, keyed `day|shiftId`.
  /// Only ACTIVE recurring schedules count.
  Future<Map<String, int>> _loadRecurringLoad(
    String clinicId, {
    String? excludeWeeklyScheduleId,
  }) async {
    final rows = await supabase
        .from('patient_schedule_days')
        .select('weekly_schedule_id, day_of_week, shift_id, '
            'weekly_schedules(is_active)')
        .eq('clinic_id', clinicId);

    final load = <String, int>{};

    for (final row in rows) {
      final weeklyScheduleId = row['weekly_schedule_id']?.toString();
      if (excludeWeeklyScheduleId != null &&
          weeklyScheduleId == excludeWeeklyScheduleId) {
        continue;
      }

      final related = row['weekly_schedules'];
      final isActive =
          related is Map ? (related['is_active'] as bool? ?? true) : true;
      if (!isActive) continue;

      final key = '${row['day_of_week']}|${row['shift_id']}';
      load[key] = (load[key] ?? 0) + 1;
    }

    return load;
  }

  /// Builds the full center capacity picture in one pass. Every caller
  /// (validation, recommendation, acceptance, weekly view) uses this --
  /// capacity is never derived from machine or shift counts elsewhere.
  Future<CenterCapacitySnapshot> getCapacitySnapshot(
    String clinicId, {
    String? excludeWeeklyScheduleId,
  }) async {
    final operatingDays = await getOperatingDays(clinicId);
    final shifts = await getClinicShifts(clinicId, activeOnly: true);
    final dailyCap = await _getDailyCap(clinicId);
    final load = await _loadRecurringLoad(
      clinicId,
      excludeWeeklyScheduleId: excludeWeeklyScheduleId,
    );

    final totalShiftCapacity =
        shifts.fold<int>(0, (sum, s) => sum + s.capacity);

    final days = <DayCapacity>[];

    for (final day in allDays) {
      final isOperating = operatingDays.contains(day);

      final shiftCapacities = shifts.map((shift) {
        var effective = shift.capacity;

        // Spread a day-level cap proportionally across the shifts so the
        // day total never exceeds it. Without a cap, or without any
        // configured shift capacity, each shift keeps its own figure.
        if (dailyCap != null && totalShiftCapacity > dailyCap) {
          final share = totalShiftCapacity == 0
              ? 0
              : (shift.capacity * dailyCap / totalShiftCapacity).floor();
          effective = share;
        }

        return ShiftCapacity(
          shift: shift,
          scheduled: load['$day|${shift.id}'] ?? 0,
          effectiveCapacity: isOperating ? effective : 0,
        );
      }).toList();

      days.add(
        DayCapacity(
          day: day,
          isOperating: isOperating,
          shifts: shiftCapacities,
        ),
      );
    }

    return CenterCapacitySnapshot(
      operatingDays: operatingDays,
      activeShifts: shifts,
      days: days,
      dailyCap: dailyCap,
    );
  }

  // ------------------------------------------------------------------
  // Patient recurring schedules
  // ------------------------------------------------------------------

  Future<PatientRecurringSchedule?> getPatientRecurringSchedule(
    String patientId,
  ) async {
    final weekly = await supabase
        .from('weekly_schedules')
        .select('id, is_active')
        .eq('patient_id', patientId)
        .maybeSingle();

    if (weekly == null) return null;

    final weeklyScheduleId = weekly['id'].toString();

    final dayRows = await supabase
        .from('patient_schedule_days')
        .select('day_of_week, shift_id')
        .eq('weekly_schedule_id', weeklyScheduleId);

    return PatientRecurringSchedule(
      weeklyScheduleId: weeklyScheduleId,
      isActive: weekly['is_active'] as bool? ?? true,
      days: (dayRows as List)
          .map(
            (row) => DayShiftSelection(
              day: row['day_of_week'].toString(),
              shiftId: row['shift_id'].toString(),
            ),
          )
          .toList(),
    );
  }

  /// Which patients are expected on a given weekday from their active
  /// recurring schedule, mapped to their default shift code. Lets the
  /// daily view label a session as recurring rather than a one-off
  /// addition, without needing a new column on daily_schedules.
  Future<Map<String, String>> getRecurringPatientShiftsForDay({
    required String clinicId,
    required String day,
  }) async {
    final dayRows = await supabase
        .from('patient_schedule_days')
        .select('weekly_schedule_id, shift_id')
        .eq('clinic_id', clinicId)
        .eq('day_of_week', day);

    if (dayRows.isEmpty) return {};

    final shifts = await getClinicShifts(clinicId);
    final shiftCodeById = {for (final s in shifts) s.id: s.shiftCode};

    final weeklyIds = dayRows
        .map((r) => r['weekly_schedule_id'].toString())
        .toSet()
        .toList();

    final weeklyRows = await supabase
        .from('weekly_schedules')
        .select('id, patient_id')
        .inFilter('id', weeklyIds)
        .eq('is_active', true);

    final patientIdByWeeklyId = {
      for (final row in weeklyRows)
        row['id'].toString(): row['patient_id'].toString(),
    };

    final result = <String, String>{};

    for (final row in dayRows) {
      final patientId =
          patientIdByWeeklyId[row['weekly_schedule_id'].toString()];
      final shiftCode = shiftCodeById[row['shift_id'].toString()];
      if (patientId != null && shiftCode != null) {
        result[patientId] = shiftCode;
      }
    }

    return result;
  }

  Future<int?> getSessionsPerWeek(String patientId) async {
    final patient = await supabase
        .from('patients')
        .select('sessions_per_week')
        .eq('id', patientId)
        .maybeSingle();

    return patient?['sessions_per_week'] as int?;
  }

  Future<void> setPatientRecurringSchedule({
    required String patientId,
    required String clinicId,
    required List<DayShiftSelection> dayShifts,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw Exception('No logged in user found.');
    }

    await supabase.rpc('set_patient_recurring_schedule', params: {
      'p_patient_id': patientId,
      'p_clinic_id': clinicId,
      'p_created_by': user.id,
      'p_day_shifts': dayShifts
          .map((d) => {'day': d.day, 'shift_id': d.shiftId})
          .toList(),
    });
  }

  /// Every active recurring schedule at the clinic, grouped by weekday --
  /// the data behind the Patients page weekly table.
  ///
  /// Driven by weekly_schedules.scheduled_days (the authoritative list of
  /// a patient's dialysis days) so a patient shows up under their days
  /// even before a default shift has been assigned; the shift, when one
  /// exists in patient_schedule_days, is attached for display. Nothing
  /// here is a UI-only copy -- it always reflects the stored schedules.
  Future<Map<String, List<WeeklyScheduleEntry>>> getWeeklyPatientSchedule(
    String clinicId,
  ) async {
    final grouped = <String, List<WeeklyScheduleEntry>>{
      for (final day in allDays) day: <WeeklyScheduleEntry>[],
    };

    final weeklyRows = await supabase
        .from('weekly_schedules')
        .select('id, patient_id, scheduled_days, is_active, created_at')
        .eq('clinic_id', clinicId)
        .eq('is_active', true)
        .order('created_at');

    if (weeklyRows.isEmpty) return grouped;

    final patientIds = weeklyRows
        .map((r) => r['patient_id'].toString())
        .toSet()
        .toList();

    final patientRows = await supabase
        .from('patients')
        .select('id, full_name')
        .inFilter('id', patientIds);

    final nameById = {
      for (final row in patientRows)
        row['id'].toString():
            (row['full_name'] ?? 'Unknown patient').toString(),
    };

    // Default shifts, where they've been assigned.
    final shifts = await getClinicShifts(clinicId);
    final shiftsById = {for (final s in shifts) s.id: s};

    final shiftRows = await supabase
        .from('patient_schedule_days')
        .select('weekly_schedule_id, day_of_week, shift_id')
        .eq('clinic_id', clinicId);

    final shiftByScheduleDay = <String, String>{
      for (final row in shiftRows)
        '${row['weekly_schedule_id']}|${row['day_of_week']}':
            row['shift_id'].toString(),
    };

    for (final weekly in weeklyRows) {
      final scheduledDays = weekly['scheduled_days'];
      if (scheduledDays is! List) continue;

      final weeklyId = weekly['id'].toString();
      final patientId = weekly['patient_id'].toString();

      for (final raw in scheduledDays) {
        final day = raw.toString();
        if (!grouped.containsKey(day)) continue;

        final shiftId = shiftByScheduleDay['$weeklyId|$day'];
        final shift = shiftId == null ? null : shiftsById[shiftId];

        grouped[day]!.add(
          WeeklyScheduleEntry(
            patientId: patientId,
            patientName: nameById[patientId] ?? 'Unknown patient',
            day: day,
            shiftLabel: shift?.displayLabel ?? 'No shift',
            shiftCode: shift?.shiftCode ?? '',
            isActive: weekly['is_active'] as bool? ?? true,
          ),
        );
      }
    }

    // Deterministic ordering: shift first (AM before PM, unassigned
    // last), then name.
    for (final entries in grouped.values) {
      entries.sort((a, b) {
        final aCode = a.shiftCode.isEmpty ? 'ZZ' : a.shiftCode;
        final bCode = b.shiftCode.isEmpty ? 'ZZ' : b.shiftCode;
        final byShift = aCode.compareTo(bCode);
        if (byShift != 0) return byShift;
        return a.patientName.toLowerCase().compareTo(
              b.patientName.toLowerCase(),
            );
      });
    }

    return grouped;
  }

  // ------------------------------------------------------------------
  // Validation
  // ------------------------------------------------------------------

  /// Per-day live feedback for the assignment UI. Uses one capacity
  /// snapshot rather than a query per day.
  Future<List<DayShiftStatus>> validateScheduleAssignment({
    required String clinicId,
    required List<DayShiftSelection> dayShifts,
    String? excludeWeeklyScheduleId,
    CenterCapacitySnapshot? snapshot,
  }) async {
    final capacity = snapshot ??
        await getCapacitySnapshot(
          clinicId,
          excludeWeeklyScheduleId: excludeWeeklyScheduleId,
        );

    return dayShifts.map((selection) {
      final day = capacity.dayByName(selection.day);

      if (day == null || !day.isOperating) {
        return DayShiftStatus(
          day: selection.day,
          shiftId: selection.shiftId,
          availability: DayShiftAvailability.centerClosed,
          message: 'The center does not operate on ${selection.day}.',
        );
      }

      final shiftCapacity = day.shiftById(selection.shiftId);
      if (shiftCapacity == null || !shiftCapacity.shift.isActive) {
        return DayShiftStatus(
          day: selection.day,
          shiftId: selection.shiftId,
          availability: DayShiftAvailability.shiftInactive,
          message: 'This shift is not currently available.',
        );
      }

      final label = shiftCapacity.shift.displayLabel;
      final used = '${shiftCapacity.scheduled}/${shiftCapacity.effectiveCapacity}';

      if (shiftCapacity.isFull) {
        return DayShiftStatus(
          day: selection.day,
          shiftId: selection.shiftId,
          availability: DayShiftAvailability.full,
          message: '$label on ${selection.day} is at full capacity ($used).',
        );
      }

      if (shiftCapacity.utilization >= nearCapacityThreshold) {
        return DayShiftStatus(
          day: selection.day,
          shiftId: selection.shiftId,
          availability: DayShiftAvailability.nearCapacity,
          message: '$label on ${selection.day} is near capacity ($used).',
        );
      }

      return DayShiftStatus(
        day: selection.day,
        shiftId: selection.shiftId,
        availability: DayShiftAvailability.available,
        message: '$label on ${selection.day} is available ($used).',
      );
    }).toList();
  }

  /// The authoritative pre-save check. Everything that can block a save
  /// lives here so the modal, and anything added later, can't drift into
  /// having their own partial copies of these rules. Returns null when
  /// the selection is safe to persist.
  ///
  /// The database enforces the last line of defense independently:
  /// weekly_schedules is unique per patient, patient_schedule_days is
  /// unique per (schedule, day), and set_patient_recurring_schedule
  /// re-checks for an existing schedule under a row lock.
  Future<String?> validateFinalAssignment({
    required String patientId,
    required String clinicId,
    required List<DayShiftSelection> dayShifts,
  }) async {
    if (dayShifts.isEmpty) {
      return 'Please select at least one day.';
    }

    final days = dayShifts.map((d) => d.day).toList();
    if (days.toSet().length != days.length) {
      return 'The same day was selected more than once.';
    }

    // A patient may only ever hold one weekly_schedules row (the table is
    // unique on patient_id and set_patient_recurring_schedule rejects a
    // second one under a row lock), so any existing row blocks here --
    // matching the database exactly rather than letting an inactive one
    // slip through to a confusing failure at write time.
    final existing = await getPatientRecurringSchedule(patientId);
    if (existing != null) {
      return existing.isActive
          ? 'This patient already has an active weekly schedule.'
          : 'This patient already has a weekly schedule on record (currently '
              'inactive). Reactivate or remove it before assigning a new one.';
    }

    final sessionsPerWeek = await getSessionsPerWeek(patientId);
    if (sessionsPerWeek != null && dayShifts.length != sessionsPerWeek) {
      return 'This patient requires exactly $sessionsPerWeek session(s) '
          'per week, but ${dayShifts.length} day(s) are selected.';
    }

    final snapshot = await getCapacitySnapshot(clinicId);
    if (!snapshot.isConfigured) {
      return "This center's operating days and shifts are not configured "
          'yet, so capacity cannot be checked.';
    }

    final statuses = await validateScheduleAssignment(
      clinicId: clinicId,
      dayShifts: dayShifts,
      snapshot: snapshot,
    );

    for (final status in statuses) {
      if (status.isBlocking) return status.message;
    }

    return null;
  }

  // ------------------------------------------------------------------
  // Daily schedule generation
  // ------------------------------------------------------------------

  /// Populates a given date's daily_schedules default list from active
  /// recurring schedules. Idempotent and additive only: never touches a
  /// row that already exists for a patient on that date (manually added,
  /// in progress, completed, or previously generated), and never exceeds
  /// a shift's configured capacity for that date.
  Future<void> generateTodayDefaultSchedule({
    required String clinicId,
    required DateTime date,
  }) async {
    if (date.weekday == DateTime.sunday) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    final dayName = allDays[date.weekday - 1];

    final snapshot = await getCapacitySnapshot(clinicId);
    final dayCapacity = snapshot.dayByName(dayName);
    if (dayCapacity == null || !dayCapacity.isOperating) return;
    if (snapshot.activeShifts.isEmpty) return;

    final shiftsById = {for (final s in snapshot.activeShifts) s.id: s};
    final isoDate = date.toIso8601String().split('T')[0];

    final dayRows = await supabase
        .from('patient_schedule_days')
        .select('weekly_schedule_id, shift_id')
        .eq('clinic_id', clinicId)
        .eq('day_of_week', dayName);

    if (dayRows.isEmpty) return;

    final weeklyScheduleIds = dayRows
        .map((r) => r['weekly_schedule_id'].toString())
        .toSet()
        .toList();

    final activeWeeklyRows = await supabase
        .from('weekly_schedules')
        .select('id, patient_id')
        .inFilter('id', weeklyScheduleIds)
        .eq('is_active', true);

    final patientIdByWeeklyId = {
      for (final row in activeWeeklyRows)
        row['id'].toString(): row['patient_id'].toString(),
    };

    final existingToday = await supabase
        .from('daily_schedules')
        .select('patient_id, shift')
        .eq('clinic_id', clinicId)
        .eq('schedule_date', isoDate);

    final alreadyAssigned = <String>{};
    final currentShiftCounts = <String, int>{
      for (final s in snapshot.activeShifts) s.shiftCode: 0,
    };

    for (final row in existingToday) {
      final patientId = row['patient_id']?.toString();
      if (patientId != null) alreadyAssigned.add(patientId);

      final shiftCode = row['shift']?.toString();
      if (shiftCode != null && currentShiftCounts.containsKey(shiftCode)) {
        currentShiftCounts[shiftCode] = currentShiftCounts[shiftCode]! + 1;
      }
    }

    for (final dayRow in dayRows) {
      final weeklyScheduleId = dayRow['weekly_schedule_id'].toString();
      final patientId = patientIdByWeeklyId[weeklyScheduleId];
      if (patientId == null) continue;
      if (alreadyAssigned.contains(patientId)) continue;

      final shift = shiftsById[dayRow['shift_id'].toString()];
      if (shift == null || !shift.isActive) continue;

      final shiftCapacity = dayCapacity.shiftById(shift.id);
      final limit = shiftCapacity?.effectiveCapacity ?? shift.capacity;
      final currentCount = currentShiftCounts[shift.shiftCode] ?? 0;
      if (currentCount >= limit) continue;

      try {
        await supabase.from('daily_schedules').insert({
          'weekly_schedule_id': weeklyScheduleId,
          'patient_id': patientId,
          'clinic_id': clinicId,
          'schedule_date': isoDate,
          'shift': shift.shiftCode,
          'start_time': shift.startTime,
          'end_time': shift.endTime,
          'created_by': user.id,
        });

        alreadyAssigned.add(patientId);
        currentShiftCounts[shift.shiftCode] = currentCount + 1;
      } on PostgrestException catch (e) {
        // Unique-violation: another concurrent call already generated
        // this patient's entry for today. Safe to ignore.
        if (e.code != '23505') rethrow;
      }
    }
  }
}
