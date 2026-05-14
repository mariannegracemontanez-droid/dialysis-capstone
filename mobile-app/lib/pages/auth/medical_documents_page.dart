import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/signup_data.dart';
import '../../services/auth/auth_service.dart';
import '../../services/file_upload_service.dart';

class MedicalDocumentsPage extends StatefulWidget {
  final SignupData signupData;

  const MedicalDocumentsPage({super.key, required this.signupData});

  @override
  State<MedicalDocumentsPage> createState() => _MedicalDocumentsPageState();
}

class _MedicalDocumentsPageState extends State<MedicalDocumentsPage> {
  final FileUploadService _fileUploadService = FileUploadService();
  late SignupData _signupData;
  final Map<String, String> _documentUrls = {};
  final Map<String, bool> _isUploading = {};
  String? _uploadError;
  bool _isInitializing = false;

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
    return _signupData.clinicRequirements.map((label) {
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
    _signupData = widget.signupData;
    _documentUrls.addAll(_signupData.documentUrls);
    _ensurePatientApplication();
  }

  Future<void> _ensurePatientApplication() async {
    if (_signupData.patientId.isNotEmpty) return;
    if (_signupData.profileId.isEmpty) return;

    setState(() {
      _isInitializing = true;
      _uploadError = null;
    });

    try {
      final patientId = await AuthService().createPatientRecord(
        profileId: _signupData.profileId,
        clinicId: _signupData.clinicId,
        fullName: _signupData.fullName,
        email: _signupData.email,
        phone: _signupData.phone,
        dateOfBirth: _signupData.dateOfBirth,
        homeAddress: _signupData.homeAddress,
        bloodType: _signupData.bloodType,
        emergencyContactName: _signupData.emergencyContactName,
        emergencyContactNumber: _signupData.emergencyContactNumber,
        ckdLevel: _signupData.ckdLevel,
        conditions: _signupData.conditions,
        insuranceOptions: _signupData.insuranceOptions,
        budgetRange: _signupData.budgetRange,
        preferredClinicType: _signupData.preferredClinicType,
        locationSummary: _signupData.locationSummary,
      );
      setState(() {
        _signupData = _signupData.copyWith(patientId: patientId);
      });
    } catch (e) {
      setState(() {
        _uploadError = e.toString();
      });
    } finally {
      setState(() {
        _isInitializing = false;
      });
    }
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

      final patientId = _signupData.patientId;

      if (patientId.isEmpty) {
        throw Exception('Unable to resolve patient application ID for upload.');
      }

      final url = await _fileUploadService.uploadMedicalDocumentImage(
        imageFile: file,
        patientId: patientId,
        clinicId: _signupData.clinicId,
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

    final updated = _signupData.copyWith(
      documentUrls: Map.from(_documentUrls),
      patientId: _signupData.patientId,
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
      backgroundColor: const Color(0xFFF3F7FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 20,
                      color: Color(0xFF2C5F7D),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Medical Documents',
                      style: TextStyle(
                        color: Color(0xFF173B4F),
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              const Text(
                'Upload the required documents requested by your chosen clinic.',
                style: TextStyle(
                  color: Color(0xFF6B7C86),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 22),

              Row(
                children: [
                  const Text(
                    'Step 4 of 5',
                    style: TextStyle(
                      color: Color(0xFF2C5F7D),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '80%',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.45),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: const LinearProgressIndicator(
                  value: 0.8,
                  minHeight: 8,
                  color: Color(0xFF2C5F7D),
                  backgroundColor: Color(0xFFDDEAF0),
                ),
              ),

              const SizedBox(height: 24),

              if (_isInitializing)
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F8FA),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE3EDF2)),
                  ),
                  child: Row(
                    children: const [
                      CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Color(0xFF2C5F7D),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Preparing your patient application. Please wait...',
                          style: TextStyle(
                            color: Color(0xFF173B4F),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE1EAF0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Submit Requirements',
                          style: TextStyle(
                            color: Color(0xFF173B4F),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),

                        const SizedBox(height: 6),

                        const Text(
                          'Accepted files are selected from your gallery and uploaded securely.',
                          style: TextStyle(
                            color: Color(0xFF7A8A94),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),

                        const SizedBox(height: 20),

                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F8FA),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE3EDF2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.folder_copy_outlined,
                                color: Color(0xFF2C5F7D),
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Uploaded: $uploadedCount / ${clinicRequirements.length}',
                                  style: const TextStyle(
                                    color: Color(0xFF173B4F),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 22),

                        const Text(
                          'Clinic Requirements',
                          style: TextStyle(
                            color: Color(0xFF173B4F),
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),

                        const SizedBox(height: 14),

                        if (clinicRequirements.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F8FA),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFE3EDF2),
                              ),
                            ),
                            child: const Text(
                              'No clinic requirements were selected. You may continue if you have no documents to upload.',
                              style: TextStyle(
                                color: Color(0xFF5B6D7D),
                                fontSize: 13,
                                height: 1.4,
                              ),
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
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.red.withOpacity(0.20),
                              ),
                            ),
                            child: Text(
                              _uploadError!,
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _isInitializing ? null : _handleNext,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: const Color(0xFF2C5F7D),
                    disabledBackgroundColor: const Color(
                      0xFF2C5F7D,
                    ).withOpacity(0.55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'NEXT',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: uploaded ? const Color(0xFFF0F8F5) : const Color(0xFFF4F8FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: uploaded ? const Color(0xFFBFE5D2) : const Color(0xFFE3EDF2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            uploaded ? Icons.check_circle_rounded : Icons.upload_file_outlined,
            color: uploaded ? const Color(0xFF2A9D65) : const Color(0xFF2C5F7D),
            size: 22,
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF173B4F),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),

          const SizedBox(width: 10),

          SizedBox(
            height: 38,
            child: ElevatedButton(
              onPressed: uploading ? null : onUpload,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: uploaded
                    ? const Color(0xFF2A9D65)
                    : const Color(0xFF2C5F7D),
                disabledBackgroundColor: const Color(
                  0xFF2C5F7D,
                ).withOpacity(0.5),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
                  : Text(
                      uploaded ? 'Replace' : 'Upload',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
