import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

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

  Future<List<Map<String, dynamic>>> getPendingApplications(
    String profileId,
  ) async {
    final response = await _supabase
        .from('patients')
        .select('id, clinic_id, status, decline_reason, created_at')
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

    final clinicMap = <String, String>{};
    if (clinicIds.isNotEmpty) {
      final clinicResponse = await _supabase
          .from('clinics')
          .select('id, name')
          .inFilter('id', clinicIds);

      for (final clinic in List<Map<String, dynamic>>.from(
        clinicResponse as List<dynamic>,
      )) {
        final id = clinic['id']?.toString();
        final name = clinic['name']?.toString() ?? 'Clinic';
        if (id != null) {
          clinicMap[id] = name;
        }
      }
    }

    return rows.map((row) {
      final clinicId = row['clinic_id']?.toString();
      return {...row, 'clinic_name': clinicMap[clinicId] ?? 'Clinic'};
    }).toList();
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
    required String fullName,
    required String email,
    required String phone,
    required String dateOfBirth,
    required String homeAddress,
    required String bloodType,
    required String emergencyContactName,
    required String emergencyContactNumber,
    required String ckdLevel,
    required List<String> conditions,
    required List<String> insuranceOptions,
    required String budgetRange,
    required String preferredClinicType,
    required String locationSummary,
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

    final trimmedDob = dateOfBirth.trim();
    String? formattedDob;
    if (trimmedDob.isNotEmpty) {
      final parsedDob = DateTime.tryParse(trimmedDob);
      if (parsedDob != null) {
        formattedDob = parsedDob.toIso8601String().split('T').first;
      }
    }

    final selectedCondition = conditions.contains('None') || conditions.isEmpty
        ? 'None'
        : conditions.firstWhere(
            (condition) => condition != 'None',
            orElse: () => 'None',
          );

    final insuranceText = insuranceOptions.isNotEmpty
        ? insuranceOptions.join(', ')
        : 'None';

    final patientData = <String, Object?>{
      'profile_id': profileId,
      'clinic_id': clinicId,
      'status': 'pending',
      'full_name': fullName,
      'email': email,
      'phone': phone,
      'home_address': homeAddress,
      'blood_type': bloodType,
      'emergency_contact_name': emergencyContactName,
      'emergency_contact_number': emergencyContactNumber,
      'dialysis_stage': ckdLevel,
      'existing_condition': selectedCondition,
      'budget': budgetRange,
      'insurance': insuranceText,
      'financial_support': insuranceText,
      'preferred_clinic': preferredClinicType,
      'user_location': locationSummary,
      'created_at': DateTime.now().toIso8601String(),
    };

    if (formattedDob != null) {
      patientData['date_of_birth'] = formattedDob;
    }

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
