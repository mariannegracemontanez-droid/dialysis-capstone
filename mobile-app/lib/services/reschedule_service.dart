import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import 'patient_service.dart';

/// Handles patient-submitted requests to move/reschedule an assigned
/// dialysis session. Requests are stored in the `reschedule_requests`
/// table and reviewed by clinic staff; this service only ever creates
/// 'pending' rows and reads back the current patient's own requests.
class RescheduleService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  Future<String?> _currentPatientId() {
    return PatientService().getCurrentActivePatientId();
  }

  Future<void> submitRequest({
    required DateTime originalDate,
    required DateTime requestedDate,
    required String reason,
    String? notes,
  }) async {
    final patientId = await _currentPatientId();
    if (patientId == null) {
      throw Exception('Unable to find your active patient record.');
    }

    await _supabase.from('reschedule_requests').insert({
      'patient_id': patientId,
      'original_date': originalDate.toIso8601String().split('T').first,
      'requested_date': requestedDate.toIso8601String().split('T').first,
      'reason': reason,
      'notes': notes,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getMyRequests() async {
    final patientId = await _currentPatientId();
    if (patientId == null) return [];

    final data = await _supabase
        .from('reschedule_requests')
        .select()
        .eq('patient_id', patientId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(data as List<dynamic>);
  }
}
