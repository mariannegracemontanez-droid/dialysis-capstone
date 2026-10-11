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

  static const Map<String, String> _requirementKeyMap = {
    'referral letter / endorsement letter / discharge summary':
        'referral_letter_url',
    'referral letter / endorsement letter / discharge summary / medical abstract':
        'referral_letter_url',
    'medical abstract': 'medical_abstract_url',
    'hd treatment sheets': 'hd_treatment_sheets_url',
    'laboratory results': 'lab_results_url',
    'hepatitis profile': 'hepatitis_profile_url',
    'x-ray / imaging report': 'xray_url',
    'government id': 'government_id_url',
    'philhealth mdr': 'philhealth_mdr_url',
    'pdd certificate': 'pdd_certificate_url',
    'phic consumption report': 'phic_consumption_url',
    'phic contribution report': 'phic_contribution_url',
  };

  static String _normalizeRequirementLabel(String label) {
    return label
        .toLowerCase()
        .replaceAll(RegExp(r'\s*/\s*'), ' / ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String? _inferRequirementKey(String normalizedLabel) {
    if (normalizedLabel.contains('referral letter') ||
        normalizedLabel.contains('endorsement letter') ||
        normalizedLabel.contains('discharge summary')) {
      return 'referral_letter_url';
    }
    if (normalizedLabel.contains('medical abstract')) {
      return 'medical_abstract_url';
    }
    if (normalizedLabel.contains('hd treatment')) {
      return 'hd_treatment_sheets_url';
    }
    if (normalizedLabel.contains('laboratory')) {
      return 'lab_results_url';
    }
    if (normalizedLabel.contains('hepatitis profile')) {
      return 'hepatitis_profile_url';
    }
    if (normalizedLabel.contains('x-ray') ||
        normalizedLabel.contains('xray') ||
        normalizedLabel.contains('imaging')) {
      return 'xray_url';
    }
    if (normalizedLabel.contains('government id')) {
      return 'government_id_url';
    }
    if (normalizedLabel.contains('philhealth mdr')) {
      return 'philhealth_mdr_url';
    }
    if (normalizedLabel.contains('pdd')) {
      return 'pdd_certificate_url';
    }
    if (normalizedLabel.contains('phic consumption')) {
      return 'phic_consumption_url';
    }
    if (normalizedLabel.contains('phic contribution')) {
      return 'phic_contribution_url';
    }
    return null;
  }

  /// The `medical_documents` column a clinic requirement label is stored
  /// in. Labels without a matching column get a derived key, which
  /// [saveDocumentUrls] does not persist.
  static String columnForRequirement(String label) {
    final normalizedLabel = _normalizeRequirementLabel(label);
    final known =
        _requirementKeyMap[normalizedLabel] ??
        _inferRequirementKey(normalizedLabel);
    if (known != null) return known;

    final key = normalizedLabel
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    return key.isEmpty ? 'unknown_requirement' : key;
  }

  /// Uploaded documents in a `medical_documents` row, in display order.
  static List<MapEntry<String, String>> uploadedDocuments(
    Map<String, dynamic>? row,
  ) {
    if (row == null) return const [];
    return [
      for (final column in allDocumentColumns)
        if ((row[column]?.toString() ?? '').isNotEmpty)
          MapEntry(column, row[column].toString()),
    ];
  }

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
