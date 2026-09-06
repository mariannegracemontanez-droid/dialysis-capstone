import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/clinic_shift.dart';
import 'center_schedule_service.dart';

class ScheduleService {
  final SupabaseClient supabase = Supabase.instance.client;
  final CenterScheduleService _centerScheduleService = CenterScheduleService();

  Future<List<dynamic>> getEligiblePatients(
    String clinicId,
    String day,
  ) async {
    final cleanDay = day.toLowerCase().trim();

    final response = await supabase
        .from('weekly_schedules')
        .select('''
          id,
          patient_id,
          clinic_id,
          scheduled_days,
          patients (
            id,
            full_name
          )
        ''')
        .eq('clinic_id', clinicId)
        .order('created_at', ascending: true);

    final filtered = response.where((item) {
      final scheduledDays = item['scheduled_days'];

      if (scheduledDays == null || scheduledDays is! List) {
        return false;
      }

      return scheduledDays.any((d) {
        return d.toString().toLowerCase().trim() == cleanDay;
      });
    }).toList();

    return filtered;
  }

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
          created_at,
          patients (
            id,
            full_name
          )
        ''')
        .eq('clinic_id', clinicId)
        .eq('schedule_date', scheduleDate)
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

  Future<bool> isPatientAlreadyAssigned({
    required String patientId,
    required String clinicId,
    required String scheduleDate,
  }) async {
    final existing = await supabase
        .from('daily_schedules')
        .select('id')
        .eq('patient_id', patientId)
        .eq('clinic_id', clinicId)
        .eq('schedule_date', scheduleDate)
        .maybeSingle();

    return existing != null;
  }

  Future<void> assignDailySchedule({
    required String weeklyScheduleId,
    required String patientId,
    required String clinicId,
    required String shift,
    required String scheduleDate,
  }) async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      throw Exception('No logged-in admin found.');
    }

    final alreadyAssigned = await isPatientAlreadyAssigned(
      patientId: patientId,
      clinicId: clinicId,
      scheduleDate: scheduleDate,
    );

    if (alreadyAssigned) {
      throw Exception('This patient is already assigned for this day.');
    }

    // Pull the configured shift time from clinic_shifts instead of a
    // hardcoded AM/PM split, so a manually-added entry always matches
    // whatever the center has actually configured for that shift. Falls
    // back to the old defaults only if no shift configuration exists yet
    // (e.g. the center scheduling foundation migration hasn't run).
    final shifts = await _centerScheduleService.getClinicShifts(clinicId);
    ClinicShift? matchedShift;
    for (final s in shifts) {
      if (s.shiftCode == shift) {
        matchedShift = s;
        break;
      }
    }

    final startTime = matchedShift?.startTime ??
        (shift == 'AM' ? '08:00:00' : '13:00:00');
    final endTime = matchedShift?.endTime ??
        (shift == 'AM' ? '12:00:00' : '17:00:00');

    await supabase.from('daily_schedules').insert({
      'weekly_schedule_id': weeklyScheduleId,
      'patient_id': patientId,
      'clinic_id': clinicId,
      'schedule_date': scheduleDate,
      'shift': shift,
      'start_time': startTime,
      'end_time': endTime,
      'created_by': user.id,
    });
  }

  Future<void> deleteDailySchedule({
    required String dailyScheduleId,
    required String clinicId,
  }) async {
    final deleted = await supabase
        .from('daily_schedules')
        .delete()
        .eq('id', dailyScheduleId)
        .eq('clinic_id', clinicId)
        .select('id');

    if (deleted.isEmpty) {
      throw Exception(
        'No schedule was deleted. Check RLS policy or clinic_id permission.',
      );
    }
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