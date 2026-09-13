import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import 'patient_service.dart';

/// Handles patient-submitted requests to move/reschedule an assigned
/// dialysis session. Requests are stored in the `reschedule_requests`
/// table and reviewed by clinic staff; this service only ever creates
/// 'pending' rows and reads back the current patient's own requests.
///
/// The Center Admin dashboard reads these same rows and writes the
/// decision back onto them: status becomes 'approved', 'declined' or
/// 'changed_date', with `resolved_date` / `resolved_shift` holding the
/// session the clinic actually scheduled and `admin_notes` any message
/// they left. clinic_id is filled in by a database trigger, so it never
/// has to be sent from here.
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

    try {
      await _supabase.from('reschedule_requests').insert({
        'patient_id': patientId,
        'original_date': originalDate.toIso8601String().split('T').first,
        'requested_date': requestedDate.toIso8601String().split('T').first,
        'reason': reason,
        'notes': notes,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });
    } on PostgrestException catch (e) {
      // Only one pending request per session date is allowed, so the
      // clinic never has to sort through duplicates.
      if (e.code == '23505') {
        throw Exception(
          'You already have a request waiting for this session. Please wait '
          'for your clinic to review it.',
        );
      }
      rethrow;
    }
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
