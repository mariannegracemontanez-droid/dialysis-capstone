import 'package:supabase_flutter/supabase_flutter.dart';

class ScheduleService {
  final SupabaseClient supabase = Supabase.instance.client;

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

    final startTime = shift == 'AM' ? '08:00:00' : '13:00:00';
    final endTime = shift == 'AM' ? '12:00:00' : '17:00:00';

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