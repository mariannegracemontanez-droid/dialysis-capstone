import 'package:supabase_flutter/supabase_flutter.dart';

import 'center_schedule_service.dart';

/// Reads and updates the per-session record on daily_schedules (one row =
/// one patient, one date, one shift).
///
/// Who may be added to a date, adding/removing/moving them, and the
/// capacity behind those decisions all live in CenterScheduleService --
/// there is deliberately no second copy of that logic here. The methods
/// that used to do it (getEligiblePatients / assignDailySchedule /
/// deleteDailySchedule) were replaced by
/// CenterScheduleService.getDateCandidates / addPatientToDate /
/// cancelDateOccurrence; the delete in particular could not survive,
/// because generateTodayDefaultSchedule re-created any deleted row from
/// the patient's recurring schedule on the next refresh.
class ScheduleService {
  final SupabaseClient supabase = Supabase.instance.client;

  /// The live sessions for a date. Cancelled occurrences (a patient taken
  /// off that one date) are excluded: the row is kept as the one-day
  /// override that stops regeneration, but it is not part of the day's
  /// schedule any more.
  Future<List<dynamic>> getDailyAssignments({
    required String clinicId,
    required String scheduleDate,
  }) async {
    final response = await supabase
        .from('daily_schedules')
        .select('''
          id,
          patient_id,
          clinic_id,
          weekly_schedule_id,
          schedule_date,
          shift,
          start_time,
          end_time,
          status,
          completed_at,
          before_weight,
          before_systolic,
          before_diastolic,
          after_weight,
          duration_hours,
          duration_minutes,
          reschedule_request_id,
          created_at,
          patients (
            id,
            full_name
          )
        ''')
        .eq('clinic_id', clinicId)
        .eq('schedule_date', scheduleDate)
        .neq('status', CenterScheduleService.occurrenceCancelled)
        .order('created_at', ascending: true);

    return response;
  }

  bool isSessionCompleted(dynamic item) {
    return item['status']?.toString() == 'completed';
  }

  Future<void> markSessionCompleted({
    required String dailyScheduleId,
    required String clinicId,
  }) async {
    final updated = await supabase
        .from('daily_schedules')
        .update({
          'status': 'completed',
          'completed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', dailyScheduleId)
        .eq('clinic_id', clinicId)
        .select('id');

    if (updated.isEmpty) {
      throw Exception(
        'Session update was not applied. Check RLS policy or clinic_id permission.',
      );
    }
  }

  /// Persists the before-dialysis weight and blood pressure directly on the
  /// daily_schedules row for this session (one row = one patient/date/shift
  /// session, so this is the single source of truth for the session record).
  Future<Map<String, dynamic>> saveBeforeDialysisData({
    required String dailyScheduleId,
    required String clinicId,
    required double beforeWeight,
    required int beforeSystolic,
    required int beforeDiastolic,
  }) async {
    final updated = await supabase
        .from('daily_schedules')
        .update({
          'before_weight': beforeWeight,
          'before_systolic': beforeSystolic,
          'before_diastolic': beforeDiastolic,
        })
        .eq('id', dailyScheduleId)
        .eq('clinic_id', clinicId)
        .select();

    if (updated.isEmpty) {
      throw Exception(
        'Before-dialysis data was not saved. Check RLS policy or clinic_id permission.',
      );
    }

    return updated.first;
  }

  /// Persists the after-dialysis weight and session duration on the same
  /// daily_schedules row. Should only be called once the session has been
  /// marked completed.
  Future<Map<String, dynamic>> saveAfterDialysisData({
    required String dailyScheduleId,
    required String clinicId,
    required double afterWeight,
    required int durationHours,
    required int durationMinutes,
  }) async {
    final updated = await supabase
        .from('daily_schedules')
        .update({
          'after_weight': afterWeight,
          'duration_hours': durationHours,
          'duration_minutes': durationMinutes,
        })
        .eq('id', dailyScheduleId)
        .eq('clinic_id', clinicId)
        .select();

    if (updated.isEmpty) {
      throw Exception(
        'After-dialysis data was not saved. Check RLS policy or clinic_id permission.',
      );
    }

    return updated.first;
  }

  String getPatientName(dynamic item) {
    final patient = item['patients'];

    if (patient == null) {
      return item['patient_id']?.toString() ?? 'Unknown Patient';
    }

    final fullName = patient['full_name'];

    if (fullName != null && fullName.toString().trim().isNotEmpty) {
      return fullName.toString();
    }

    return item['patient_id']?.toString() ?? 'Unknown Patient';
  }
}