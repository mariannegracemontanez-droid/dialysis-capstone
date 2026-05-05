import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/signup_data.dart';
import '../../services/file_upload_service.dart';

class MedicalDocumentsPage extends StatefulWidget {
  final SignupData signupData;

  const MedicalDocumentsPage({super.key, required this.signupData});

  @override
  State<MedicalDocumentsPage> createState() => _MedicalDocumentsPageState();
}

class _MedicalDocumentsPageState extends State<MedicalDocumentsPage> {
  final FileUploadService _fileUploadService = FileUploadService();
  final Map<String, String> _documentUrls = {};
  final Map<String, bool> _isUploading = {};
  String? _uploadError;

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
    // System-level fields
    'status': 'status',
    'reviewed by': 'reviewed_by',
    'remarks': 'remarks',
    'uploaded_at': 'uploaded_at',
    'clinic id': 'clinic_id',
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

  static String _fallbackRequirementKey(String normalizedLabel) {
    final key = normalizedLabel
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    return key.isEmpty ? 'unknown_requirement' : key;
  }

  List<Map<String, String>> get _selectedClinicRequirements {
    return widget.signupData.clinicRequirements.map((label) {
      final normalizedLabel = _normalizeRequirementLabel(label);
      final key =
          _requirementKeyMap[normalizedLabel] ??
          _inferRequirementKey(normalizedLabel) ??
          _fallbackRequirementKey(normalizedLabel);

      return {'key': key, 'label': label};
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _documentUrls.addAll(widget.signupData.documentUrls);
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _pickDocumentFor(String requirementKey) async {
    setState(() {
      _isUploading[requirementKey] = true;
      _uploadError = null;
    });

    try {
      final XFile? file = await _fileUploadService.pickImage(
        source: ImageSource.gallery,
      );

      if (file == null) {
        setState(() {
          _isUploading[requirementKey] = false;
          _uploadError = 'No file selected.';
        });
        return;
      }

      final patientId = widget.signupData.patientId.isNotEmpty
          ? widget.signupData.patientId
          : Supabase.instance.client.auth.currentUser?.id;

      if (patientId == null || patientId.isEmpty) {
        throw Exception('Unable to resolve patient ID for upload.');
      }

      final url = await _fileUploadService.uploadMedicalDocumentImage(
        imageFile: file,
        patientId: patientId,
        clinicId: widget.signupData.clinicId,
      );

      setState(() {
        _documentUrls[requirementKey] = url;
        _isUploading[requirementKey] = false;
        _uploadError = null;
      });
    } catch (e, stack) {
      setState(() {
        _isUploading[requirementKey] = false;
        _uploadError = e.toString();
      });
      debugPrint('Error uploading document: $e');
      debugPrint(stack.toString());
    }
  }

  void _handleNext() {
    final clinicRequirements = _selectedClinicRequirements;
    final uploadedCount = clinicRequirements
        .where((item) => _documentUrls[item['key']]?.isNotEmpty ?? false)
        .length;
    final requiredCount = clinicRequirements.length >= 5
        ? 5
        : clinicRequirements.length;

    if (clinicRequirements.isNotEmpty && uploadedCount < requiredCount) {
      setState(() {
        final remaining = requiredCount - uploadedCount;
        _uploadError = remaining == 1
            ? 'Please upload the remaining document before continuing.'
            : 'Please upload $remaining more required documents before continuing.';
      });
      return;
    }

    final updated = widget.signupData.copyWith(
      documentUrls: Map.from(_documentUrls),
    );
    Navigator.of(context).pushNamed('/financial', arguments: updated);
  }

  @override
  Widget build(BuildContext context) {
    final clinicRequirements = _selectedClinicRequirements;
    final uploadedCount = clinicRequirements
        .where((item) => _documentUrls[item['key']]?.isNotEmpty ?? false)
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F9FB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Color(0xFF2C5F7D),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Your medical background',
                    style: TextStyle(
                      color: Color(0xFF2C5F7D),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: 0.83,
                color: const Color(0xFF2C5F7D),
                backgroundColor: const Color(0xFFE7F0F3),
                minHeight: 8,
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 4,
                  shadowColor: Colors.black.withOpacity(0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Do you have existing medical records?',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Upload medical reports or referral notes from your hospital or doctor.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            clinicRequirements.isEmpty
                                ? 'No clinic-specific requirements were selected. Upload any relevant medical documents you have.'
                                : 'Upload the documents requested by your chosen clinic.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Uploaded: $uploadedCount / ${clinicRequirements.length}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF2C5F7D),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${clinicRequirements.length} required',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF6C7A8E),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Clinic requirements',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (clinicRequirements.isEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 18,
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF4F8),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Text(
                                'No clinic requirements were selected. You may continue if you have no documents to upload.',
                                style: TextStyle(fontSize: 14),
                              ),
                            )
                          else
                            ...clinicRequirements.map((item) {
                              final key = item['key']!;
                              final label = item['label']!;
                              final uploaded =
                                  _documentUrls[key]?.isNotEmpty ?? false;
                              final uploading = _isUploading[key] == true;
                              return _buildRequirementRow(
                                label: label,
                                uploaded: uploaded,
                                uploading: uploading,
                                onUpload: () => _pickDocumentFor(key),
                              );
                            }),
                          if (_uploadError != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _uploadError!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _handleNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2C5F7D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text('Next'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRequirementRow({
    required String label,
    required bool uploaded,
    required bool uploading,
    required VoidCallback onUpload,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            uploaded ? Icons.check_circle : Icons.radio_button_unchecked,
            color: uploaded ? const Color(0xFF2C5F7D) : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          const SizedBox(width: 10),
          SizedBox(
            height: 38,
            child: ElevatedButton(
              onPressed: uploading ? null : onUpload,
              style: ElevatedButton.styleFrom(
                backgroundColor: uploaded
                    ? const Color(0xFF2C5F7D)
                    : const Color(0xFF4F82A4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                minimumSize: const Size(100, 38),
              ),
              child: uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(uploaded ? 'Replace' : 'Upload'),
            ),
          ),
        ],
      ),
    );
  }
}
