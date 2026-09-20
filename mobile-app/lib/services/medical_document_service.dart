import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class MedicalDocumentService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  static const List<String> allDocumentColumns = [
    'referral_letter_url',
    'medical_abstract_url',
    'hd_treatment_sheets_url',
    'lab_results_url',
    'hepatitis_profile_url',
    'xray_url',
    'government_id_url',
    'philhealth_mdr_url',
    'pdd_certificate_url',
    'phic_consumption_url',
    'phic_contribution_url',
  ];

  /// Human-readable labels for each document URL column, for display on the
  /// Medical Records page and in the "Download My Data" export.
  static const Map<String, String> documentLabels = {
    'referral_letter_url':
        'Referral Letter / Endorsement Letter / Discharge Summary',
    'medical_abstract_url': 'Medical Abstract',
    'hd_treatment_sheets_url': 'HD Treatment Sheets',
    'lab_results_url': 'Laboratory Results',
    'hepatitis_profile_url': 'Hepatitis Profile',
    'xray_url': 'X-Ray / Imaging Report',
    'government_id_url': 'Government ID',
    'philhealth_mdr_url': 'PhilHealth MDR',
    'pdd_certificate_url': 'PDD Certificate',
    'phic_consumption_url': 'PHIC Consumption Report',
    'phic_contribution_url': 'PHIC Contribution Report',
  };

  Future<void> saveDocumentUrls({
    required String patientId,
    required Object? clinicId,
    required Map<String, String> documentUrls,
  }) async {
    if (documentUrls.isEmpty) return;

    final row = <String, dynamic>{
      'patient_id': patientId,
      'clinic_id': clinicId,
      'uploaded_at': DateTime.now().toIso8601String(),
    };

    for (final column in allDocumentColumns) {
      row[column] = documentUrls[column];
    }

    await _supabase
        .from('medical_documents')
        .upsert(row, onConflict: 'patient_id, clinic_id');
  }

  /// Reads back the submitted document URLs (plus the shared `uploaded_at`
  /// date for that upload batch) for a given patient/clinic pair.
  Future<Map<String, dynamic>?> getDocuments({
    required String patientId,
    required Object? clinicId,
  }) async {
    if (clinicId != null) {
      final scoped = await _supabase
          .from('medical_documents')
          .select()
          .eq('patient_id', patientId)
          .eq('clinic_id', clinicId)
          .maybeSingle();

      if (scoped != null) {
        return Map<String, dynamic>.from(scoped);
      }
    }

    // Fall back to the most recent upload for this patient — covers cases
    // where clinic_id types/values don't line up exactly between the
    // `patients` and `medical_documents` rows.
    final response = await _supabase
        .from('medical_documents')
        .select()
        .eq('patient_id', patientId)
        .order('uploaded_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;

    return Map<String, dynamic>.from(response);
  }
}
