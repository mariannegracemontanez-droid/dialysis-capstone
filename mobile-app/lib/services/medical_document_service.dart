import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class MedicalDocumentService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  static const List<String> _allDocumentColumns = [
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

  Future<void> saveDocumentUrls({
    required String userId,
    required Object? clinicId,
    required Map<String, String> documentUrls,
  }) async {
    if (documentUrls.isEmpty) return;

    final row = <String, dynamic>{
      'profile_id': userId,
      'clinic_id': clinicId,
      'updated_at': DateTime.now().toIso8601String(),
    };

    for (final column in _allDocumentColumns) {
      row[column] = documentUrls[column];
    }

    for (final entry in documentUrls.entries) {
      if (!row.containsKey(entry.key)) {
        row[entry.key] = entry.value;
      }
    }

    await _supabase
        .from('medical_document')
        .upsert(row, onConflict: 'profile_id, clinic_id');
  }
}
