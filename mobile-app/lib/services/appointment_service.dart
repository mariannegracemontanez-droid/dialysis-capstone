import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class AppointmentService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  Future<Map<String, dynamic>?> getMySchedule() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('No logged in user found.');
    }

    print('AUTH USER ID: ${user.id}');

    final patient = await _supabase
        .from('patients')
        .select('id, clinic_id')
        .eq('profile_id', user.id)
        .maybeSingle();

    print('PATIENT ROW: $patient');

    if (patient == null) {
      return null;
    }

    final weeklySchedule = await _supabase
        .from('weekly_schedules')
        .select('id, patient_id, clinic_id, slot_id, scheduled_days')
        .eq('patient_id', patient['id'])
        .maybeSingle();

    print('WEEKLY SCHEDULE: $weeklySchedule');

    if (weeklySchedule == null) {
      return null;
    }

    return {'patient': patient, 'weekly_schedule': weeklySchedule};
  }
}
