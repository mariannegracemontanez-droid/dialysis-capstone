import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/center_schedule.dart';
import '../models/clinic_shift.dart';
import '../models/reschedule_request.dart';
import 'center_schedule_service.dart';

/// Center Admin side of the patient reschedule flow.
///
/// Reads the SAME `reschedule_requests` rows the mobile app writes from
/// mobile-app/lib/services/reschedule_service.dart -- there is no separate
/// admin-side request store. RLS scopes every read and write to the
/// admin's own clinic.
///
/// Deciding a request is a single call to the `review_reschedule_request`
/// database function, so cancelling the original date's occurrence and
/// creating the new one either both happen or neither does. That function
/// never writes to weekly_schedules, patient_schedule_days or
/// patients.preferred_shift: an accepted request is a ONE-TIME change.
class RescheduleRequestService {
  final SupabaseClient supabase = Supabase.instance.client;
  final CenterScheduleService _centerScheduleService = CenterScheduleService();

  static const String statusPending = 'pending';
  static const String statusApproved = 'approved';
  static const String statusDeclined = 'declined';
  static const String statusChangedDate = 'changed_date';

  /// Requests for the admin's clinic, pending ones first, newest first
  /// inside each group.
  Future<List<RescheduleRequest>> getRequests({
    required String clinicId,
    int limit = 50,
  }) async {
    final rows = await supabase
        .from('reschedule_requests')
        .select('''
          id,
          patient_id,
          clinic_id,
          original_date,
          requested_date,
          resolved_date,
          resolved_shift,
          reason,
          notes,
          status,
          created_at,
          reviewed_at,
          admin_notes,
          patients (
            id,
            full_name
          )
        ''')
        .eq('clinic_id', clinicId)
        .order('created_at', ascending: false)
        .limit(limit);

    final requests = (rows as List)
        .map((row) => RescheduleRequest.fromJson(row as Map<String, dynamic>))
        .toList();

    requests.sort((a, b) {
      if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
      final aDate = a.createdAt;
      final bDate = b.createdAt;
      if (aDate == null || bDate == null) return 0;
      return bDate.compareTo(aDate);
    });

    return requests;
  }

  Future<int> getPendingCount(String clinicId) async {
    final rows = await supabase
        .from('reschedule_requests')
        .select('id')
        .eq('clinic_id', clinicId)
        .eq('status', statusPending);

    return (rows as List).length;
  }

  /// The admin-facing capacity/conflict check, run before the database
  /// call so the admin gets a readable explanation instead of a raw
  /// exception. It reuses the one capacity calculation
  /// (CenterScheduleService.getDateCapacity) rather than recomputing
  /// anything; `review_reschedule_request` still re-checks the hard
  /// constraints itself as the last line of defense.
  ///
  /// Returns null when the date/shift is safe to grant.
  Future<String?> validateTarget({
    required String clinicId,
    required String patientId,
    required DateTime date,
    String? shiftCode,
  }) async {
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);

    if (date.isBefore(startOfToday)) {
      return 'That dialysis date has already passed.';
    }

    final dayName = CenterScheduleService.dayNameFor(date);
    if (dayName == null) {
      return 'The center is closed on Sunday.';
    }

    final dayCapacity = await _centerScheduleService.getDateCapacity(
      clinicId: clinicId,
      date: date,
    );

    if (!dayCapacity.isOperating) {
      return 'The center does not operate on $dayName.';
    }

    final resolvedShift =
        shiftCode ?? await _defaultShiftCodeFor(patientId: patientId, day: dayName);

    if (resolvedShift == null) {
      return 'This patient has no default shift on $dayName. '
          'Use Change Date and pick a shift.';
    }

    ShiftCapacity? shiftCapacity;
    for (final entry in dayCapacity.shifts) {
      if (entry.shift.shiftCode == resolvedShift) shiftCapacity = entry;
    }

    if (shiftCapacity == null || !shiftCapacity.shift.isActive) {
      return 'The $resolvedShift shift is not active at this center.';
    }

    if (shiftCapacity.isFull) {
      return 'The $resolvedShift shift on $dayName is full '
          '(${shiftCapacity.scheduled}/${shiftCapacity.effectiveCapacity}). '
          'Free a slot or pick another date.';
    }

    final existing = await supabase
        .from('daily_schedules')
        .select('status, shift')
        .eq('clinic_id', clinicId)
        .eq('patient_id', patientId)
        .eq('schedule_date', CenterScheduleService.isoDate(date))
        .maybeSingle();

    final status = existing?['status']?.toString();

    if (status == CenterScheduleService.occurrenceCompleted) {
      return 'This patient already completed a dialysis session on that date.';
    }

    if (status == CenterScheduleService.occurrencePending) {
      return 'This patient already has a dialysis session scheduled on that '
          'date (${existing?['shift']} shift).';
    }

    return null;
  }

  /// The patient's recurring default shift for a weekday, read from
  /// patient_schedule_days. Read-only -- granting a reschedule never
  /// changes it.
  Future<String?> _defaultShiftCodeFor({
    required String patientId,
    required String day,
  }) async {
    final weekly = await supabase
        .from('weekly_schedules')
        .select('id, clinic_id')
        .eq('patient_id', patientId)
        .eq('is_active', true)
        .maybeSingle();

    if (weekly == null) return null;

    final dayRow = await supabase
        .from('patient_schedule_days')
        .select('shift_id')
        .eq('weekly_schedule_id', weekly['id'])
        .eq('day_of_week', day)
        .maybeSingle();

    if (dayRow == null) return null;

    final shifts = await _centerScheduleService.getClinicShifts(
      weekly['clinic_id'].toString(),
    );

    for (final shift in shifts) {
      if (shift.id == dayRow['shift_id'].toString()) return shift.shiftCode;
    }

    return null;
  }

  Future<List<ClinicShift>> getActiveShifts(String clinicId) {
    return _centerScheduleService.getClinicShifts(clinicId, activeOnly: true);
  }

  /// Accept on the date the patient asked for.
  Future<Map<String, dynamic>> accept({
    required String requestId,
    String? shiftCode,
    String? adminNotes,
  }) {
    return _review(
      requestId: requestId,
      decision: statusApproved,
      shiftCode: shiftCode,
      adminNotes: adminNotes,
    );
  }

  /// Accept, but on a date the admin picked instead.
  Future<Map<String, dynamic>> changeDate({
    required String requestId,
    required DateTime date,
    String? shiftCode,
    String? adminNotes,
  }) {
    return _review(
      requestId: requestId,
      decision: statusChangedDate,
      targetDate: date,
      shiftCode: shiftCode,
      adminNotes: adminNotes,
    );
  }

  /// Reject. No session is created, nothing is cancelled, and the
  /// recurring schedule is untouched.
  Future<Map<String, dynamic>> reject({
    required String requestId,
    String? adminNotes,
  }) {
    return _review(
      requestId: requestId,
      decision: statusDeclined,
      adminNotes: adminNotes,
    );
  }

  Future<Map<String, dynamic>> _review({
    required String requestId,
    required String decision,
    DateTime? targetDate,
    String? shiftCode,
    String? adminNotes,
  }) async {
    final result = await supabase.rpc(
      'review_reschedule_request',
      params: {
        'p_request_id': requestId,
        'p_decision': decision,
        'p_target_date':
            targetDate == null ? null : CenterScheduleService.isoDate(targetDate),
        'p_shift_code': shiftCode,
        'p_admin_notes': adminNotes,
      },
    );

    if (result is Map) return Map<String, dynamic>.from(result);
    return <String, dynamic>{};
  }
}
