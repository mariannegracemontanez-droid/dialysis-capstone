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

  /// The patient lifecycle, as already defined in the database:
  ///
  ///   pending  -> not yet reviewed by this center
  ///   no_sched -> accepted/reserved here, no recurring schedule yet
  ///   active   -> accepted AND holds an active recurring schedule
  ///   declined / deleted -> no longer reserved
  ///
  /// `no_sched` and `active` are exactly the two the Super Admin capacity
  /// estimate counts as reserved for a clinic, so every transition below
  /// has to actually land in the database -- a silently-skipped update
  /// would leave that estimate wrong with no visible error.
  static const String statusPending = 'pending';
  static const String statusNoSchedule = 'no_sched';
  static const String statusActive = 'active';
  static const String statusDeclined = 'declined';
  static const String statusDeleted = 'deleted';

  /// Applies a status change to one patient at the admin's own clinic and
  /// PROVES it landed.
  ///
  /// The `.select()` is the important part. With RLS on, an UPDATE that
  /// matches no row is not an error -- it quietly affects zero rows. So a
  /// patient belonging to another clinic, a patient whose clinic_id is
  /// null, a missing RLS policy, or a patient who is no longer in the
  /// expected status all used to report "accepted" while nothing changed.
  /// This is the same failure mode already documented for daily_schedules
  /// in supabase/daily_schedules_update_policy.sql.
  ///
  /// [expectedStatuses] guards the transition itself, so a status can only
  /// move along the intended path (an already-scheduled `active` patient
  /// can never be knocked back to `no_sched` by a stray Accept, which
  /// would orphan their recurring schedule).
  Future<Map<String, dynamic>> _applyStatusChange({
    required String patientId,
    required String newStatus,
    required List<String> expectedStatuses,
    Map<String, dynamic> extraFields = const {},
    required String failureMessage,
  }) async {
    final clinicId = await getCurrentClinicId();

    if (clinicId == null) {
      throw Exception('No clinic assigned to this admin account.');
    }

    final updated = await client
        .from('patients')
        .update({
          'status': newStatus,
          // Written explicitly, not just filtered on: the row is
          // guaranteed to end up owned by the clinic that made the
          // decision, which is what the Super Admin capacity estimate
          // groups by. A no-op on already-correct data.
          'clinic_id': clinicId,
          ...extraFields,
        })
        .eq('id', patientId)
        .eq('clinic_id', clinicId)
        .inFilter('status', expectedStatuses)
        .select('id, status, clinic_id');

    if (updated.isEmpty) {
      // Work out which of the two reasons it was, so the admin gets a
      // real explanation instead of a generic failure.
      final current = await client
          .from('patients')
          .select('status, clinic_id')
          .eq('id', patientId)
          .maybeSingle();

      if (current == null) {
        throw Exception('This patient record could not be found.');
      }

      if (current['clinic_id']?.toString() != clinicId) {
        throw Exception(
          'This patient is not registered at your center, so their record '
          'cannot be changed here.',
        );
      }

      throw Exception(
        '$failureMessage (the patient is currently '
        '"${current['status'] ?? 'unknown'}"). The list has probably changed '
        'since it was loaded — refresh and try again.',
      );
    }

    return Map<String, dynamic>.from(updated.first);
  }

  Future<void> updatePatientStatus(String patientId, String newStatus) async {
    await _applyStatusChange(
      patientId: patientId,
      newStatus: newStatus,
      expectedStatuses: const [
        statusPending,
        statusNoSchedule,
        statusActive,
        statusDeclined,
      ],
      failureMessage: 'This patient\'s status could not be updated',
    );
  }

  /// Accept a pending application: the patient becomes RESERVED at this
  /// clinic (`no_sched`) and their clinic_id is pinned to it.
  ///
  /// Deliberately NOT `active` -- that is earned only by successfully
  /// saving a recurring schedule (set_patient_recurring_schedule). Only a
  /// `pending` patient can be accepted.
  Future<void> acceptPatient(String patientId) async {
    await _applyStatusChange(
      patientId: patientId,
      newStatus: statusNoSchedule,
      expectedStatuses: const [statusPending],
      failureMessage: 'Only a pending patient can be accepted',
    );
  }

  Future<void> declinePatient(String patientId) async {
    await _applyStatusChange(
      patientId: patientId,
      newStatus: statusDeclined,
      expectedStatuses: const [statusPending],
      failureMessage: 'Only a pending patient can be declined',
    );
  }

  Future<void> declinePatientWithReason({
    required String patientId,
    required String reason,
  }) async {
    await _applyStatusChange(
      patientId: patientId,
      newStatus: statusDeclined,
      expectedStatuses: const [statusPending],
      extraFields: {'decline_reason': reason},
      failureMessage: 'Only a pending patient can be declined',
    );
  }

  Future<void> deletePatientWithReason({
    required String patientId,
    required String reason,
    DateTime? deletedAt,
  }) async {
    await _applyStatusChange(
      patientId: patientId,
      newStatus: statusDeleted,
      expectedStatuses: const [
        statusPending,
        statusNoSchedule,
        statusActive,
        statusDeclined,
      ],
      extraFields: {
        'delete_reason': reason,
        if (deletedAt != null) 'deleted_at': deletedAt.toIso8601String(),
      },
      failureMessage: 'This patient could not be removed',
    );
  }

  // There is deliberately no "mark this patient active" method. A patient
  // becomes `active` in exactly one place -- inside the
  // set_patient_recurring_schedule database function, in the same
  // transaction that writes weekly_schedules + patient_schedule_days -- so
  // `active` can never mean anything other than "has a recurring schedule
  // that was actually saved". The previous activatePatient() helper set the
  // status on its own, with no schedule and no caller.

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
