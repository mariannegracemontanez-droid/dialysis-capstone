import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../utils/patient_name.dart';

class PatientService {
  final SupabaseClient _supabase = SupabaseConfig.client;
  final List<String> _activeStatuses = ['approved', 'active', 'no_sched'];

  Future<Map<String, dynamic>?> getActivePatientRow(String profileId) async {
    final response = await _supabase
        .from('patients')
        .select(
          'id, profile_id, clinic_id, status, full_name, email, phone, created_at',
        )
        .eq('profile_id', profileId)
        .not('clinic_id', 'is', null)
        .inFilter('status', _activeStatuses)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>?> getMostRecentPatientRow(
    String profileId,
  ) async {
    final response = await _supabase
        .from('patients')
        .select()
        .eq('profile_id', profileId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return Map<String, dynamic>.from(response);
  }

  Future<bool> hasPatientAccess(String profileId) async {
    final activePatient = await getActivePatientRow(profileId);
    return activePatient != null;
  }

  Future<String?> getCurrentActivePatientId() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final patient = await getActivePatientRow(user.id);
    return patient?['id']?.toString();
  }

  /// The patient's pending/declined applications for the Pending Account
  /// page. Each row is the full `patients` application row (the snapshot
  /// of what was submitted to that clinic) plus:
  /// - `clinic_name` and `clinic` (the clinic's details, incl. requirements)
  /// - `documents` (that application's `medical_documents` row, or null)
  ///
  /// Three queries in total regardless of how many applications exist.
  Future<List<Map<String, dynamic>>> getPendingApplications(
    String profileId,
  ) async {
    final response = await _supabase
        .from('patients')
        .select()
        .eq('profile_id', profileId)
        .not('clinic_id', 'is', null)
        .inFilter('status', ['pending', 'declined'])
        .order('created_at', ascending: false);

    final rows = List<Map<String, dynamic>>.from(response as List<dynamic>);
    if (rows.isEmpty) {
      return [];
    }

    final clinicIds = rows
        .map((row) => row['clinic_id']?.toString())
        .whereType<String>()
        .toSet()
        .toList();
    final patientIds = rows
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .toList();

    final clinicMap = <String, Map<String, dynamic>>{};
    if (clinicIds.isNotEmpty) {
      final clinicResponse = await _supabase
          .from('clinics')
          .select()
          .inFilter('id', clinicIds);

      for (final clinic in List<Map<String, dynamic>>.from(
        clinicResponse as List<dynamic>,
      )) {
        final id = clinic['id']?.toString();
        if (id != null) {
          clinicMap[id] = clinic;
        }
      }
    }

    // Documents are keyed by application (patient_id), which is already
    // specific to one clinic. A failure here shouldn't hide the
    // applications themselves.
    final documentMap = <String, Map<String, dynamic>>{};
    if (patientIds.isNotEmpty) {
      try {
        final documentResponse = await _supabase
            .from('medical_documents')
            .select()
            .inFilter('patient_id', patientIds);

        for (final document in List<Map<String, dynamic>>.from(
          documentResponse as List<dynamic>,
        )) {
          final patientId = document['patient_id']?.toString();
          if (patientId != null) {
            documentMap[patientId] = document;
          }
        }
      } catch (_) {
        // Leave documentMap empty; the page shows an unavailable state.
      }
    }

    return rows.map((row) {
      final clinic = clinicMap[row['clinic_id']?.toString()];
      return {
        ...row,
        'clinic_name': clinic?['name']?.toString() ?? 'Clinic',
        'clinic': clinic,
        'documents': documentMap[row['id']?.toString()],
      };
    }).toList();
  }

  /// Saves the patient's separated name on their account profile (the
  /// application rows carry their own per-clinic snapshot).
  Future<void> updateProfileName({
    required String profileId,
    required PatientName name,
  }) async {
    if (!name.hasComponents) return;

    await _supabase
        .from('profiles')
        .update(name.toColumns())
        .eq('id', profileId);
  }

  Future<Map<String, dynamic>?> getPatientApplicationByClinic(
    String profileId,
    Object clinicId,
  ) async {
    final response = await _supabase
        .from('patients')
        .select('id, status')
        .eq('profile_id', profileId)
        .eq('clinic_id', clinicId)
        .limit(1)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return Map<String, dynamic>.from(response);
  }

  Future<String> createPatientApplication({
    required String profileId,
    required Object clinicId,
    required Map<String, Object?> details,
  }) async {
    final existing = await getPatientApplicationByClinic(profileId, clinicId);
    if (existing != null) {
      final status = existing['status']?.toString().toLowerCase().trim() ?? '';
      if (status == 'pending') {
        throw Exception(
          'You already have a pending application for this clinic.',
        );
      }
      if (status == 'rejected' || status == 'declined') {
        throw Exception(
          'You already have an application for this clinic. Duplicate applications are not allowed at this time.',
        );
      }

      throw Exception('You already have an application for this clinic.');
    }

    final patientData = <String, Object?>{
      ...details,
      'profile_id': profileId,
      'clinic_id': clinicId,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    };

    final response = await _supabase
        .from('patients')
        .insert(patientData)
        .select('id');

    await _supabase
        .from('profiles')
        .update({'clinic_id': clinicId})
        .eq('id', profileId);

    if (response.isEmpty) {
      throw Exception('Failed to create patient application.');
    }

    final row = Map<String, dynamic>.from(response.first);
    final patientId = row['id']?.toString();
    if (patientId == null || patientId.isEmpty) {
      throw Exception('Patient application ID is missing.');
    }

    return patientId;
  }

  Future<void> updatePatientApplication({
    required String patientId,
    required Map<String, Object?> updates,
  }) async {
    if (updates.isEmpty) return;

    await _supabase.from('patients').update(updates).eq('id', patientId);
  }
}
