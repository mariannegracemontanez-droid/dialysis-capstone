import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'patient_service.dart';

class AppointmentService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  Future<Map<String, dynamic>?> getMySchedule() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('No logged in user found.');
    }

    final patient = await PatientService().getActivePatientRow(user.id);

    if (patient == null) {
      return null;
    }

    final weeklySchedule = await _supabase
        .from('weekly_schedules')
        .select('id, patient_id, clinic_id, slot_id, scheduled_days, created_at')
        .eq('patient_id', patient['id'])
        .maybeSingle();

    if (weeklySchedule == null) {
      return null;
    }

    return {'patient': patient, 'weekly_schedule': weeklySchedule};
  }
}
