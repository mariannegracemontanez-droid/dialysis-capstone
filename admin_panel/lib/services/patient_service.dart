import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/patient.dart';
import 'supabase_config.dart';

class PatientService {
  final SupabaseClient client = SupabaseConfig.client;

  Future<String?> getCurrentClinicId() async {
    final user = client.auth.currentUser;
    if (user == null) return null;

    final profile = await client
        .from('profiles')
        .select('clinic_id')
        .eq('id', user.id)
        .maybeSingle();

    return profile?['clinic_id']?.toString();
  }

  Future<List<Patient>> getPatientsByStatus(String status) async {
    final clinicId = await getCurrentClinicId();
    if (clinicId == null) return [];

    final response = await client
        .from('patients')
        .select('*, profiles(*)')
        .eq('clinic_id', clinicId)
        .eq('status', status)
        .order('created_at', ascending: false);

    return (response as List)
        .map((row) => Patient.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>?> getCurrentAdminInfo() async {
    final user = client.auth.currentUser;
    if (user == null) return null;

    final response = await client
        .from('profiles')
        .select('full_name, clinics(name)')
        .eq('id', user.id)
        .maybeSingle();

    if (response == null) return null;

    return {
      'adminName': response['full_name'] ?? 'Admin',
      'clinicName': response['clinics']?['name'] ?? 'No clinic assigned',
    };
  }

  /// Updates contact details and, when provided, the medical/scheduling
  /// fields. Changes to the medical fields are recorded automatically as
  /// history by the patient_medical_updates trigger -- previous values
  /// are never lost, only superseded.
  Future<void> updatePatientInfo({
    required String patientId,
    required String email,
    required String phone,
    required String homeAddress,
    required String emergencyContactName,
    required String emergencyContactNumber,
    String? dialysisStage,
    String? existingCondition,
    int? sessionsPerWeek,
    bool includeMedicalFields = false,
  }) async {
    final clinicId = await getCurrentClinicId();

    if (clinicId == null) {
      throw Exception('No clinic assigned to this admin account.');
    }

    final payload = <String, dynamic>{
      'email': email,
      'phone': phone,
      'home_address': homeAddress,
      'emergency_contact_name': emergencyContactName,
      'emergency_contact_number': emergencyContactNumber,
    };

    if (includeMedicalFields) {
      payload['dialysis_stage'] = dialysisStage;
      payload['existing_condition'] = existingCondition;
      payload['sessions_per_week'] = sessionsPerWeek;
    }

    await client
        .from('patients')
        .update(payload)
        .eq('id', patientId)
        .eq('clinic_id', clinicId);
  }

  /// Append-only medical change history for a patient, newest first.
  /// Written by the database trigger, never by the client.
  Future<List<Map<String, dynamic>>> getMedicalHistory(String patientId) async {
    final response = await client
        .from('patient_medical_updates')
        .select('field, old_value, new_value, created_at')
        .eq('patient_id', patientId)
        .order('created_at', ascending: false)
        .limit(50);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getPatientMedicalDocs(
    String patientId,
  ) async {
    final files = await client.storage
        .from('medical_docs')
        .list(path: patientId);

    final docs = <Map<String, dynamic>>[];

    for (final file in files) {
      final filePath = '$patientId/${file.name}';

      final signedUrl = await client.storage
          .from('medical_docs')
          .createSignedUrl(filePath, 60 * 10);

      docs.add({
        'name': file.name,
        'path': filePath,
        'url': signedUrl,
        'uploaded_at': file.createdAt,
      });
    }

    return docs;
  }

  Future<List<Patient>> getAllPatients() async {
    final clinicId = await getCurrentClinicId();
    if (clinicId == null) return [];

    final response = await client
        .from('patients')
        .select('*, profiles(*)')
        .eq('clinic_id', clinicId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((row) => Patient.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> updatePatientStatus(String patientId, String newStatus) async {
    final clinicId = await getCurrentClinicId();

    if (clinicId == null) {
      throw Exception('No clinic assigned to this admin account.');
    }

    await client
        .from('patients')
        .update({'status': newStatus})
        .eq('id', patientId)
        .eq('clinic_id', clinicId);
  }

  Future<void> acceptPatient(String patientId) async {
    await updatePatientStatus(patientId, 'no_sched');
  }

  Future<void> declinePatient(String patientId) async {
    await updatePatientStatus(patientId, 'declined');
  }

  Future<void> declinePatientWithReason({
    required String patientId,
    required String reason,
  }) async {
    final clinicId = await getCurrentClinicId();

    if (clinicId == null) {
      throw Exception('No clinic assigned to this admin account.');
    }

    await client
        .from('patients')
        .update({'status': 'declined', 'decline_reason': reason})
        .eq('id', patientId)
        .eq('clinic_id', clinicId);
  }

  Future<void> deletePatientWithReason({
    required String patientId,
    required String reason,
  }) async {
    final clinicId = await getCurrentClinicId();

    if (clinicId == null) {
      throw Exception('No clinic assigned to this admin account.');
    }

    await client
        .from('patients')
        .update({'status': 'deleted', 'delete_reason': reason})
        .eq('id', patientId)
        .eq('clinic_id', clinicId);
  }

  Future<void> activatePatient(String patientId) async {
    await updatePatientStatus(patientId, 'active');
  }

  Future<List<Map<String, dynamic>>> getPatientSchedule(
    String patientId,
  ) async {
    try {
      final response = await client
          .from('weekly_schedules')
          .select('scheduled_days')
          .eq('patient_id', patientId)
          .maybeSingle();

      if (response == null) return [];

      return [
        {'scheduled_days': response['scheduled_days'] ?? []},
      ];
    } catch (e) {
      throw Exception('Failed to load patient schedule: $e');
    }
  }
}
